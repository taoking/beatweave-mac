import Foundation
import os

enum ProjectPackage {
    static let projectFileName = "project.json"
    static let recoveryFileName = "autosave/last-known-good.json"
    static let cacheDirectoryNames = ["thumbnails", "waveforms", "analysis", "proxies", "autosave"]
    private static let logger = Logger(subsystem: "com.taoking.BeatWeave", category: "cache")

    static func makeFileWrapper(
        for project: ProjectFile,
        waveformCaches: [UUID: WaveformCache] = [:],
        thumbnailCaches: [UUID: Data] = [:],
        proxyCaches: [UUID: Data] = [:],
        recoveryProject: ProjectFile? = nil
    ) throws -> FileWrapper {
        var entries: [String: FileWrapper] = [:]
        let projectFile = FileWrapper(regularFileWithContents: try ProjectCodec.encode(project))
        projectFile.preferredFilename = projectFileName
        entries[projectFileName] = projectFile

        for name in cacheDirectoryNames where !["waveforms", "thumbnails", "proxies", "autosave"].contains(name) {
            let directory = FileWrapper(directoryWithFileWrappers: [:])
            directory.preferredFilename = name
            entries[name] = directory
        }
        entries["waveforms"] = try waveformDirectory(caches: waveformCaches)
        entries["thumbnails"] = binaryDirectory(caches: thumbnailCaches, fileExtension: "png", name: "thumbnails")
        entries["proxies"] = binaryDirectory(caches: proxyCaches, fileExtension: "mp4", name: "proxies")
        let recoveryFile = FileWrapper(regularFileWithContents: try ProjectCodec.encode(recoveryProject ?? project))
        recoveryFile.preferredFilename = "last-known-good.json"
        let recoveryDirectory = FileWrapper(directoryWithFileWrappers: ["last-known-good.json": recoveryFile])
        recoveryDirectory.preferredFilename = "autosave"
        entries["autosave"] = recoveryDirectory

        return FileWrapper(directoryWithFileWrappers: entries)
    }

    static func readProject(from package: FileWrapper) throws -> ProjectFile {
        try readContents(from: package).project
    }

    static func readContents(from package: FileWrapper) throws -> ProjectPackageContents {
        guard package.isDirectory else {
            throw ProjectPackageError.notAPackage
        }
        let entries = package.fileWrappers ?? [:]
        let recoveryData = entries["autosave"]?.fileWrappers?["last-known-good.json"]?.regularFileContents
        let project: ProjectFile
        let recoveredFromBackup: Bool
        if let projectData = entries[projectFileName]?.regularFileContents,
           let decoded = try? ProjectCodec.decode(projectData) {
            project = decoded
            recoveredFromBackup = false
        } else if let recoveryData, let recovered = try? ProjectCodec.decode(recoveryData) {
            logger.notice("主项目文件不可用，已从恢复快照打开项目。")
            project = recovered
            recoveredFromBackup = true
        } else if entries[projectFileName]?.regularFileContents == nil {
            throw ProjectPackageError.missingProjectFile
        } else {
            throw ProjectPackageError.unreadableProjectFile
        }
        var waveformCaches: [UUID: WaveformCache] = [:]
        let waveformFiles = entries["waveforms"]?.fileWrappers ?? [:]
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
        let thumbnailCaches = binaryCaches(in: entries["thumbnails"], fileExtension: "png")
        let proxyCaches = binaryCaches(in: entries["proxies"], fileExtension: "mp4")
        return ProjectPackageContents(
            project: project,
            waveformCaches: waveformCaches,
            thumbnailCaches: thumbnailCaches,
            proxyCaches: proxyCaches,
            recoveredFromBackup: recoveredFromBackup
        )
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

    private static func binaryDirectory(
        caches: [UUID: Data],
        fileExtension: String,
        name: String
    ) -> FileWrapper {
        let entries = Dictionary(uniqueKeysWithValues: caches.map { mediaID, data in
            let file = FileWrapper(regularFileWithContents: data)
            let filename = "\(mediaID.uuidString).\(fileExtension)"
            file.preferredFilename = filename
            return (filename, file)
        })
        let directory = FileWrapper(directoryWithFileWrappers: entries)
        directory.preferredFilename = name
        return directory
    }

    private static func binaryCaches(in directory: FileWrapper?, fileExtension: String) -> [UUID: Data] {
        var result: [UUID: Data] = [:]
        for (filename, file) in directory?.fileWrappers ?? [:] {
            let identifier = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
            guard URL(fileURLWithPath: filename).pathExtension.lowercased() == fileExtension,
                  let mediaID = UUID(uuidString: identifier),
                  let data = file.regularFileContents
            else {
                continue
            }
            result[mediaID] = data
        }
        return result
    }
}

struct ProjectPackageContents {
    var project: ProjectFile
    var waveformCaches: [UUID: WaveformCache]
    var thumbnailCaches: [UUID: Data]
    var proxyCaches: [UUID: Data]
    var recoveredFromBackup: Bool
}

enum ProjectPackageError: LocalizedError, Equatable {
    case notAPackage
    case missingProjectFile
    case unreadableProjectFile

    var errorDescription: String? {
        switch self {
        case .notAPackage:
            "BeatWeave 项目必须是一个 .beatweave 包。"
        case .missingProjectFile:
            "该 BeatWeave 项目缺少 project.json。"
        case .unreadableProjectFile:
            "该 BeatWeave 项目的 project.json 无法读取，且没有可恢复的快照。"
        }
    }
}
