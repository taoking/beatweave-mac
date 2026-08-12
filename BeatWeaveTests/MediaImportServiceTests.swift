import AVFoundation
import XCTest
@testable import BeatWeave

final class MediaImportServiceTests: XCTestCase {
    func testImportReadsAudioMediaMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "BeatWeaveMediaImport-\(UUID().uuidString)", directoryHint: .isDirectory)
        let audioURL = directory.appending(path: "tone.wav")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
        buffer.frameLength = 4_410
        var audioFile: AVAudioFile? = try AVAudioFile(forWriting: audioURL, settings: format.settings)
        try audioFile?.write(from: buffer)
        audioFile = nil

        let imported = try await MediaImportService().import(url: audioURL).reference

        XCTAssertEqual(imported.displayName, "tone.wav")
        XCTAssertEqual(imported.kind, .audio)
        XCTAssertNil(imported.videoMetadata)
        XCTAssertEqual(imported.duration.seconds, 0.1, accuracy: 0.01)
        XCTAssertNotNil(imported.securityScopedBookmark)
    }

    func testSourceResolverDistinguishesAvailableAndMissingMedia() async {
        let existingURL = FileManager.default.temporaryDirectory.appending(path: "BeatWeaveExisting-\(UUID().uuidString)")
        let existing = reference(url: existingURL)
        let missing = reference(url: existingURL.appending(path: "missing.mov"))
        defer {
            try? FileManager.default.removeItem(at: existingURL)
        }

        FileManager.default.createFile(atPath: existingURL.path, contents: Data())
        let resolver = MediaSourceResolver()
        let existingStatus = await resolver.status(for: existing)
        let missingStatus = await resolver.status(for: missing)

        XCTAssertEqual(existingStatus, .available)
        XCTAssertEqual(missingStatus, .missing)
    }

    private func reference(url: URL) -> MediaReference {
        MediaReference(
            displayName: url.lastPathComponent,
            originalURL: url,
            kind: .video,
            duration: .zero
        )
    }
}
