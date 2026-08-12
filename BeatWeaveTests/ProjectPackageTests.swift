import XCTest
@testable import BeatWeave

final class ProjectPackageTests: XCTestCase {
    func testPackageContainsProjectJSONAndRegenerableCacheDirectories() throws {
        let project = ProjectFile.new(name: "包测试")
        let package = try ProjectPackage.makeFileWrapper(for: project)
        let entries = try XCTUnwrap(package.fileWrappers)

        XCTAssertNotNil(entries[ProjectPackage.projectFileName]?.regularFileContents)
        for name in ProjectPackage.cacheDirectoryNames {
            XCTAssertTrue(entries[name]?.isDirectory == true, "Missing cache directory: \(name)")
        }
    }

    func testPackageRoundTripRestoresProject() throws {
        let timestamp = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-13T00:00:00Z"))
        let project = ProjectFile.new(name: "保存并重开", now: timestamp)

        let package = try ProjectPackage.makeFileWrapper(for: project)
        let restored = try ProjectPackage.readProject(from: package)

        XCTAssertEqual(restored, project)
    }

    func testPackageRoundTripRestoresWaveformCaches() throws {
        let timestamp = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-13T00:00:00Z"))
        let project = ProjectFile.new(name: "带波形缓存", now: timestamp)
        let mediaID = UUID()
        let cache = WaveformCache(
            formatVersion: WaveformCache.currentFormatVersion,
            mediaID: mediaID,
            duration: TimelineTime(seconds: 2),
            levels: [WaveformLevel(bucketCount: 2, samples: [
                WaveformSample(peak: 0.5, rms: 0.25),
                WaveformSample(peak: 0.75, rms: 0.5)
            ])]
        )

        let package = try ProjectPackage.makeFileWrapper(for: project, waveformCaches: [mediaID: cache])
        let contents = try ProjectPackage.readContents(from: package)

        XCTAssertEqual(contents.project, project)
        XCTAssertEqual(contents.waveformCaches, [mediaID: cache])
    }

    func testPackageRoundTripPreservesBeatMarkers() throws {
        let timestamp = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-13T00:00:00Z"))
        var project = ProjectFile.new(name: "节拍持久化", now: timestamp)
        let mediaID = UUID(uuidString: "96F27813-450D-4548-88C2-62D36CBF3A9C") ?? UUID()
        let onsetID = UUID(uuidString: "2E7B1B02-4E7C-42E8-8178-7607FAFF7B9D") ?? UUID()
        project.beatAnalysis = BeatAnalysis(
            mediaID: mediaID,
            bpm: 120,
            confidence: 0.8,
            alternateBPMs: [60],
            onsets: [Onset(id: onsetID, time: TimelineTime(seconds: 0.5), strength: 1)],
            beatTimes: [TimelineTime(seconds: 0.5), TimelineTime(seconds: 1)],
            strongBeatTimes: [TimelineTime(seconds: 0.5)],
            downbeatTimes: [TimelineTime(seconds: 0.5)],
            parameters: .default,
            diagnostics: BeatAnalysisDiagnostics(
                duration: TimelineTime(seconds: 2),
                sampleRate: 44_100,
                parameters: .default,
                detectedBPM: 120,
                alternateBPMs: [60],
                confidence: 0.8,
                onsetCount: 1,
                beatCount: 2,
                executionMilliseconds: 15
            )
        )

        let package = try ProjectPackage.makeFileWrapper(for: project)
        let restored = try ProjectPackage.readProject(from: package)

        XCTAssertEqual(restored.beatAnalysis, project.beatAnalysis)
    }

    func testPackageWritesAndReadsFromDisk() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "BeatWeaveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let projectURL = temporaryDirectory.appending(path: "磁盘项目.beatweave", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let timestamp = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-13T00:00:00Z"))
        let project = ProjectFile.new(name: "磁盘往返", now: timestamp)
        let package = try ProjectPackage.makeFileWrapper(for: project)
        try package.write(to: projectURL, options: .atomic, originalContentsURL: nil)

        let reopenedPackage = try FileWrapper(url: projectURL, options: .immediate)
        XCTAssertNotNil(reopenedPackage.fileWrappers?[ProjectPackage.projectFileName]?.regularFileContents)
        let reopenedProject = try ProjectPackage.readProject(from: reopenedPackage)

        XCTAssertEqual(reopenedProject, project)
    }

    func testPackageReadRejectsMissingProjectJSON() {
        let package = FileWrapper(directoryWithFileWrappers: [:])

        XCTAssertThrowsError(try ProjectPackage.readProject(from: package)) { error in
            XCTAssertEqual(error as? ProjectPackageError, .missingProjectFile)
        }
    }
}
