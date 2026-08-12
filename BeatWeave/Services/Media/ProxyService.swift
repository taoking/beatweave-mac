@preconcurrency import AVFoundation
import Foundation

enum ProxyServiceError: LocalizedError {
    case cannotCreateSession
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotCreateSession:
            "无法为该素材创建代理生成任务。"
        case let .exportFailed(message):
            "代理生成失败：\(message)"
        }
    }
}

struct GeneratedProxy: Sendable {
    var data: Data
    var info: ProxyMediaInfo
}

/// A proxy is a cache-only H.264 rendition. Export services never receive this URL.
actor ProxyService {
    private let resolver = MediaSourceResolver()

    func generate(for media: MediaReference) async throws -> GeneratedProxy {
        let sourceURL = try await resolver.resolvedURL(for: media)
        let accessGranted = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessGranted { sourceURL.stopAccessingSecurityScopedResource() } }

        return try await MediaGenerationQueue.shared.perform {
            try await Self.generateProxy(sourceURL: sourceURL, media: media)
        }
    }

    private static func generateProxy(sourceURL: URL, media: MediaReference) async throws -> GeneratedProxy {
        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            throw ProxyServiceError.cannotCreateSession
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeatWeave-proxy-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        do {
            try await session.export(to: outputURL, as: .mp4)
        } catch {
            throw ProxyServiceError.exportFailed(error.localizedDescription)
        }
        let data = try Data(contentsOf: outputURL)
        let dimensions = proxyDimensions(for: media.videoMetadata)
        return GeneratedProxy(
            data: data,
            info: ProxyMediaInfo(
                cacheFilename: "\(media.id.uuidString).mp4",
                width: dimensions.width,
                height: dimensions.height,
                codec: .h264
            )
        )
    }

    private static func proxyDimensions(for metadata: VideoMetadata?) -> (width: Int, height: Int) {
        guard let metadata, metadata.width > 0, metadata.height > 0 else { return (960, 540) }
        let maximumDimension = 960.0
        let scale = min(1, maximumDimension / Double(max(metadata.width, metadata.height)))
        return (
            max(2, Int((Double(metadata.width) * scale).rounded()) / 2 * 2),
            max(2, Int((Double(metadata.height) * scale).rounded()) / 2 * 2)
        )
    }
}
