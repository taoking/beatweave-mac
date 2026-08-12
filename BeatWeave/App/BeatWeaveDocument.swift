import SwiftUI
import UniformTypeIdentifiers

struct BeatWeaveDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.beatWeaveProject]

    var project: ProjectFile

    init() {
        project = .new()
    }

    init(configuration: ReadConfiguration) throws {
        project = try ProjectPackage.readProject(from: configuration.file)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try ProjectPackage.makeFileWrapper(for: project)
    }
}

extension UTType {
    static let beatWeaveProject = UTType(
        exportedAs: "com.taoking.beatweave.project",
        conformingTo: .package
    )
}
