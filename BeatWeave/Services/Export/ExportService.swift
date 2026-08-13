@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import os

enum ExportServiceError: LocalizedError, Equatable {
    case outputAlreadyExists(URL)
    case cannotCreateSession
    case unsupportedCodec(ExportCodec)
    case exportFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case let .outputAlreadyExists(url):
            "“\(url.lastPathComponent)”已存在，请选择新文件名。"
        case .cannotCreateSession:
            "无法为当前时间线创建视频导出会话。"
        case let .unsupportedCodec(codec):
            "此设备不支持 \(codec.displayName) 导出。"
        case let .exportFailed(message):
            "视频导出失败：\(message)"
        case .cancelled:
            "导出已取消。"
        }
    }
}

extension ExportCodec {
    var displayName: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC"
        }
    }
}

extension ExportQuality {
    var displayName: String {
        switch self {
        case .medium: "中等"
        case .high: "高"
        }
    }
}

struct ExportResult: Sendable {
    var outputURL: URL
    var duration: TimelineTime
}

actor ExportService {
    private let resolver = MediaSourceResolver()
    private let logger = Logger(subsystem: "com.taoking.BeatWeave", category: "export")
    private var activeSession: AVAssetExportSession?
    private var cancellationRequested = false

    func export(project: ProjectFile, to outputURL: URL) async throws -> ExportResult {
        let plan = try ExportTimelinePlanner.makePlan(for: project)
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ExportServiceError.outputAlreadyExists(outputURL)
        }
        let temporaryURL = makeTemporaryURL(for: outputURL)
        let scopedURLs = try await scopedURLs(for: plan)
        defer {
            scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }

        let composition = try await CompositionBuilder(resolver: resolver).build(
            plan: plan,
            settings: project.exportSettings
        )
        defer {
            for url in composition.temporaryVideoURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let presetName = exportPreset(for: project.exportSettings.codec, quality: project.exportSettings.quality)
        guard let session = AVAssetExportSession(asset: composition.composition, presetName: presetName) else {
            throw ExportServiceError.cannotCreateSession
        }
        activeSession = session
        cancellationRequested = false
        defer {
            activeSession = nil
        }
        session.videoComposition = composition.videoComposition
        session.audioMix = composition.audioMix

        let startedAt = Date()
        try await run(session, to: temporaryURL)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        let elapsedMilliseconds = Int((Date().timeIntervalSince(startedAt) * 1_000).rounded())
        logger.info(
            "export complete duration=\(plan.duration.seconds, privacy: .public)s codec=\(project.exportSettings.codec.rawValue, privacy: .public) size=\(project.exportSettings.width, privacy: .public)x\(project.exportSettings.height, privacy: .public) fps=\(project.exportSettings.frameRate.rawValue, privacy: .public) elapsedMs=\(elapsedMilliseconds, privacy: .public)"
        )
        return ExportResult(outputURL: outputURL, duration: plan.duration)
    }

    func progress() -> Double? {
        activeSession.map { min(1, max(0, Double($0.progress))) }
    }

    func cancel() {
        cancellationRequested = true
        activeSession?.cancelExport()
    }

    private func scopedURLs(for plan: ExportTimelinePlan) async throws -> [URL] {
        let media = plan.videoSegments.map(\.media)
            + plan.audioSegments.map(\.media)
            + (plan.musicSegment.map { [$0.media] } ?? [])
        var scopedURLs: [URL] = []
        for mediaReference in Dictionary(uniqueKeysWithValues: media.map { ($0.id, $0) }).values {
            let url = try await resolver.resolvedURL(for: mediaReference)
            if url.startAccessingSecurityScopedResource() {
                scopedURLs.append(url)
            }
        }
        return scopedURLs
    }

    private func run(_ session: AVAssetExportSession, to url: URL) async throws {
        do {
            try await session.export(to: url, as: .mp4)
        } catch is CancellationError {
            throw ExportServiceError.cancelled
        } catch {
            if cancellationRequested || Task.isCancelled {
                throw ExportServiceError.cancelled
            }
            throw ExportServiceError.exportFailed(error.localizedDescription)
        }
    }

    private func exportPreset(
        for codec: ExportCodec,
        quality: ExportQuality
    ) -> String {
        switch (codec, quality) {
        case (.h264, .medium): AVAssetExportPresetMediumQuality
        case (.h264, .high): AVAssetExportPresetHighestQuality
        case (.hevc, .medium): AVAssetExportPresetHEVC1920x1080
        case (.hevc, .high): AVAssetExportPresetHEVCHighestQuality
        }
    }

    private func makeTemporaryURL(for outputURL: URL) -> URL {
        outputURL
            .deletingPathExtension()
            .appendingPathExtension("partial-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
    }
}

struct BuiltComposition {
    var composition: AVMutableComposition
    var videoComposition: AVVideoComposition
    var audioMix: AVMutableAudioMix?
    var temporaryVideoURLs: [URL]
}

private struct CompositionVideoLayer {
    var segment: ExportVideoSegment
    var compositionTrack: AVMutableCompositionTrack
    var layerInstruction: AVVideoCompositionLayerInstruction

    var timelineRange: MediaTimeRange {
        MediaTimeRange(start: segment.clip.timelineStart, duration: segment.clip.timelineDuration)
    }
}

private struct ClipTransitionTiming {
    var incoming: MediaTimeRange?
    var outgoing: MediaTimeRange?
}

struct CompositionBuilder {
    private let resolver: MediaSourceResolver
    private let colorRenderer = ColorRenderService()

    init(resolver: MediaSourceResolver) {
        self.resolver = resolver
    }

    func build(plan: ExportTimelinePlan, settings: ExportSettings) async throws -> BuiltComposition {
        let composition = AVMutableComposition()
        var audioParameters: [AVMutableAudioMixInputParameters] = []
        var videoLayers: [CompositionVideoLayer] = []
        var temporaryVideoURLs: [URL] = []
        let renderSize = CGSize(width: settings.width, height: settings.height)
        let transitionTimings = transitionTimings(for: plan.videoSegments)

        do {
            for segment in plan.videoSegments {
                let sourceURL = try await resolver.resolvedURL(for: segment.media)
                let preparedSource = try await colorRenderer.prepare(segment: segment, sourceURL: sourceURL)
                if let temporaryURL = preparedSource.temporaryURL {
                    temporaryVideoURLs.append(temporaryURL)
                }
                let asset = AVURLAsset(url: preparedSource.url)
                let tracks = try await asset.load(.tracks)
                guard let sourceTrack = tracks.first(where: { $0.mediaType == .video }),
                      let compositionTrack = composition.addMutableTrack(
                          withMediaType: .video,
                          preferredTrackID: kCMPersistentTrackID_Invalid
                      )
                else {
                    throw MediaSourceResolverError.unavailable(segment.media)
                }
                let sourceRange = preparedSource.sourceRange.cmTimeRange
                try compositionTrack.insertTimeRange(sourceRange, of: sourceTrack, at: segment.clip.timelineStart.cmTime)
                let timelineDuration = segment.clip.timelineDuration.cmTime
                if segment.clip.playbackRate != 1 {
                    compositionTrack.scaleTimeRange(
                        CMTimeRange(start: segment.clip.timelineStart.cmTime, duration: sourceRange.duration),
                        toDuration: timelineDuration
                    )
                }
                let clipStart = segment.clip.timelineStart.cmTime
                let clipEnd = CMTimeAdd(clipStart, timelineDuration)
                var layerConfiguration = AVVideoCompositionLayerInstruction.Configuration(assetTrack: compositionTrack)
                let transform = try await videoTransform(
                    sourceTrack: sourceTrack,
                    renderSize: renderSize,
                    clipTransform: segment.clip.transform,
                    contentMode: segment.clip.appearance?.contentMode ?? .fit
                )
                layerConfiguration.setTransform(transform, at: clipStart)
                if let crop = segment.clip.appearance?.crop,
                   crop.clamped() != .fullFrame {
                    let naturalSize = try await sourceTrack.load(.naturalSize)
                    let normalizedCrop = crop.clamped()
                    let cropRect = CGRect(
                        x: naturalSize.width * normalizedCrop.x,
                        y: naturalSize.height * normalizedCrop.y,
                        width: naturalSize.width * normalizedCrop.width,
                        height: naturalSize.height * normalizedCrop.height
                    )
                    layerConfiguration.setCropRectangle(cropRect, at: clipStart)
                }
                applyTransitionOpacity(
                    to: &layerConfiguration,
                    clip: segment.clip,
                    start: clipStart,
                    end: clipEnd,
                    timing: transitionTimings[segment.clip.id] ?? ClipTransitionTiming()
                )
                videoLayers.append(CompositionVideoLayer(
                    segment: segment,
                    compositionTrack: compositionTrack,
                    layerInstruction: AVVideoCompositionLayerInstruction(configuration: layerConfiguration)
                ))
            }
        } catch {
            for url in temporaryVideoURLs {
                try? FileManager.default.removeItem(at: url)
            }
            throw error
        }

        for segment in plan.audioSegments {
            let url = try await resolver.resolvedURL(for: segment.media)
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.load(.tracks)
            guard let sourceTrack = tracks.first(where: { $0.mediaType == .audio }),
                  let compositionTrack = composition.addMutableTrack(
                      withMediaType: .audio,
                      preferredTrackID: kCMPersistentTrackID_Invalid
                  )
            else {
                continue
            }
            try compositionTrack.insertTimeRange(
                segment.clip.sourceRange.cmTimeRange,
                of: sourceTrack,
                at: segment.clip.timelineStart.cmTime
            )
            let parameters = AVMutableAudioMixInputParameters(track: compositionTrack)
            let volume = segment.clip.isMuted == true
                ? 0
                : Float(min(1, max(0, segment.clip.volume * plan.masterVolume)))
            parameters.setVolume(volume, at: segment.clip.timelineStart.cmTime)
            audioParameters.append(parameters)
        }

        if let musicSegment = plan.musicSegment {
            let url = try await resolver.resolvedURL(for: musicSegment.media)
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.load(.tracks)
            if let sourceTrack = tracks.first(where: { $0.mediaType == .audio }),
               let compositionTrack = composition.addMutableTrack(
                   withMediaType: .audio,
                   preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let availableDuration = try await asset.load(.duration)
                let availableSeconds = min(
                    availableDuration.seconds,
                    max(0, plan.duration.seconds - musicSegment.track.timelineStart.seconds)
                )
                if availableSeconds > 0 {
                    try compositionTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: CMTime(seconds: availableSeconds, preferredTimescale: 600)),
                        of: sourceTrack,
                        at: musicSegment.track.timelineStart.cmTime
                    )
                    let parameters = AVMutableAudioMixInputParameters(track: compositionTrack)
                    applyMusicFades(
                        to: parameters,
                        track: musicSegment.track,
                        insertedDuration: TimelineTime(seconds: availableSeconds),
                        masterVolume: plan.masterVolume
                    )
                    audioParameters.append(parameters)
                }
            }
        }

        var videoConfiguration = AVVideoComposition.Configuration()
        videoConfiguration.frameDuration = CMTime(value: 1, timescale: CMTimeScale(settings.frameRate.rawValue))
        videoConfiguration.instructions = videoInstructions(for: videoLayers)
        videoConfiguration.renderSize = renderSize
        let videoComposition = AVVideoComposition(configuration: videoConfiguration)
        let audioMix: AVMutableAudioMix?
        if audioParameters.isEmpty {
            audioMix = nil
        } else {
            let mix = AVMutableAudioMix()
            mix.inputParameters = audioParameters
            audioMix = mix
        }
        return BuiltComposition(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            temporaryVideoURLs: temporaryVideoURLs
        )
    }

    private func videoInstructions(
        for layers: [CompositionVideoLayer]
    ) -> [AVVideoCompositionInstructionProtocol] {
        let boundaries = Array(Set(layers.flatMap {
            [$0.timelineRange.start, TimelineTime(seconds: $0.timelineRange.start.seconds + $0.timelineRange.duration.seconds)]
        })).sorted()
        guard boundaries.count > 1 else { return [] }

        return zip(boundaries, boundaries.dropFirst()).compactMap { start, end in
            let activeLayers = layers.filter { layer in
                layer.timelineRange.start <= start
                    && TimelineTime(seconds: layer.timelineRange.start.seconds + layer.timelineRange.duration.seconds) > start
            }
            guard !activeLayers.isEmpty else { return nil }
            // AVFoundation applies the first layer instruction on top. A higher
            // video-track index is therefore listed first; within one track an
            // outgoing clip stays first in an overlap so its opacity ramp reveals
            // the incoming clip beneath it.
            let orderedInstructions = activeLayers.sorted {
                if $0.segment.trackIndex != $1.segment.trackIndex {
                    return $0.segment.trackIndex > $1.segment.trackIndex
                }
                return $0.segment.clip.timelineStart < $1.segment.clip.timelineStart
            }.map(\.layerInstruction)
            var configuration = AVVideoCompositionInstruction.Configuration()
            configuration.timeRange = CMTimeRange(
                start: start.cmTime,
                duration: CMTimeSubtract(end.cmTime, start.cmTime)
            )
            configuration.layerInstructions = orderedInstructions
            return AVVideoCompositionInstruction(configuration: configuration)
        }
    }

    private func transitionTimings(for segments: [ExportVideoSegment]) -> [UUID: ClipTransitionTiming] {
        var timings = Dictionary(uniqueKeysWithValues: segments.map { ($0.clip.id, ClipTransitionTiming()) })
        for trackSegments in Dictionary(grouping: segments, by: \.trackIndex).values {
            let sorted = trackSegments.sorted { $0.clip.timelineStart < $1.clip.timelineStart }
            for (outgoing, incoming) in zip(sorted, sorted.dropFirst()) {
                let overlapStart = max(outgoing.clip.timelineStart.seconds, incoming.clip.timelineStart.seconds)
                let overlapEnd = min(outgoing.clip.timelineEnd.seconds, incoming.clip.timelineEnd.seconds)
                guard overlapEnd > overlapStart,
                      outgoing.clip.transitionOut == .crossDissolve || incoming.clip.transitionIn == .crossDissolve
                else {
                    continue
                }
                let range = MediaTimeRange(
                    start: TimelineTime(seconds: overlapStart),
                    duration: TimelineTime(seconds: min(0.35, overlapEnd - overlapStart))
                )
                timings[outgoing.clip.id]?.outgoing = range
                timings[incoming.clip.id]?.incoming = range
            }
        }
        return timings
    }

    private func videoTransform(
        sourceTrack: AVAssetTrack,
        renderSize: CGSize,
        clipTransform: ClipTransform,
        contentMode: ClipContentMode
    ) async throws -> CGAffineTransform {
        let naturalSize = try await sourceTrack.load(.naturalSize)
        let preferredTransform = try await sourceTrack.load(.preferredTransform)
        let transformedBounds = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientedSize = CGSize(width: abs(transformedBounds.width), height: abs(transformedBounds.height))
        guard orientedSize.width > 0, orientedSize.height > 0 else { return preferredTransform }
        let fittedScale: CGFloat
        switch contentMode {
        case .fit:
            fittedScale = min(renderSize.width / orientedSize.width, renderSize.height / orientedSize.height)
        case .fill:
            fittedScale = max(renderSize.width / orientedSize.width, renderSize.height / orientedSize.height)
        }
        let scale = fittedScale * clipTransform.scale
        let translatedX = ((renderSize.width - (orientedSize.width * scale)) / 2) - (transformedBounds.minX * scale) + clipTransform.positionX
        let translatedY = ((renderSize.height - (orientedSize.height * scale)) / 2) - (transformedBounds.minY * scale) + clipTransform.positionY
        let rotation = clipTransform.rotationDegrees * .pi / 180
        return preferredTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(rotationAngle: rotation))
            .concatenating(CGAffineTransform(translationX: translatedX, y: translatedY))
    }

    private func applyMusicFades(
        to parameters: AVMutableAudioMixInputParameters,
        track: MusicTrack,
        insertedDuration: TimelineTime,
        masterVolume: Double
    ) {
        let start = track.timelineStart.cmTime
        let volume = Float(min(1, max(0, track.volume * masterVolume)))
        let fadeIn = min(track.fadeInDuration.seconds, insertedDuration.seconds)
        let fadeOut = min(track.fadeOutDuration.seconds, insertedDuration.seconds)
        if fadeIn > 0 {
            parameters.setVolumeRamp(
                fromStartVolume: 0,
                toEndVolume: volume,
                timeRange: CMTimeRange(start: start, duration: CMTime(seconds: fadeIn, preferredTimescale: 600))
            )
        } else {
            parameters.setVolume(volume, at: start)
        }
        if fadeOut > 0 {
            let fadeStart = CMTimeAdd(start, CMTime(seconds: max(0, insertedDuration.seconds - fadeOut), preferredTimescale: 600))
            parameters.setVolumeRamp(
                fromStartVolume: volume,
                toEndVolume: 0,
                timeRange: CMTimeRange(start: fadeStart, duration: CMTime(seconds: fadeOut, preferredTimescale: 600))
            )
        }
    }

    private func applyTransitionOpacity(
        to configuration: inout AVVideoCompositionLayerInstruction.Configuration,
        clip: TimelineClip,
        start: CMTime,
        end: CMTime,
        timing: ClipTransitionTiming
    ) {
        let opacity = Float(min(1, max(0, clip.opacity)))
        let maximumDuration = min(0.35, max(0, clip.timelineDuration.seconds / 2))
        let transitionDuration = CMTime(seconds: maximumDuration, preferredTimescale: 600)

        if let incoming = timing.incoming {
            configuration.setOpacity(0, at: incoming.start.cmTime)
            configuration.addOpacityRamp(.init(
                timeRange: incoming.cmTimeRange,
                start: 0,
                end: opacity
            ))
        } else {
            switch clip.transitionIn {
            case .hardCut, .crossDissolve:
                configuration.setOpacity(opacity, at: start)
            case .dipToBlack:
                configuration.setOpacity(0, at: start)
                configuration.addOpacityRamp(.init(
                    timeRange: CMTimeRange(start: start, duration: transitionDuration),
                    start: 0,
                    end: opacity
                ))
            }
        }
        if let outgoing = timing.outgoing {
            configuration.addOpacityRamp(.init(
                timeRange: outgoing.cmTimeRange,
                start: opacity,
                end: 0
            ))
        } else {
            switch clip.transitionOut {
            case .hardCut, .crossDissolve:
                break
            case .dipToBlack:
                let transitionStart = CMTimeSubtract(end, transitionDuration)
                configuration.addOpacityRamp(.init(
                    timeRange: CMTimeRange(start: transitionStart, duration: transitionDuration),
                    start: opacity,
                    end: 0
                ))
            }
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
