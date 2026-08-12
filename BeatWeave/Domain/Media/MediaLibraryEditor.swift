import Foundation

enum MediaLibraryEditor {
    @discardableResult
    static func append(_ candidates: [MediaReference], to library: inout MediaLibrary) -> [MediaReference] {
        let existingURLs = Set(library.items.map(\.originalURL))
        let newItems = candidates.filter { !existingURLs.contains($0.originalURL) }
        library.items.append(contentsOf: newItems)
        return newItems
    }

    @discardableResult
    static func relink(
        mediaID: UUID,
        with replacement: MediaReference,
        in library: inout MediaLibrary
    ) -> Bool {
        guard let index = library.items.firstIndex(where: { $0.id == mediaID }) else {
            return false
        }
        var relinked = replacement
        relinked.id = mediaID
        library.items[index] = relinked
        return true
    }

    @discardableResult
    static func remove(
        mediaID: UUID,
        from project: inout ProjectFile
    ) -> MediaReference? {
        guard let index = project.mediaLibrary.items.firstIndex(where: { $0.id == mediaID }) else {
            return nil
        }

        let removed = project.mediaLibrary.items.remove(at: index)
        for trackIndex in project.timeline.videoTracks.indices {
            project.timeline.videoTracks[trackIndex].clips.removeAll { $0.mediaID == mediaID }
        }
        for trackIndex in project.timeline.audioTracks.indices {
            project.timeline.audioTracks[trackIndex].clips.removeAll { $0.mediaID == mediaID }
        }
        if project.timeline.musicTrack?.mediaID == mediaID {
            project.timeline.musicTrack = nil
        }
        return removed
    }
}
