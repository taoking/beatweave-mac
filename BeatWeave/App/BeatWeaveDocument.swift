import SwiftUI
import UniformTypeIdentifiers

struct BeatWeaveDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.beatWeaveProject]

    var project: ProjectFile
    var waveformCaches: [UUID: WaveformCache]

    init() {
        project = .new()
        waveformCaches = [:]
    }

    init(configuration: ReadConfiguration) throws {
        let contents = try ProjectPackage.readContents(from: configuration.file)
        project = contents.project
        waveformCaches = contents.waveformCaches
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try ProjectPackage.makeFileWrapper(for: project, waveformCaches: waveformCaches)
    }
}

extension UTType {
    static let beatWeaveProject = UTType(
        exportedAs: "com.taoking.beatweave.project",
        conformingTo: .package
    )
}
