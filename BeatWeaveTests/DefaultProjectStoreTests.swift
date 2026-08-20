import XCTest
@testable import BeatWeave

@MainActor
final class DefaultProjectStoreTests: XCTestCase {
    func testCreatesAndReopensDefaultProjectWithoutUserSelectedDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "DefaultProjectStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let suiteName = "DefaultProjectStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = DefaultProjectStore(userDefaults: defaults, defaultDirectory: directory)

        XCTAssertEqual(store.projectDirectory, directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.projectURL.path))
        XCTAssertNil(store.errorMessage)

        store.document.project.name = "自动恢复项目"
        store.save(store.document)

        let reopened = DefaultProjectStore(userDefaults: defaults, defaultDirectory: directory)
        XCTAssertEqual(reopened.document.project.name, "自动恢复项目")
        XCTAssertNil(reopened.errorMessage)
    }
}
