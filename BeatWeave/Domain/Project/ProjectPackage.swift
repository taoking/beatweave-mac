import Foundation

enum ProjectPackage {
    static let projectFileName = "project.json"
    static let cacheDirectoryNames = ["thumbnails", "waveforms", "analysis", "proxies", "autosave"]

    static func makeFileWrapper(for project: ProjectFile) throws -> FileWrapper {
        var entries: [String: FileWrapper] = [:]
        let projectFile = FileWrapper(regularFileWithContents: try ProjectCodec.encode(project))
        projectFile.preferredFilename = projectFileName
        entries[projectFileName] = projectFile

        for name in cacheDirectoryNames {
            let directory = FileWrapper(directoryWithFileWrappers: [:])
            directory.preferredFilename = name
            entries[name] = directory
        }

        return FileWrapper(directoryWithFileWrappers: entries)
    }

    static func readProject(from package: FileWrapper) throws -> ProjectFile {
        guard package.isDirectory else {
            throw ProjectPackageError.notAPackage
        }
        guard let projectData = package.fileWrappers?[projectFileName]?.regularFileContents else {
            throw ProjectPackageError.missingProjectFile
        }
        return try ProjectCodec.decode(projectData)
    }
}

enum ProjectPackageError: LocalizedError, Equatable {
    case notAPackage
    case missingProjectFile

    var errorDescription: String? {
        switch self {
        case .notAPackage:
            "BeatWeave 项目必须是一个 .beatweave 包。"
        case .missingProjectFile:
            "该 BeatWeave 项目缺少 project.json。"
        }
    }
}
