import AVFoundation
import Foundation
import UniformTypeIdentifiers

struct ImportedMedia: Sendable {
    let reference: MediaReference
}

enum MediaImportError: LocalizedError {
    case unsupportedMedia(URL)
    case unreadableDuration(URL)

    var errorDescription: String? {
        switch self {
        case let .unsupportedMedia(url):
            "“\(url.lastPathComponent)”不包含可用的视频或音频轨道。"
        case let .unreadableDuration(url):
            "无法读取“\(url.lastPathComponent)”的有效时长。"
        }
    }
}

actor MediaImportService {
    static let supportedContentTypes: [UTType] = [
        .movie,
        .video,
        .audio,
        .mpeg4Movie,
        .quickTimeMovie,
        .mpeg4Audio,
        .mp3,
        .wav
    ]

    func `import`(url: URL) async throws -> ImportedMedia {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds
        guard durationSeconds.isFinite, durationSeconds >= 0 else {
            throw MediaImportError.unreadableDuration(url)
        }

        let tracks = try await asset.load(.tracks)
        let videoTrack = tracks.first { $0.mediaType == .video }
        let audioTrack = tracks.first { $0.mediaType == .audio }
        guard videoTrack != nil || audioTrack != nil else {
            throw MediaImportError.unsupportedMedia(url)
        }

        let videoMetadata = try await metadata(for: videoTrack)
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let timescale = duration.timescale > 0 ? duration.timescale : 600
        let reference = MediaReference(
            displayName: url.lastPathComponent,
            originalURL: url,
            securityScopedBookmark: bookmark,
            kind: videoTrack == nil ? .audio : .video,
            duration: TimelineTime(seconds: durationSeconds, timescale: timescale),
            videoMetadata: videoMetadata
        )
        return ImportedMedia(reference: reference)
    }

    private func metadata(for videoTrack: AVAssetTrack?) async throws -> VideoMetadata? {
        guard let videoTrack else {
            return nil
        }
        let naturalSize = try await videoTrack.load(.naturalSize)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        return VideoMetadata(
            width: Int(naturalSize.width.rounded()),
            height: Int(naturalSize.height.rounded()),
            nominalFrameRate: Double(frameRate)
        )
    }
}
