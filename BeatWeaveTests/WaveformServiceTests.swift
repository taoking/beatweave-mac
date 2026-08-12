import AVFoundation
import XCTest
@testable import BeatWeave

final class WaveformServiceTests: XCTestCase {
    func testGenerateCreatesMultiplePeakAndRMSLevels() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "BeatWeaveWaveform-\(UUID().uuidString)", directoryHint: .isDirectory)
        let url = directory.appending(path: "pulse.wav")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
        buffer.frameLength = 4_410
        if let samples = buffer.floatChannelData?[0] {
            for index in 0..<Int(buffer.frameLength) {
                samples[index] = index.isMultiple(of: 2) ? 0.5 : -0.5
            }
        }
        var audioFile: AVAudioFile? = try AVAudioFile(forWriting: url, settings: format.settings)
        try audioFile?.write(from: buffer)
        audioFile = nil

        let media = MediaReference(
            displayName: "pulse.wav",
            originalURL: url,
            kind: .audio,
            duration: TimelineTime(seconds: 0.1)
        )
        let cache = try await WaveformService().generate(for: media)

        XCTAssertEqual(cache.mediaID, media.id)
        XCTAssertEqual(cache.levels.map(\.bucketCount), [512, 2_048, 8_192])
        XCTAssertTrue(cache.levels.allSatisfy { $0.samples.count == $0.bucketCount })
        XCTAssertGreaterThan(cache.levels[0].samples.map(\.peak).max() ?? 0, 0.4)
    }
}
