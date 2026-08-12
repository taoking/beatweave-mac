import SwiftUI

@main
struct BeatWeaveApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: BeatWeaveDocument()) { file in
            ProjectEditorView(document: file.$document)
        }
    }
}
