import SwiftUI
import UniformTypeIdentifiers

struct BeatWeaveDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.beatWeaveProject]

    var project: ProjectFile
    var waveformCaches: [UUID: WaveformCache]
    var thumbnailCaches: [UUID: Data]
    var proxyCaches: [UUID: Data]
    var recoveredFromBackup: Bool

    init() {
        project = .new()
        waveformCaches = [:]
        thumbnailCaches = [:]
        proxyCaches = [:]
        recoveredFromBackup = false
    }

    init(configuration: ReadConfiguration) throws {
        let contents = try ProjectPackage.readContents(from: configuration.file)
        project = contents.project
        waveformCaches = contents.waveformCaches
        thumbnailCaches = contents.thumbnailCaches
        proxyCaches = contents.proxyCaches
        recoveredFromBackup = contents.recoveredFromBackup
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // On subsequent saves keep the prior readable model as the recovery target.
        // The current model is still used on a first save, so every package always
        // contains a valid snapshot.
        let recoveryProject = configuration.existingFile.flatMap { existing in
            try? ProjectPackage.readProject(from: existing)
        }
        return try ProjectPackage.makeFileWrapper(
            for: project,
            waveformCaches: waveformCaches,
            thumbnailCaches: thumbnailCaches,
            proxyCaches: proxyCaches,
            recoveryProject: recoveryProject
        )
    }
}

extension UTType {
    static let beatWeaveProject = UTType(
        exportedAs: "com.taoking.beatweave.project",
        conformingTo: .package
    )
}
