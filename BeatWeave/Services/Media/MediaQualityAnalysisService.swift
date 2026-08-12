@preconcurrency import AVFoundation
import AppKit
import Foundation
import Vision

enum MediaQualityAnalysisError: LocalizedError {
    case noVideoTrack
    case noSampleFrames

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "素材没有可分析的视频轨。"
        case .noSampleFrames: "无法从素材读取用于质量分析的画面。"
        }
    }
}

/// Deliberately sparse analysis: it samples three frames instead of decoding a full video.
actor MediaQualityAnalysisService {
    private let resolver = MediaSourceResolver()

    func analyze(_ media: MediaReference) async throws -> MediaQualityAnalysis {
        guard media.kind == .video else { throw MediaQualityAnalysisError.noVideoTrack }
        let url = try await resolver.resolvedURL(for: media)
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.load(.tracks)
        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            throw MediaQualityAnalysisError.noVideoTrack
        }
        let duration = try await asset.load(.duration).seconds
        let size = try await videoTrack.load(.naturalSize)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = NSSize(width: 320, height: 320)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)

        let fractions = [0.15, 0.5, 0.85]
        var luminances: [Double] = []
        var faceHits = 0
        for fraction in fractions {
            let time = CMTime(seconds: max(0, duration * fraction), preferredTimescale: 600)
            guard let image = try? await generator.image(at: time).image else { continue }
            luminances.append(averageLuminance(of: image))
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: image)
            try? handler.perform([request])
            if !(request.results ?? []).isEmpty { faceHits += 1 }
        }
        guard !luminances.isEmpty else { throw MediaQualityAnalysisError.noSampleFrames }

        let visual = min(1, max(0, (log2(max(1, Double(abs(size.width * size.height)))) - 16) / 6))
        let frameRateScore = min(1, max(0, Double(frameRate) / 30))
        let quality = (visual * 0.75) + (frameRateScore * 0.25)
        let motion = averageDelta(luminances)
        let face = Double(faceHits) / Double(luminances.count)
        let overall = min(1, (quality * 0.55) + (motion * 0.25) + (face * 0.20))
        let rangeDuration = max(0.1, duration / Double(luminances.count))
        let rangeScores = luminances.enumerated().map { index, luminance in
            MediaRangeScore(
                id: UUID(),
                sourceRange: MediaTimeRange(
                    start: TimelineTime(seconds: Double(index) * rangeDuration),
                    duration: TimelineTime(seconds: rangeDuration)
                ),
                score: min(1, max(0, (overall * 0.8) + (luminance * 0.2)))
            )
        }
        return MediaQualityAnalysis(
            overallScore: overall,
            visualQualityScore: quality,
            motionScore: motion,
            faceScore: face,
            rangeScores: rangeScores
        )
    }

    private func averageLuminance(of image: CGImage) -> Double {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        else { return 0.5 }
        let row = max(1, image.bytesPerRow)
        let stepX = max(1, image.width / 8)
        let stepY = max(1, image.height / 8)
        let components = max(1, image.bitsPerPixel / max(1, image.bitsPerComponent))
        var sum = 0.0
        var count = 0.0
        for y in stride(from: 0, to: image.height, by: stepY) {
            for x in stride(from: 0, to: image.width, by: stepX) {
                let offset = (y * row) + (x * components)
                let red = Double(bytes[offset])
                let green = Double(bytes[offset + min(1, components - 1)])
                let blue = Double(bytes[offset + min(2, components - 1)])
                sum += (red * 0.2126) + (green * 0.7152) + (blue * 0.0722)
                count += 1
            }
        }
        return count > 0 ? sum / (count * 255) : 0.5
    }

    private func averageDelta(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let deltas = zip(values, values.dropFirst()).map { abs($0 - $1) }
        return min(1, (deltas.reduce(0, +) / Double(deltas.count)) * 8)
    }
}
