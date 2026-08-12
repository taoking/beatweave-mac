import AVFoundation
import Foundation

enum WaveformError: LocalizedError {
    case noAudioTrack(URL)
    case readerStartFailed(URL)
    case unsupportedPCM(URL)

    var errorDescription: String? {
        switch self {
        case let .noAudioTrack(url): "“\(url.lastPathComponent)”没有可分析的音频轨道。"
        case let .readerStartFailed(url): "无法解码“\(url.lastPathComponent)”的音频。"
        case let .unsupportedPCM(url): "“\(url.lastPathComponent)”返回了不支持的 PCM 数据。"
        }
    }
}

actor WaveformService {
    private static let bucketCounts = [512, 2_048, 8_192]

    func generate(for media: MediaReference) async throws -> WaveformCache {
        let url = media.originalURL
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted { url.stopAccessingSecurityScopedResource() }
        }

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.load(.tracks)
        guard let track = tracks.first(where: { $0.mediaType == .audio }) else {
            throw WaveformError.noAudioTrack(url)
        }
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw WaveformError.readerStartFailed(url)
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
                AVSampleRateKey: 44_100
            ]
        )
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw WaveformError.readerStartFailed(url)
        }

        var accumulators = Self.bucketCounts.map { Array(repeating: WaveformAccumulator(), count: $0) }
        var processedSamples = 0
        let estimatedSamples = max(1, Int((durationSeconds * 44_100).rounded()))

        while reader.status == .reading {
            try Task.checkCancellation()
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            try Self.consume(
                sampleBuffer,
                processedSamples: &processedSamples,
                estimatedSamples: estimatedSamples,
                accumulators: &accumulators,
                url: url
            )
        }
        guard reader.status != .failed else {
            throw reader.error ?? WaveformError.readerStartFailed(url)
        }

        let timescale = duration.timescale > 0 ? duration.timescale : 600
        return WaveformCache(
            formatVersion: WaveformCache.currentFormatVersion,
            mediaID: media.id,
            duration: TimelineTime(seconds: durationSeconds, timescale: timescale),
            levels: zip(Self.bucketCounts, accumulators).map { bucketCount, buckets in
                WaveformLevel(bucketCount: bucketCount, samples: buckets.map(\.sample))
            }
        )
    }

    private static func consume(
        _ buffer: CMSampleBuffer,
        processedSamples: inout Int,
        estimatedSamples: Int,
        accumulators: inout [[WaveformAccumulator]],
        url: URL
    ) throws {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else {
            throw WaveformError.unsupportedPCM(url)
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
            throw WaveformError.unsupportedPCM(url)
        }

        let count = totalLength / MemoryLayout<Float>.stride
        let values = UnsafeRawPointer(pointer).bindMemory(to: Float.self, capacity: count)
        for offset in 0..<count {
            let value = values[offset]
            for levelIndex in accumulators.indices {
                let bucketCount = accumulators[levelIndex].count
                let progress = min(0.999_999, Double(processedSamples + offset) / Double(estimatedSamples))
                let bucketIndex = Int(progress * Double(bucketCount))
                accumulators[levelIndex][bucketIndex].add(value)
            }
        }
        processedSamples += count
    }
}

private struct WaveformAccumulator: Sendable {
    private var maxMagnitude: Float = 0
    private var squaredSum: Float = 0
    private var count = 0

    mutating func add(_ value: Float) {
        maxMagnitude = max(maxMagnitude, abs(value))
        squaredSum += value * value
        count += 1
    }

    var sample: WaveformSample {
        WaveformSample(
            peak: maxMagnitude,
            rms: count == 0 ? 0 : sqrt(squaredSum / Float(count))
        )
    }
}
