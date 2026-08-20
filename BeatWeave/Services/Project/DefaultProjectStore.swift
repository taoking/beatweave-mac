import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DefaultProjectStore {
    private static let directoryBookmarkKey = "defaultProjectDirectoryBookmark"
    private static let defaultProjectFilename = "BeatWeave 默认项目.beatweave"

    var document: BeatWeaveDocument
    private(set) var projectDirectory: URL
    private(set) var projectURL: URL
    var errorMessage: String?

    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private var scopedDirectory: URL?

    init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        defaultDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults

        let directory = defaultDirectory ?? Self.loadDirectory(from: userDefaults, fileManager: fileManager)
        projectDirectory = directory
        projectURL = Self.projectURL(in: directory)
        document = BeatWeaveDocument()

        if userDefaults.data(forKey: Self.directoryBookmarkKey) != nil,
           directory.startAccessingSecurityScopedResource() {
            scopedDirectory = directory
        }

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: projectURL.path) {
                let wrapper = try FileWrapper(url: projectURL, options: .immediate)
                document = BeatWeaveDocument(contents: try ProjectPackage.readContents(from: wrapper))
            } else {
                try write(document, to: projectURL)
            }
        } catch {
            errorMessage = "默认项目无法读取或创建：\(error.localizedDescription)"
        }
    }

    func save(_ document: BeatWeaveDocument) {
        do {
            try write(document, to: projectURL)
            errorMessage = nil
        } catch {
            errorMessage = "项目未能保存：\(error.localizedDescription)"
        }
    }

    func chooseDefaultDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择默认项目目录"
        panel.message = "BeatWeave 会将默认项目保存到此目录，并在下次启动时自动打开。"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = projectDirectory

        guard panel.runModal() == .OK, let directory = panel.url else {
            return
        }

        do {
            let bookmark = try directory.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let startedAccessing = directory.startAccessingSecurityScopedResource()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let newProjectURL = Self.projectURL(in: directory)
            try write(document, to: newProjectURL)

            scopedDirectory?.stopAccessingSecurityScopedResource()
            scopedDirectory = startedAccessing ? directory : nil
            userDefaults.set(bookmark, forKey: Self.directoryBookmarkKey)
            projectDirectory = directory
            projectURL = newProjectURL
            errorMessage = nil
        } catch {
            errorMessage = "无法设置默认项目目录：\(error.localizedDescription)"
        }
    }

    private func write(_ document: BeatWeaveDocument, to url: URL) throws {
        let existingFile = try? FileWrapper(url: url, options: .immediate)
        let recoveryProject = existingFile.flatMap { try? ProjectPackage.readProject(from: $0) }
        let wrapper = try ProjectPackage.makeFileWrapper(
            for: document.project,
            waveformCaches: document.waveformCaches,
            thumbnailCaches: document.thumbnailCaches,
            proxyCaches: document.proxyCaches,
            recoveryProject: recoveryProject
        )
        try wrapper.write(
            to: url,
            options: .atomic,
            originalContentsURL: existingFile == nil ? nil : url
        )
    }

    private static func loadDirectory(from userDefaults: UserDefaults, fileManager: FileManager) -> URL {
        if let bookmark = userDefaults.data(forKey: directoryBookmarkKey) {
            var isStale = false
            if let directory = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), !isStale {
                return directory
            }
            userDefaults.removeObject(forKey: directoryBookmarkKey)
        }

        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("BeatWeave", isDirectory: true)
            .appendingPathComponent("Projects", isDirectory: true)
    }

    private static func projectURL(in directory: URL) -> URL {
        directory.appendingPathComponent(defaultProjectFilename, isDirectory: true)
    }
}
