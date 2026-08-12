import AVFoundation
import XCTest
@testable import BeatWeave

final class BeatAnalysisServiceTests: XCTestCase {
    func testAnalyzeDetectsBPMFromSyntheticClickTrack() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "BeatWeaveBeatAnalysis-\(UUID().uuidString)", directoryHint: .isDirectory)
        let url = directory.appending(path: "click-track.wav")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let sampleRate = 44_100.0
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let frameCount = AVAudioFrameCount(sampleRate * 8)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for beatFrame in stride(from: 0, to: Int(frameCount), by: Int(sampleRate / 2)) {
            for offset in 0..<min(1_024, Int(frameCount) - beatFrame) {
                samples[beatFrame + offset] = 0.9 * exp(-Float(offset) / 120)
            }
        }
        var audioFile: AVAudioFile? = try AVAudioFile(forWriting: url, settings: format.settings)
        try audioFile?.write(from: buffer)
        audioFile = nil

        let media = MediaReference(
            displayName: "click-track.wav",
            originalURL: url,
            kind: .audio,
            duration: TimelineTime(seconds: 8)
        )
        let analysis = try await BeatAnalysisService().analyze(for: media)

        XCTAssertEqual(analysis.mediaID, media.id)
        XCTAssertEqual(analysis.bpm, 120, accuracy: 3)
        XCTAssertGreaterThanOrEqual(analysis.onsets.count, 10)
        XCTAssertGreaterThanOrEqual(analysis.beatTimes.count, 14)
        XCTAssertNotNil(analysis.diagnostics)
    }
}
