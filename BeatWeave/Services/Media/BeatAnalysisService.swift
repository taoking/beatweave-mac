import Accelerate
import AVFoundation
import Foundation
import os

enum BeatAnalysisError: LocalizedError {
    case noAudioTrack(URL)
    case readerStartFailed(URL)
    case unsupportedPCM(URL)
    case invalidParameters
    case insufficientOnsets(URL)

    var errorDescription: String? {
        switch self {
        case let .noAudioTrack(url): "“\(url.lastPathComponent)”没有可分析的音频轨道。"
        case let .readerStartFailed(url): "无法解码“\(url.lastPathComponent)”的音频。"
        case let .unsupportedPCM(url): "“\(url.lastPathComponent)”返回了不支持的 PCM 数据。"
        case .invalidParameters: "节拍分析参数无效。"
        case let .insufficientOnsets(url): "“\(url.lastPathComponent)”没有足够清晰的起音，无法估计 BPM。"
        }
    }
}

actor BeatAnalysisService {
    private let parameters: BeatAnalysisParameters
    private let logger = Logger(subsystem: "com.taoking.BeatWeave", category: "beat-analysis")

    init(parameters: BeatAnalysisParameters = .default) {
        self.parameters = parameters
    }

    func analyze(for media: MediaReference) async throws -> BeatAnalysis {
        let startedAt = Date()
        let url = media.originalURL
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted { url.stopAccessingSecurityScopedResource() }
        }

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.load(.tracks)
        guard let track = tracks.first(where: { $0.mediaType == .audio }) else {
            throw BeatAnalysisError.noAudioTrack(url)
        }
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw BeatAnalysisError.readerStartFailed(url)
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: parameters.sampleRate
            ]
        )
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw BeatAnalysisError.readerStartFailed(url)
        }

        let processor = try SpectralFluxProcessor(parameters: parameters)
        while reader.status == .reading {
            try Task.checkCancellation()
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            try processor.consume(sampleBuffer, url: url)
        }
        guard reader.status != .failed else {
            throw reader.error ?? BeatAnalysisError.readerStartFailed(url)
        }

        let onsets = BeatAnalysisDSP.detectOnsets(from: processor.envelope)
        guard let bpmResult = BeatAnalysisDSP.estimateBPM(
            from: onsets,
            minimumBPM: parameters.minimumBPM,
            maximumBPM: parameters.maximumBPM
        ) else {
            throw BeatAnalysisError.insufficientOnsets(url)
        }
        let timescale = duration.timescale > 0 ? duration.timescale : 600
        let timelineDuration = TimelineTime(seconds: durationSeconds, timescale: timescale)
        let grid = BeatAnalysisDSP.makeBeatGrid(
            bpm: bpmResult.bpm,
            duration: timelineDuration,
            onsets: onsets
        )
        let elapsedMilliseconds = Int((Date().timeIntervalSince(startedAt) * 1_000).rounded())
        let diagnostics = BeatAnalysisDiagnostics(
            duration: timelineDuration,
            sampleRate: parameters.sampleRate,
            parameters: parameters,
            detectedBPM: bpmResult.bpm,
            alternateBPMs: bpmResult.alternateBPMs,
            confidence: bpmResult.confidence,
            onsetCount: onsets.count,
            beatCount: grid.beatTimes.count,
            executionMilliseconds: elapsedMilliseconds
        )
        logger.info(
            "beat analysis complete duration=\(durationSeconds, privacy: .public)s sampleRate=\(self.parameters.sampleRate, privacy: .public) bpm=\(bpmResult.bpm, privacy: .public) alternates=\(bpmResult.alternateBPMs.description, privacy: .public) confidence=\(bpmResult.confidence, privacy: .public) onsets=\(onsets.count, privacy: .public) beats=\(grid.beatTimes.count, privacy: .public) elapsedMs=\(elapsedMilliseconds, privacy: .public)"
        )
        return BeatAnalysis(
            mediaID: media.id,
            bpm: bpmResult.bpm,
            confidence: bpmResult.confidence,
            alternateBPMs: bpmResult.alternateBPMs,
            onsets: onsets,
            beatTimes: grid.beatTimes,
            strongBeatTimes: grid.strongBeatTimes,
            downbeatTimes: grid.downbeatTimes,
            parameters: parameters,
            diagnostics: diagnostics
        )
    }
}

private final class SpectralFluxProcessor {
    let parameters: BeatAnalysisParameters
    private let fftSetup: FFTSetup
    private let log2WindowSize: vDSP_Length
    private let hannWindow: [Float]
    private var pendingSamples: [Float] = []
    private var pendingStart = 0
    private var processedFrameStart = 0
    private var previousMagnitudes: [Float]?
    private(set) var envelope: [OnsetEnvelopePoint] = []

    init(parameters: BeatAnalysisParameters) throws {
        guard parameters.sampleRate > 0,
              parameters.windowSize > 0,
              parameters.windowSize.isMultiple(of: 2),
              parameters.windowSize.nonzeroBitCount == 1,
              parameters.hopSize > 0,
              parameters.hopSize <= parameters.windowSize,
              parameters.minimumBPM > 0,
              parameters.maximumBPM >= parameters.minimumBPM,
              let fftSetup = vDSP_create_fftsetup(
                  vDSP_Length(log2(Double(parameters.windowSize))),
                  FFTRadix(kFFTRadix2)
              )
        else {
            throw BeatAnalysisError.invalidParameters
        }
        self.parameters = parameters
        self.fftSetup = fftSetup
        self.log2WindowSize = vDSP_Length(log2(Double(parameters.windowSize)))
        var window = [Float](repeating: 0, count: parameters.windowSize)
        vDSP_hann_window(&window, vDSP_Length(parameters.windowSize), Int32(vDSP_HANN_NORM))
        self.hannWindow = window
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func consume(_ sampleBuffer: CMSampleBuffer, url: URL) throws {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            throw BeatAnalysisError.unsupportedPCM(url)
        }
        var totalLength = 0
        var pointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            block,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &pointer
        )
        guard status == kCMBlockBufferNoErr, let pointer else {
            throw BeatAnalysisError.unsupportedPCM(url)
        }
        let count = totalLength / MemoryLayout<Float>.stride
        let values = UnsafeRawPointer(pointer).bindMemory(to: Float.self, capacity: count)
        pendingSamples.append(contentsOf: UnsafeBufferPointer(start: values, count: count))
        processPendingSamples()
    }

    private func processPendingSamples() {
        while pendingSamples.count - pendingStart >= parameters.windowSize {
            var real = [Float](repeating: 0, count: parameters.windowSize)
            var imaginary = [Float](repeating: 0, count: parameters.windowSize)
            for index in real.indices {
                real[index] = pendingSamples[pendingStart + index] * hannWindow[index]
            }
            real.withUnsafeMutableBufferPointer { realBuffer in
                imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                    var splitComplex = DSPSplitComplex(
                        realp: realBuffer.baseAddress!,
                        imagp: imaginaryBuffer.baseAddress!
                    )
                    vDSP_fft_zip(
                        fftSetup,
                        &splitComplex,
                        1,
                        log2WindowSize,
                        FFTDirection(FFT_FORWARD)
                    )
                }
            }

            let magnitudes = (1..<(parameters.windowSize / 2)).map { index in
                hypot(real[index], imaginary[index])
            }
            let flux: Double
            if let previousMagnitudes {
                flux = zip(magnitudes, previousMagnitudes).reduce(0) { partial, pair in
                    partial + Double(max(0, pair.0 - pair.1))
                }
            } else {
                flux = 0
            }
            previousMagnitudes = magnitudes
            let centerTime = Double(processedFrameStart + (parameters.windowSize / 2)) / parameters.sampleRate
            envelope.append(OnsetEnvelopePoint(time: centerTime, strength: flux))
            pendingStart += parameters.hopSize
            processedFrameStart += parameters.hopSize

            if pendingStart >= parameters.windowSize {
                pendingSamples.removeFirst(pendingStart)
                pendingStart = 0
            }
        }
    }
}
