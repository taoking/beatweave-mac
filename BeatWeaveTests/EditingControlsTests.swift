import XCTest
@testable import BeatWeave

final class EditingControlsTests: XCTestCase {
    func testLegacyEditingModelsDecodeWithSafeDefaults() throws {
        let canvas = try JSONDecoder().decode(
            CanvasSettings.self,
            from: Data("{\"width\":1280,\"height\":720}".utf8)
        )
        XCTAssertNil(canvas.preset)

        let clip = try JSONDecoder().decode(
            TimelineClip.self,
            from: Data("""
            {
              "id":"11111111-1111-1111-1111-111111111111",
              "mediaID":"22222222-2222-2222-2222-222222222222",
              "sourceRange":{"start":{"value":0,"timescale":600},"duration":{"value":600,"timescale":600}},
              "timelineStart":{"value":0,"timescale":600},
              "playbackRate":1,
              "transform":{"scale":1,"positionX":0,"positionY":0,"rotationDegrees":0},
              "opacity":1,
              "volume":1,
              "transitionIn":"hardCut",
              "transitionOut":"hardCut"
            }
            """.utf8)
        )
        XCTAssertNil(clip.appearance)

        let audio = try JSONDecoder().decode(
            AudioClip.self,
            from: Data("""
            {
              "id":"33333333-3333-3333-3333-333333333333",
              "mediaID":"22222222-2222-2222-2222-222222222222",
              "sourceRange":{"start":{"value":0,"timescale":600},"duration":{"value":600,"timescale":600}},
              "timelineStart":{"value":0,"timescale":600},
              "volume":1
            }
            """.utf8)
        )
        XCTAssertNil(audio.isMuted)
    }

    @MainActor
    func testCanvasAndClipControlsUseUndoableCommands() throws {
        let clip = makeClip()
        var project = ProjectFile.new()
        project.timeline = Timeline(
            videoTracks: [VideoTrack(clips: [clip])],
            audioTracks: [AudioTrack(clips: [
                AudioClip(
                    id: UUID(),
                    mediaID: clip.mediaID,
                    sourceRange: clip.sourceRange,
                    timelineStart: clip.timelineStart,
                    volume: 1
                )
            ])],
            musicTrack: nil,
            markers: []
        )
        let model = TimelineEditorModel()

        XCTAssertTrue(model.updateClip(id: clip.id, name: "调色", in: &project) { edited in
            var appearance = ClipAppearance.default
            appearance.color.exposure = 0.5
            appearance.contentMode = .fill
            edited.appearance = appearance
            edited.transform.scale = 1.25
        })
        XCTAssertEqual(project.timeline.videoTracks[0].clips[0].appearance?.color.exposure, 0.5)
        XCTAssertEqual(project.timeline.videoTracks[0].clips[0].appearance?.contentMode, .fill)
        XCTAssertTrue(model.updateAudio(forVideoClipID: clip.id, name: "静音", in: &project) { audio in
            audio.isMuted = true
            audio.volume = 0.4
        })
        XCTAssertEqual(project.timeline.audioTracks[0].clips[0].isMuted, true)

        let portrait = try XCTUnwrap(CanvasPreset.portrait9x16.canvas())
        XCTAssertTrue(model.updateCanvas(portrait, in: &project))
        XCTAssertEqual(project.canvas, portrait)
        XCTAssertEqual(project.exportSettings.width, 1_080)
        XCTAssertEqual(project.exportSettings.height, 1_920)

        XCTAssertTrue(model.undo(in: &project))
        XCTAssertEqual(project.canvas, .hdLandscape)
        XCTAssertTrue(model.undo(in: &project))
        XCTAssertNil(project.timeline.audioTracks[0].clips[0].isMuted)
        XCTAssertTrue(model.undo(in: &project))
        XCTAssertNil(project.timeline.videoTracks[0].clips[0].appearance)
        XCTAssertTrue(model.redo(in: &project))
        XCTAssertEqual(project.timeline.videoTracks[0].clips[0].transform.scale, 1.25)
    }

    func testExportPlannerClampsMasterVolume() throws {
        let clip = makeClip()
        let media = MediaReference(
            id: clip.mediaID,
            displayName: "clip.mov",
            originalURL: URL(fileURLWithPath: "/fixtures/clip.mov"),
            kind: .video,
            duration: TimelineTime(seconds: 2)
        )
        var project = ProjectFile.new()
        project.mediaLibrary.items = [media]
        project.timeline = Timeline(
            videoTracks: [VideoTrack(clips: [clip])],
            audioTracks: [],
            musicTrack: nil,
            markers: [],
            masterVolume: 2
        )

        XCTAssertEqual(try ExportTimelinePlanner.makePlan(for: project).masterVolume, 1)
    }

    private func makeClip() -> TimelineClip {
        TimelineClip(
            id: UUID(),
            mediaID: UUID(),
            sourceRange: MediaTimeRange(start: .zero, duration: TimelineTime(seconds: 2)),
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
