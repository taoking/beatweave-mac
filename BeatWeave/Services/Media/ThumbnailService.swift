import AVFoundation
import AppKit
import Foundation

enum ThumbnailError: LocalizedError {
    case unsupportedMedia(URL)
    case encodingFailed(URL)

    var errorDescription: String? {
        switch self {
        case let .unsupportedMedia(url):
            "无法从“\(url.lastPathComponent)”生成缩略图。"
        case let .encodingFailed(url):
            "无法编码“\(url.lastPathComponent)”的缩略图。"
        }
    }
}

actor ThumbnailService {
    func makePNGThumbnail(for media: MediaReference, maximumDimension: CGFloat = 480) async throws -> Data? {
        guard media.kind == .video else {
            return nil
        }

        let url = media.originalURL
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = NSSize(width: maximumDimension, height: maximumDimension)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .positiveInfinity

        let image: CGImage
        do {
            image = try await generator.image(at: .zero).image
        } catch {
            throw ThumbnailError.unsupportedMedia(url)
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ThumbnailError.encodingFailed(url)
        }
        return png
    }
}
