import XCTest
@testable import BeatWeave

final class TimelineEngineTests: XCTestCase {
    func testAppendUsesBeatSnapNearExistingTimelineEnd() {
        let first = video(name: "first.mov", duration: 2)
        let second = video(name: "second.mov", duration: 3)
        let beatAnalysis = BeatAnalysis(
            bpm: 120,
            confidence: 1,
            beatTimes: [TimelineTime(seconds: 2.04)],
            strongBeatTimes: [],
            downbeatTimes: []
        )
        let configuration = TimelineSnapConfiguration()
        let firstResult = TimelineEngine.append(
            media: first,
            to: .init(videoTracks: [], audioTracks: [], musicTrack: nil, markers: []),
            beatAnalysis: beatAnalysis,
            playhead: TimelineTime(seconds: 10),
            snapConfiguration: configuration,
            pointsPerSecond: 80
        )
        let secondResult = TimelineEngine.append(
            media: second,
            to: firstResult.timeline,
            beatAnalysis: beatAnalysis,
            playhead: TimelineTime(seconds: 10),
            snapConfiguration: configuration,
            pointsPerSecond: 80
        )

        XCTAssertEqual(secondResult.snap.target, .beat)
        XCTAssertEqual(secondResult.timeline.videoTracks[0].clips[1].timelineStart.seconds, 2.04, accuracy: 0.001)
        XCTAssertEqual(secondResult.timeline.audioTracks[0].clips.count, 2)
        XCTAssertEqual(secondResult.timeline.audioTracks[0].clips[1].timelineStart.seconds, 2.04, accuracy: 0.001)
    }

    func testTrimChangesSourceRangeAndTimelineBoundaryTogether() throws {
        let clip = makeClip(start: 0, duration: 10)
        let timeline = timeline(with: [clip])
        let trimmedStart = try XCTUnwrap(
            TimelineEngine.trimStart(clipID: clip.id, to: TimelineTime(seconds: 2), in: timeline)
        )
        let startClip = try XCTUnwrap(trimmedStart.videoTracks[0].clips.first)
        XCTAssertEqual(startClip.timelineStart.seconds, 2, accuracy: 0.001)
        XCTAssertEqual(startClip.sourceRange.start.seconds, 2, accuracy: 0.001)
        XCTAssertEqual(startClip.sourceRange.duration.seconds, 8, accuracy: 0.001)

        let trimmedEnd = try XCTUnwrap(
            TimelineEngine.trimEnd(clipID: clip.id, to: TimelineTime(seconds: 8), in: timeline)
        )
        XCTAssertEqual(trimmedEnd.videoTracks[0].clips[0].sourceRange.duration.seconds, 8, accuracy: 0.001)
    }

    func testInsertSplitsContainingClipAndRipplesLaterMaterial() {
        let base = video(name: "base.mov", duration: 4)
        let inserted = video(name: "inserted.mov", duration: 1)
        let initial = TimelineEngine.append(
            media: base,
            to: .init(videoTracks: [], audioTracks: [], musicTrack: nil, markers: []),
            beatAnalysis: nil,
            playhead: TimelineTime(seconds: 10),
            snapConfiguration: .init(isEnabled: false),
            pointsPerSecond: 80
        ).timeline

        let result = TimelineEngine.insert(
            media: inserted,
            at: TimelineTime(seconds: 2),
            in: initial,
            beatAnalysis: nil,
            playhead: TimelineTime(seconds: 10),
            snapConfiguration: .init(isEnabled: false),
            pointsPerSecond: 80
        )
        let clips = result.timeline.videoTracks[0].clips

        XCTAssertEqual(clips.count, 3)
        XCTAssertEqual(clips[0].timelineStart.seconds, 0, accuracy: 0.001)
        XCTAssertEqual(clips[0].sourceRange.duration.seconds, 2, accuracy: 0.001)
        XCTAssertEqual(clips[1].mediaID, inserted.id)
        XCTAssertEqual(clips[1].timelineStart.seconds, 2, accuracy: 0.001)
        XCTAssertEqual(clips[2].timelineStart.seconds, 3, accuracy: 0.001)
        XCTAssertEqual(clips[2].sourceRange.start.seconds, 2, accuracy: 0.001)
        XCTAssertEqual(result.timeline.audioTracks[0].clips.count, 3)
    }

    func testSplitPreservesSourceCoverage() throws {
        let clip = makeClip(start: 1, duration: 8)
        let split = try XCTUnwrap(
            TimelineEngine.split(clipID: clip.id, at: TimelineTime(seconds: 4), in: timeline(with: [clip]))
        )
        let clips = split.videoTracks[0].clips

        XCTAssertEqual(clips.count, 2)
        XCTAssertEqual(clips[0].sourceRange.duration.seconds, 3, accuracy: 0.001)
        XCTAssertEqual(clips[1].sourceRange.start.seconds, 3, accuracy: 0.001)
        XCTAssertEqual(clips[1].sourceRange.duration.seconds, 5, accuracy: 0.001)
        XCTAssertEqual(clips[1].timelineStart.seconds, 4, accuracy: 0.001)
    }

    func testRippleDeleteClosesRemovedClipDuration() throws {
        let first = makeClip(start: 0, duration: 2)
        let second = makeClip(start: 2, duration: 3)
        let updated = try XCTUnwrap(
            TimelineEngine.delete(clipID: first.id, ripple: true, in: timeline(with: [first, second]))
        )

        XCTAssertEqual(updated.videoTracks[0].clips.count, 1)
        XCTAssertEqual(updated.videoTracks[0].clips[0].timelineStart.seconds, 0, accuracy: 0.001)
    }

    func testPlayheadSnapHasPriorityOverBeatAndClipEdges() {
        let clip = makeClip(start: 0, duration: 5)
        let beats = BeatAnalysis(
            bpm: 120,
            confidence: 1,
            beatTimes: [TimelineTime(seconds: 5)],
            strongBeatTimes: [],
            downbeatTimes: []
        )

        let snap = TimelineEngine.snappedTime(
            TimelineTime(seconds: 5.03),
            in: timeline(with: [clip]),
            beatAnalysis: beats,
            playhead: TimelineTime(seconds: 5.05),
            configuration: .init(),
            pointsPerSecond: 80
        )

        XCTAssertEqual(snap.target, .playhead)
        XCTAssertEqual(snap.time.seconds, 5.05, accuracy: 0.001)
    }

    func testMoveReordersClipsByTimelineStart() throws {
        let first = makeClip(start: 0, duration: 2)
        let second = makeClip(start: 2, duration: 2)
        let result = try XCTUnwrap(
            TimelineEngine.move(
                clipID: first.id,
                to: TimelineTime(seconds: 3),
                in: timeline(with: [first, second]),
                beatAnalysis: nil,
                playhead: TimelineTime(seconds: 10),
                snapConfiguration: .init(isEnabled: false),
                pointsPerSecond: 80
            )
        )

        XCTAssertEqual(result.timeline.videoTracks[0].clips.first?.id, second.id)
        XCTAssertEqual(result.timeline.videoTracks[0].clips.last?.id, first.id)
        XCTAssertEqual(try XCTUnwrap(result.timeline.videoTracks[0].clips.last).timelineStart.seconds, 3, accuracy: 0.001)
    }

    @MainActor
    func testUndoAndRedoRestoreTimelineSnapshots() {
        let media = video(name: "undo.mov", duration: 2)
        var project = ProjectFile.new()
        let model = TimelineEditorModel()

        XCTAssertTrue(
            model.append(
                media: media,
                to: &project,
                beatAnalysis: nil,
                playhead: .zero,
                pointsPerSecond: 80
            )
        )
        XCTAssertEqual(project.timeline.videoTracks[0].clips.count, 1)
        XCTAssertTrue(model.undo(in: &project))
        XCTAssertTrue(project.timeline.videoTracks.isEmpty)
        XCTAssertTrue(model.redo(in: &project))
        XCTAssertEqual(project.timeline.videoTracks[0].clips.count, 1)
    }

    private func video(name: String, duration: Double) -> MediaReference {
        MediaReference(
            displayName: name,
            originalURL: URL(fileURLWithPath: "/fixtures/\(name)"),
            kind: .video,
            duration: TimelineTime(seconds: duration)
        )
    }

    private func makeClip(start: Double, duration: Double) -> TimelineClip {
        TimelineClip(
            id: UUID(),
            mediaID: UUID(),
            sourceRange: MediaTimeRange(start: .zero, duration: TimelineTime(seconds: duration)),
            timelineStart: TimelineTime(seconds: start),
            playbackRate: 1,
            transform: .identity,
            opacity: 1,
            volume: 1,
            transitionIn: .hardCut,
            transitionOut: .hardCut
        )
    }

    private func timeline(with clips: [TimelineClip]) -> Timeline {
        Timeline(videoTracks: [VideoTrack(clips: clips)], audioTracks: [], musicTrack: nil, markers: [])
    }
}
