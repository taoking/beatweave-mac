import SwiftUI

@main
struct BeatWeaveApp: App {
    @State private var projectStore = DefaultProjectStore()

    var body: some Scene {
        WindowGroup {
            ProjectEditorView(
                document: $projectStore.document,
                projectStore: projectStore
            )
        }
        .defaultSize(width: 1_360, height: 820)
    }
}
