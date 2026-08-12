import SwiftUI

struct ProjectEditorView: View {
    @Binding private var document: BeatWeaveDocument
    @State private var selectedMediaID: UUID?
    @State private var mediaBrowser = MediaBrowserModel()
    @State private var playback = PlaybackService()

    init(document: Binding<BeatWeaveDocument>) {
        _document = document
    }

    var body: some View {
        NavigationSplitView {
            MediaBrowserView(
                project: $document.project,
                selectedMediaID: $selectedMediaID,
                model: mediaBrowser,
                onProjectMutation: markProjectModified
            )
        } detail: {
            ViewerView(
                selectedMedia: selectedMedia,
                playback: playback
            )
            .navigationTitle(document.project.name)
        }
        .frame(minWidth: 900, minHeight: 560)
        .task {
            await mediaBrowser.refreshSourceStatuses(for: document.project.mediaLibrary.items)
        }
        .onChange(of: selectedMediaID) { _, _ in
            playback.preview(selectedMedia)
        }
        .onChange(of: document.project.mediaLibrary.items) { _, items in
            Task {
                await mediaBrowser.refreshSourceStatuses(for: items)
            }
        }
    }

    private var selectedMedia: MediaReference? {
        guard let selectedMediaID else {
            return nil
        }
        return document.project.mediaLibrary.items.first { $0.id == selectedMediaID }
    }

    private func markProjectModified() {
        document.project.markModified()
    }
}
