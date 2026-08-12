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
