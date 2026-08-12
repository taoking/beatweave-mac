import XCTest
@testable import BeatWeave

final class AutoCutEngineTests: XCTestCase {
    func testFourBeatPlanCreatesBeatAlignedSequentialPlacements() {
        let media = [video(name: "one.mov", duration: 4), video(name: "two.mov", duration: 4)]
        let plan = AutoCutEngine.makePlan(
            for: request(
                media: media,
                pattern: .every4Beats,
                range: MediaTimeRange(start: .zero, duration: TimelineTime(seconds: 8))
            )
        )

        XCTAssertEqual(plan.placements.count, 4)
        XCTAssertEqual(plan.placements.map(\.mediaID), [media[0].id, media[1].id, media[0].id, media[1].id])
        XCTAssertEqual(plan.placements.map(\.timelineStart.seconds), [0, 2, 4, 6])
        XCTAssertEqual(plan.placements.map(\.sourceRange.duration.seconds), [2, 2, 2, 2])
        XCTAssertEqual(plan.diagnostics.plannedDuration.seconds, 8, accuracy: 0.001)
    }

    func testShuffledPlanIsDeterministicForFixedSeed() {
        let media = (0..<5).map { video(name: "\($0).mov", duration: 2) }
        var shuffled = request(media: media, pattern: .everyBeat, range: MediaTimeRange(start: .zero, duration: TimelineTime(seconds: 5)))
        shuffled.preserveSourceOrder = false
        shuffled.randomSeed = 42

        let first = AutoCutEngine.makePlan(for: shuffled)
        let second = AutoCutEngine.makePlan(for: shuffled)

        XCTAssertEqual(first.placements.map(\.mediaID), second.placements.map(\.mediaID))
        XCTAssertNotEqual(first.placements.map(\.mediaID), media.prefix(first.placements.count).map(\.id))
    }

    func testPlanReportsUnfillableSegmentsWithoutMutatingTimeline() {
        let media = [video(name: "short.mov", duration: 0.4)]
        let plan = AutoCutEngine.makePlan(
            for: request(
                media: media,
                pattern: .everyBeat,
                range: MediaTimeRange(start: .zero, duration: TimelineTime(seconds: 4))
            )
        )

        XCTAssertTrue(plan.placements.isEmpty)
        XCTAssertGreaterThan(plan.diagnostics.skippedSegmentCount, 0)
        XCTAssertFalse(plan.diagnostics.messages.isEmpty)
    }

    @MainActor
    func testApplyingPlanIsOneUndoableTimelineTransaction() {
        let media = [video(name: "one.mov", duration: 4), video(name: "two.mov", duration: 4)]
        let plan = AutoCutEngine.makePlan(
            for: request(
                media: media,
                pattern: .every2Beats,
                range: MediaTimeRange(start: .zero, duration: TimelineTime(seconds: 4))
            )
        )
        var project = ProjectFile.new()
        let previousClip = TimelineClip(
            id: UUID(), mediaID: media[0].id,
            sourceRange: MediaTimeRange(start: .zero, duration: TimelineTime(seconds: 1)),
            timelineStart: .zero, playbackRate: 1, transform: .identity, opacity: 1,
            volume: 1, transitionIn: .hardCut, transitionOut: .hardCut
        )
        project.timeline.videoTracks = [VideoTrack(clips: [previousClip])]
        let model = TimelineEditorModel()

        XCTAssertTrue(model.applyAutoCut(plan, to: &project))
        XCTAssertEqual(project.timeline.videoTracks[0].clips.count, plan.placements.count)
        XCTAssertTrue(model.undo(in: &project))
        XCTAssertEqual(project.timeline.videoTracks[0].clips, [previousClip])
        XCTAssertTrue(model.redo(in: &project))
        XCTAssertEqual(project.timeline.videoTracks[0].clips.count, plan.placements.count)
    }

    private func request(
        media: [MediaReference],
        pattern: AutoCutPattern,
        range: MediaTimeRange
    ) -> AutoCutRequest {
        AutoCutRequest(
            selectedMedia: media,
            beatAnalysis: BeatAnalysis(
                bpm: 120,
                confidence: 1,
                beatTimes: stride(from: 0.5, through: 10, by: 0.5).map { TimelineTime(seconds: $0) },
                strongBeatTimes: [],
                downbeatTimes: []
            ),
            targetRange: range,
            pattern: pattern,
            minimumClipDuration: TimelineTime(seconds: 0.5),
            maximumClipDuration: TimelineTime(seconds: 4),
            preserveSourceOrder: true,
            randomSeed: 99
        )
    }

    private func video(name: String, duration: Double) -> MediaReference {
        MediaReference(
            displayName: name,
            originalURL: URL(fileURLWithPath: "/fixtures/\(name)"),
            kind: .video,
            duration: TimelineTime(seconds: duration)
        )
    }
}
