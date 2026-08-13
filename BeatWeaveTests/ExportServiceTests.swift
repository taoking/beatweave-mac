import AppKit
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
            quality: .high
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

    func testExportCompositesOverlappedCrossDissolveAndLayeredVideoTracks() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "BeatWeaveTransitionExport-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let redURL = directory.appending(path: "red.mov")
        let blueURL = directory.appending(path: "blue.mov")
        let greenURL = directory.appending(path: "green.mov")
        let outputURL = directory.appending(path: "result.mp4")
        try await makeVideo(at: redURL, color: (red: 255, green: 0, blue: 0))
        try await makeVideo(at: blueURL, color: (red: 0, green: 0, blue: 255))
        try await makeVideo(at: greenURL, color: (red: 0, green: 255, blue: 0))

        let red = videoReference(name: "red.mov", url: redURL)
        let blue = videoReference(name: "blue.mov", url: blueURL)
        let green = videoReference(name: "green.mov", url: greenURL)
        var project = ProjectFile.new()
        project.mediaLibrary.items = [red, blue, green]
        project.timeline.videoTracks = [
            VideoTrack(clips: [
                clip(mediaID: red.id, start: 0, duration: 1, transitionOut: .crossDissolve),
                clip(mediaID: blue.id, start: 0.65, duration: 1, transitionIn: .crossDissolve)
            ]),
            VideoTrack(clips: [clip(mediaID: green.id, start: 1.4, duration: 0.25)])
        ]
        project.exportSettings = exportSettings

        _ = try await ExportService().export(project: project, to: outputURL)
        let exportedAsset = AVURLAsset(url: outputURL)
        let exportedTracks = try await exportedAsset.load(.tracks)
        let exportedVideo = try XCTUnwrap(exportedTracks.first(where: { $0.mediaType == .video }))
        let exportedDuration = try await exportedAsset.load(.duration).seconds
        let videoDuration = try await exportedVideo.load(.timeRange).duration.seconds
        XCTAssertEqual(exportedDuration, 1.65, accuracy: 0.1)
        XCTAssertEqual(videoDuration, 1.65, accuracy: 0.1)

        let dissolve = try await color(at: 0.82, in: outputURL)
        XCTAssertGreaterThan(dissolve.red, 0.12)
        XCTAssertGreaterThan(dissolve.blue, 0.12)
        let upperTrack = try await color(at: 1.5, in: outputURL)
        XCTAssertGreaterThan(upperTrack.green, 0.35)
        XCTAssertLessThan(upperTrack.red, 0.2)
        XCTAssertLessThan(upperTrack.blue, 0.2)
    }

    func testExportRendersBasicColorAndCubeLUTPerClip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "BeatWeaveColorExport-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let redURL = directory.appending(path: "red.mov")
        let blueURL = directory.appending(path: "blue.mov")
        let cubeURL = directory.appending(path: "black.cube")
        let outputURL = directory.appending(path: "result.mp4")
        try await makeVideo(at: redURL, color: (red: 255, green: 0, blue: 0))
        try await makeVideo(at: blueURL, color: (red: 0, green: 0, blue: 255))
        try Data("""
        LUT_3D_SIZE 2
        0 0 0
        0 0 0
        0 0 0
        0 0 0
        0 0 0
        0 0 0
        0 0 0
        0 0 0
        """.utf8).write(to: cubeURL)

        let red = videoReference(name: "red.mov", url: redURL)
        let blue = videoReference(name: "blue.mov", url: blueURL)
        var grayscaleAppearance = ClipAppearance.default
        grayscaleAppearance.color.saturation = 0
        var lutAppearance = ClipAppearance.default
        lutAppearance.lut = LUTReference(displayName: "black.cube", fileURL: cubeURL, intensity: 1)
        var project = ProjectFile.new()
        project.mediaLibrary.items = [red, blue]
        project.timeline.videoTracks = [VideoTrack(clips: [
            clip(mediaID: red.id, start: 0, duration: 1, appearance: grayscaleAppearance),
            clip(mediaID: blue.id, start: 1, duration: 1, appearance: lutAppearance)
        ])]
        project.exportSettings = exportSettings

        _ = try await ExportService().export(project: project, to: outputURL)

        let grayscale = try await color(at: 0.5, in: outputURL)
        XCTAssertLessThan(abs(grayscale.red - grayscale.green), 0.12)
        XCTAssertLessThan(abs(grayscale.green - grayscale.blue), 0.12)
        let blackLUT = try await color(at: 1.5, in: outputURL)
        XCTAssertLessThan(max(blackLUT.red, blackLUT.green, blackLUT.blue), 0.2)
    }

    private var exportSettings: ExportSettings {
        ExportSettings(
            codec: .h264,
            width: 64,
            height: 64,
            frameRate: .fps30,
            quality: .medium
        )
    }

    private func videoReference(name: String, url: URL) -> MediaReference {
        MediaReference(
            displayName: name,
            originalURL: url,
            kind: .video,
            duration: TimelineTime(seconds: 1)
        )
    }

    private func clip(
        mediaID: UUID,
        start: Double,
        duration: Double,
        transitionIn: Transition = .hardCut,
        transitionOut: Transition = .hardCut,
        appearance: ClipAppearance? = nil
    ) -> TimelineClip {
        TimelineClip(
            id: UUID(),
            mediaID: mediaID,
            sourceRange: MediaTimeRange(start: .zero, duration: TimelineTime(seconds: duration)),
            timelineStart: TimelineTime(seconds: start),
            playbackRate: 1,
            transform: .identity,
            opacity: 1,
            volume: 1,
            transitionIn: transitionIn,
            transitionOut: transitionOut,
            appearance: appearance
        )
    }

    private func color(at seconds: Double, in url: URL) async throws -> (red: Double, green: Double, blue: Double) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let result = try await generator.image(
            at: CMTime(seconds: seconds, preferredTimescale: 600)
        )
        let image = result.image
        let bitmap = try XCTUnwrap(NSBitmapImageRep(cgImage: image))
        let color = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
        let calibrated = color.usingColorSpace(.sRGB) ?? color
        return (Double(calibrated.redComponent), Double(calibrated.greenComponent), Double(calibrated.blueComponent))
    }

    private func makeVideo(
        at url: URL,
        color: (red: UInt8, green: UInt8, blue: UInt8)? = nil
    ) async throws {
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
            if let color, let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
                let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
                for y in 0..<64 {
                    for x in 0..<64 {
                        let offset = (y * bytesPerRow) + (x * 4)
                        pixels[offset] = color.blue
                        pixels[offset + 1] = color.green
                        pixels[offset + 2] = color.red
                        pixels[offset + 3] = 255
                    }
                }
            } else if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
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
