@preconcurrency import AVFoundation
import CoreImage
import Foundation

struct PreparedVideoSource: Sendable {
    var url: URL
    var sourceRange: MediaTimeRange
    var temporaryURL: URL?
}

enum ColorRenderServiceError: LocalizedError {
    case cannotCreateSession
    case compositionFailed(String)
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotCreateSession: "无法为调色创建视频处理会话。"
        case let .compositionFailed(message): "无法创建调色视频合成：\(message)"
        case let .renderFailed(message): "无法渲染调色视频：\(message)"
        }
    }
}

private struct ClipColorRenderConfiguration: Sendable {
    let adjustments: ClipColorAdjustments
    let cube: LUTCube?
    let cubeIntensity: Double

    init(appearance: ClipAppearance?) throws {
        let appearance = appearance ?? .default
        adjustments = appearance.color
        if let lut = appearance.lut, lut.intensity > 0 {
            cube = try LUTCube.load(from: lut)
            cubeIntensity = lut.intensity
        } else {
            cube = nil
            cubeIntensity = 0
        }
    }

    var requiresRendering: Bool {
        adjustments != .neutral || cube != nil
    }

    func apply(to sourceImage: CIImage) -> CIImage {
        var image = sourceImage
        if adjustments.exposure != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: adjustments.exposure
            ])
        }
        if adjustments.contrast != 1 || adjustments.saturation != 1 {
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: adjustments.contrast,
                kCIInputSaturationKey: adjustments.saturation
            ])
        }
        if adjustments.temperature != 0 || adjustments.tint != 0 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6_500, y: 0),
                "inputTargetNeutral": CIVector(
                    x: 6_500 + (adjustments.temperature * 2_000),
                    y: adjustments.tint * 500
                )
            ])
        }
        if adjustments.highlights != 0 || adjustments.shadows != 0 {
            image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": min(1, max(0, 1 - (adjustments.highlights * 0.75))),
                "inputShadowAmount": max(0, adjustments.shadows)
            ])
            if adjustments.shadows < 0 {
                image = image.applyingFilter("CIExposureAdjust", parameters: [
                    kCIInputEVKey: adjustments.shadows * 0.5
                ])
            }
        }
        if let cube {
            image = image.applyingFilter("CIColorCube", parameters: [
                "inputCubeDimension": cube.dimension,
                "inputCubeData": cube.colorCubeData(intensity: cubeIntensity)
            ])
        }
        return image
    }
}

/// Renders color-adjusted clips to short, private temporary MP4 sources before
/// the canonical AVFoundation composition performs geometry and transitions.
/// This keeps Core Image's filter-only composition separate from the basic
/// multi-track compositor, which AVFoundation requires.
struct ColorRenderService {
    func prepare(
        segment: ExportVideoSegment,
        sourceURL: URL
    ) async throws -> PreparedVideoSource {
        let configuration = try ClipColorRenderConfiguration(appearance: segment.clip.appearance)
        guard configuration.requiresRendering else {
            return PreparedVideoSource(url: sourceURL, sourceRange: segment.clip.sourceRange, temporaryURL: nil)
        }

        let asset = AVURLAsset(url: sourceURL)
        let videoComposition = try await makeVideoComposition(asset: asset, configuration: configuration)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ColorRenderServiceError.cannotCreateSession
        }
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeatWeave-color-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        do {
            session.videoComposition = videoComposition
            session.timeRange = segment.clip.sourceRange.cmTimeRange
            try await session.export(to: temporaryURL, as: .mp4)
            return PreparedVideoSource(
                url: temporaryURL,
                sourceRange: MediaTimeRange(start: .zero, duration: segment.clip.sourceRange.duration),
                temporaryURL: temporaryURL
            )
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw ColorRenderServiceError.renderFailed(error.localizedDescription)
        }
    }

    private func makeVideoComposition(
        asset: AVAsset,
        configuration: ClipColorRenderConfiguration
    ) async throws -> AVVideoComposition {
        try await withCheckedThrowingContinuation { continuation in
            AVVideoComposition.videoComposition(
                with: asset,
                applyingCIFiltersWithHandler: { request in
                    request.finish(with: configuration.apply(to: request.sourceImage), context: nil)
                },
                completionHandler: { composition, error in
                    if let composition {
                        continuation.resume(returning: composition)
                    } else {
                        continuation.resume(throwing: ColorRenderServiceError.compositionFailed(error?.localizedDescription ?? "未知错误"))
                    }
                }
            )
        }
    }
}

private extension TimelineTime {
    var cmTime: CMTime {
        CMTime(value: CMTimeValue(value), timescale: CMTimeScale(timescale))
    }
}

private extension MediaTimeRange {
    var cmTimeRange: CMTimeRange {
        CMTimeRange(start: start.cmTime, duration: duration.cmTime)
    }
}
