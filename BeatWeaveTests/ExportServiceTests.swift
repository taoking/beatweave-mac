import AVFoundation
import CoreVideo
import XCTest
@testable import BeatWeave

final class ExportServiceTests: XCTestCase {
    func testExportNeverOverwritesExistingFinalFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "BeatWeaveExistingExport-\(UUID().uuidString)", directoryHint: .isDirectory)
        let outputURL = directory.appending(path: "existing.mp4")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let originalData = Data("original output".utf8)
        try originalData.write(to: outputURL)

        let video = MediaReference(
            displayName: "missing.mov",
            originalURL: directory.appending(path: "missing.mov"),
            kind: .video,
            duration: TimelineTime(seconds: 1)
        )
        var project = ProjectFile.new()
        project.mediaLibrary.items = [video]
        project.timeline.videoTracks = [VideoTrack(clips: [
            TimelineClip(
                id: UUID(), mediaID: video.id,
                sourceRange: MediaTimeRange(start: .zero, duration: TimelineTime(seconds: 1)),
                timelineStart: .zero, playbackRate: 1,
                transform: .identity, opacity: 1, volume: 1,
                transitionIn: .hardCut, transitionOut: .hardCut
            )
        ])]

        do {
            _ = try await ExportService().export(project: project, to: outputURL)
            XCTFail("Expected existing output to be rejected.")
        } catch let error as ExportServiceError {
            XCTAssertEqual(error, .outputAlreadyExists(outputURL))
        }
        XCTAssertEqual(try Data(contentsOf: outputURL), originalData)
    }

    func testExportWritesPlayableMP4WithTimelineDuration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "BeatWeaveExport-\(UUID().uuidString)", directoryHint: .isDirectory)
        let sourceURL = directory.appending(path: "source.mov")
        let musicURL = directory.appending(path: "music.wav")
        let outputURL = directory.appending(path: "result.mp4")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await makeVideo(at: sourceURL)
        try makeAudio(at: musicURL)

        let video = MediaReference(
            displayName: "source.mov",
            originalURL: sourceURL,
            kind: .video,
            duration: TimelineTime(seconds: 1)
        )
        let music = MediaReference(
            displayName: "music.wav",
            originalURL: musicURL,
            kind: .audio,
            duration: TimelineTime(seconds: 1)
        )
        var project = ProjectFile.new()
        project.mediaLibrary.items = [video, music]
        project.timeline.videoTracks = [VideoTrack(clips: [
            TimelineClip(
                id: UUID(), mediaID: video.id,
                sourceRange: MediaTimeRange(start: .zero, duration: TimelineTime(seconds: 1)),
                timelineStart: .zero, playbackRate: 1,
                transform: .identity, opacity: 1, volume: 1,
                transitionIn: .hardCut, transitionOut: .hardCut
            )
        ])]
        project.timeline.musicTrack = MusicTrack(
            mediaID: music.id,
            timelineStart: .zero,
            volume: 1,
            fadeInDuration: .zero,
            fadeOutDuration: .zero
        )
        project.exportSettings = ExportSettings(
            codec: .h264,
            width: 64,
            height: 64,
            frameRate: .fps30,
            quality: .medium
        )

        let result = try await ExportService().export(project: project, to: outputURL)
        let exportedAsset = AVURLAsset(url: result.outputURL)
        let tracks = try await exportedAsset.load(.tracks)
        let duration = try await exportedAsset.load(.duration)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let exportedVideoTrack = try XCTUnwrap(tracks.first(where: { $0.mediaType == .video }))
        XCTAssertNotNil(tracks.first(where: { $0.mediaType == .audio }))
        let naturalSize = try await exportedVideoTrack.load(.naturalSize)
        XCTAssertEqual(naturalSize, CGSize(width: 64, height: 64))
        XCTAssertEqual(duration.seconds, 1, accuracy: 0.15)
        XCTAssertEqual(result.duration.seconds, 1, accuracy: 0.001)
    }

    func testHEVCExportWritesPlayableMP4() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "BeatWeaveHEVCExport-\(UUID().uuidString)", directoryHint: .isDirectory)
        let sourceURL = directory.appending(path: "source.mov")
        let outputURL = directory.appending(path: "result-hevc.mp4")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await makeVideo(at: sourceURL)

        let video = MediaReference(
            displayName: "source.mov",
            originalURL: sourceURL,
            kind: .video,
            duration: TimelineTime(seconds: 1)
        )
        var project = ProjectFile.new()
        project.mediaLibrary.items = [video]
        project.timeline.videoTracks = [VideoTrack(clips: [
            TimelineClip(
                id: UUID(), mediaID: video.id,
                sourceRange: MediaTimeRange(start: .zero, duration: TimelineTime(seconds: 1)),
                timelineStart: .zero, playbackRate: 1,
                transform: .identity, opacity: 1, volume: 1,
                transitionIn: .hardCut, transitionOut: .hardCut
            )
        ])]
        project.exportSettings = ExportSettings(
            codec: .hevc,
            width: 64,
            height: 64,
            frameRate: .fps30,
            quality: .medium
        )

        let result = try await ExportService().export(project: project, to: outputURL)
        let exportedAsset = AVURLAsset(url: result.outputURL)
        let tracks = try await exportedAsset.load(.tracks)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let exportedVideoTrack = try XCTUnwrap(tracks.first(where: { $0.mediaType == .video }))
        let naturalSize = try await exportedVideoTrack.load(.naturalSize)
        XCTAssertEqual(naturalSize, CGSize(width: 64, height: 64))
    }

    private func makeVideo(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64
            ]
        )
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            var optionalBuffer: CVPixelBuffer?
            let creationResult = CVPixelBufferCreate(
                kCFAllocatorDefault,
                64,
                64,
                kCVPixelFormatType_32BGRA,
                nil,
                &optionalBuffer
            )
            XCTAssertEqual(creationResult, kCVReturnSuccess)
            let pixelBuffer = try XCTUnwrap(optionalBuffer)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
                memset(baseAddress, frame.isMultiple(of: 2) ? 0x22 : 0xAA, CVPixelBufferGetDataSize(pixelBuffer))
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "AVAssetWriter 未完成。")
    }

    private func makeAudio(at url: URL) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
        buffer.frameLength = 44_100
        if let samples = buffer.floatChannelData?[0] {
            for index in 0..<Int(buffer.frameLength) {
                samples[index] = Float(sin(Double(index) * 0.02)) * 0.2
            }
        }
        var audioFile: AVAudioFile? = try AVAudioFile(forWriting: url, settings: format.settings)
        try audioFile?.write(from: buffer)
        audioFile = nil
    }
}
