import XCTest
@testable import BeatWeave

final class ExportTimelinePlannerTests: XCTestCase {
    func testPlanUsesCanonicalTimelineDurationsForExportTiming() throws {
        let video = MediaReference(
            displayName: "timing.mov",
            originalURL: URL(fileURLWithPath: "/fixtures/timing.mov"),
            kind: .video,
            duration: TimelineTime(seconds: 10)
        )
        var project = ProjectFile.new()
        project.mediaLibrary.items = [video]
        project.timeline.videoTracks = [VideoTrack(clips: [
            TimelineClip(
                id: UUID(), mediaID: video.id,
                sourceRange: MediaTimeRange(start: TimelineTime(seconds: 2), duration: TimelineTime(seconds: 6)),
                timelineStart: TimelineTime(seconds: 1), playbackRate: 2,
                transform: .identity, opacity: 1, volume: 1,
                transitionIn: .hardCut, transitionOut: .hardCut
            )
        ])]

        let plan = try ExportTimelinePlanner.makePlan(for: project)

        XCTAssertEqual(plan.videoSegments.count, 1)
        XCTAssertEqual(plan.videoSegments[0].clip.timelineDuration.seconds, 3, accuracy: 0.001)
        XCTAssertEqual(plan.duration.seconds, 4, accuracy: 0.001)
    }

    func testPlanRejectsOverlappingVideoClips() {
        let video = MediaReference(
            displayName: "overlap.mov",
            originalURL: URL(fileURLWithPath: "/fixtures/overlap.mov"),
            kind: .video,
            duration: TimelineTime(seconds: 10)
        )
        var project = ProjectFile.new()
        project.mediaLibrary.items = [video]
        project.timeline.videoTracks = [VideoTrack(clips: [
            clip(mediaID: video.id, start: 0, duration: 3),
            clip(mediaID: video.id, start: 2, duration: 3)
        ])]

        XCTAssertThrowsError(try ExportTimelinePlanner.makePlan(for: project)) { error in
            XCTAssertEqual(error as? ExportTimelinePlanError, .overlappingVideoClips)
        }
    }

    func testPlanRejectsMissingVideoMedia() {
        var project = ProjectFile.new()
        project.timeline.videoTracks = [VideoTrack(clips: [clip(mediaID: UUID(), start: 0, duration: 1)])]

        XCTAssertThrowsError(try ExportTimelinePlanner.makePlan(for: project)) { error in
            guard case .missingMedia = error as? ExportTimelinePlanError else {
                return XCTFail("Expected missing media error, got \(error)")
            }
        }
    }

    func testDeliveryPresetChangesTheCompleteExportSettings() {
        let social = ExportDeliveryPreset.socialVertical.settings
        let master = ExportDeliveryPreset.master4K.settings

        XCTAssertEqual(social.codec, .h264)
        XCTAssertEqual(social.width, 1_080)
        XCTAssertEqual(social.height, 1_920)
        XCTAssertEqual(master.codec, .hevc)
        XCTAssertEqual(master.frameRate, .fps60)
        XCTAssertEqual(ExportDeliveryPreset.closest(to: master), .master4K)
    }

    private func clip(mediaID: UUID, start: Double, duration: Double) -> TimelineClip {
        TimelineClip(
            id: UUID(), mediaID: mediaID,
            sourceRange: MediaTimeRange(start: .zero, duration: TimelineTime(seconds: duration)),
            timelineStart: TimelineTime(seconds: start), playbackRate: 1,
            transform: .identity, opacity: 1, volume: 1,
            transitionIn: .hardCut, transitionOut: .hardCut
        )
    }
}
