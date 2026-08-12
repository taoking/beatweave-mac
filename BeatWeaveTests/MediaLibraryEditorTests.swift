import XCTest
@testable import BeatWeave

final class MediaLibraryEditorTests: XCTestCase {
    func testAppendSkipsExistingSourceURLs() {
        let existing = mediaReference(name: "existing.mov", path: "/fixtures/existing.mov")
        let duplicate = mediaReference(name: "copy.mov", path: "/fixtures/existing.mov")
        let new = mediaReference(name: "new.mov", path: "/fixtures/new.mov")
        var library = MediaLibrary(items: [existing])

        let appended = MediaLibraryEditor.append([duplicate, new], to: &library)

        XCTAssertEqual(appended, [new])
        XCTAssertEqual(library.items, [existing, new])
    }

    func testRelinkPreservesStableMediaID() {
        let original = mediaReference(name: "missing.mov", path: "/fixtures/missing.mov")
        let replacement = mediaReference(name: "found.mov", path: "/fixtures/found.mov")
        var library = MediaLibrary(items: [original])

        let relinked = MediaLibraryEditor.relink(mediaID: original.id, with: replacement, in: &library)

        XCTAssertTrue(relinked)
        XCTAssertEqual(library.items[0].id, original.id)
        XCTAssertEqual(library.items[0].originalURL, replacement.originalURL)
        XCTAssertEqual(library.items[0].displayName, replacement.displayName)
    }

    func testRemoveMediaAlsoRemovesDependentTimelineItems() {
        let media = mediaReference(name: "remove.mov", path: "/fixtures/remove.mov")
        let retained = mediaReference(name: "retain.mov", path: "/fixtures/retain.mov")
        var project = ProjectFile.new()
        project.mediaLibrary.items = [media, retained]
        project.timeline.videoTracks = [VideoTrack(clips: [
            videoClip(mediaID: media.id),
            videoClip(mediaID: retained.id)
        ])]
        project.timeline.audioTracks = [AudioTrack(clips: [
            AudioClip(
                id: UUID(),
                mediaID: media.id,
                sourceRange: MediaTimeRange(start: .zero, duration: TimelineTime(seconds: 1)),
                timelineStart: .zero,
                volume: 1
            )
        ])]
        project.timeline.musicTrack = MusicTrack(
            mediaID: media.id,
            timelineStart: .zero,
            volume: 1,
            fadeInDuration: .zero,
            fadeOutDuration: .zero
        )

        let removed = MediaLibraryEditor.remove(mediaID: media.id, from: &project)

        XCTAssertEqual(removed, media)
        XCTAssertEqual(project.mediaLibrary.items, [retained])
        XCTAssertEqual(project.timeline.videoTracks[0].clips.map(\.mediaID), [retained.id])
        XCTAssertTrue(project.timeline.audioTracks[0].clips.isEmpty)
        XCTAssertNil(project.timeline.musicTrack)
    }

    private func mediaReference(name: String, path: String) -> MediaReference {
        MediaReference(
            displayName: name,
            originalURL: URL(fileURLWithPath: path),
            kind: .video,
            duration: TimelineTime(seconds: 1)
        )
    }

    private func videoClip(mediaID: UUID) -> TimelineClip {
        TimelineClip(
            id: UUID(),
            mediaID: mediaID,
            sourceRange: MediaTimeRange(start: .zero, duration: TimelineTime(seconds: 1)),
            timelineStart: .zero,
            playbackRate: 1,
            transform: .identity,
            opacity: 1,
            volume: 1,
            transitionIn: .hardCut,
            transitionOut: .hardCut
        )
    }
}
