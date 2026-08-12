import Foundation
import os

enum ProjectPackage {
    static let projectFileName = "project.json"
    static let cacheDirectoryNames = ["thumbnails", "waveforms", "analysis", "proxies", "autosave"]
    private static let logger = Logger(subsystem: "com.taoking.BeatWeave", category: "cache")

    static func makeFileWrapper(
        for project: ProjectFile,
        waveformCaches: [UUID: WaveformCache] = [:]
    ) throws -> FileWrapper {
        var entries: [String: FileWrapper] = [:]
        let projectFile = FileWrapper(regularFileWithContents: try ProjectCodec.encode(project))
        projectFile.preferredFilename = projectFileName
        entries[projectFileName] = projectFile

        for name in cacheDirectoryNames where name != "waveforms" {
            let directory = FileWrapper(directoryWithFileWrappers: [:])
            directory.preferredFilename = name
            entries[name] = directory
        }
        entries["waveforms"] = try waveformDirectory(caches: waveformCaches)

        return FileWrapper(directoryWithFileWrappers: entries)
    }

    static func readProject(from package: FileWrapper) throws -> ProjectFile {
        try readContents(from: package).project
    }

    static func readContents(from package: FileWrapper) throws -> ProjectPackageContents {
        guard package.isDirectory else {
            throw ProjectPackageError.notAPackage
        }
        guard let projectData = package.fileWrappers?[projectFileName]?.regularFileContents else {
            throw ProjectPackageError.missingProjectFile
        }
        let project = try ProjectCodec.decode(projectData)
        var waveformCaches: [UUID: WaveformCache] = [:]
        let waveformFiles = package.fileWrappers?["waveforms"]?.fileWrappers ?? [:]
        for (filename, wrapper) in waveformFiles {
            guard let data = wrapper.regularFileContents else {
                logger.error("忽略无效波形缓存文件：\(filename, privacy: .public)")
                continue
            }
            do {
                let cache = try JSONDecoder().decode(WaveformCache.self, from: data)
                guard cache.formatVersion == WaveformCache.currentFormatVersion else {
                    logger.notice("忽略不兼容波形缓存：\(filename, privacy: .public)")
                    continue
                }
                waveformCaches[cache.mediaID] = cache
            } catch {
                logger.error("忽略损坏波形缓存：\(filename, privacy: .public)")
            }
        }
        return ProjectPackageContents(project: project, waveformCaches: waveformCaches)
    }

    private static func waveformDirectory(caches: [UUID: WaveformCache]) throws -> FileWrapper {
        var entries: [String: FileWrapper] = [:]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for cache in caches.values {
            let file = FileWrapper(regularFileWithContents: try encoder.encode(cache))
            let filename = "\(cache.mediaID.uuidString).json"
            file.preferredFilename = filename
            entries[filename] = file
        }
        let directory = FileWrapper(directoryWithFileWrappers: entries)
        directory.preferredFilename = "waveforms"
        return directory
    }
}

struct ProjectPackageContents {
    var project: ProjectFile
    var waveformCaches: [UUID: WaveformCache]
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
