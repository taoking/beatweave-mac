import XCTest
@testable import BeatWeave

final class SmartMontageTests: XCTestCase {
    func testSmartPlanHonorsExcludedAndPinnedMediaBeforeScores() {
        let excluded = video("excluded", duration: 8)
        let pinned = video("pinned", duration: 8)
        let scored = video("scored", duration: 8)
        let settings = SmartMontageSettings(
            analyses: [
                pinned.id: analysis(score: 0.1),
                scored.id: analysis(score: 0.9)
            ],
            decisions: [excluded.id: .excluded, pinned.id: .pinned]
        )
        let plan = AutoCutEngine.makePlan(for: request(
            media: [excluded, scored, pinned],
            smartMontage: settings
        ))

        XCTAssertFalse(plan.placements.contains { $0.mediaID == excluded.id })
        XCTAssertEqual(plan.placements.first?.mediaID, pinned.id)
    }

    func testSmartPlanUsesDistinctSourceRangesBeforeReusingFootage() {
        let media = video("long", duration: 12)
        let plan = AutoCutEngine.makePlan(for: request(
            media: [media],
            smartMontage: SmartMontageSettings(analyses: [media.id: analysis(score: 0.8)])
        ))

        XCTAssertGreaterThan(plan.placements.count, 2)
        XCTAssertEqual(plan.placements[0].sourceRange.start.seconds, 0, accuracy: 0.001)
        XCTAssertGreaterThan(plan.placements[1].sourceRange.start.seconds, 0)
    }

    func testStrongBeatModeUsesStrongBeatGrid() {
        let media = video("strong", duration: 12)
        var request = self.request(media: [media], smartMontage: SmartMontageSettings())
        request.prefersStrongBeats = true
        request.beatAnalysis.strongBeatTimes = [TimelineTime(seconds: 2), TimelineTime(seconds: 4)]
        let plan = AutoCutEngine.makePlan(for: request)

        XCTAssertEqual(plan.placements.map { $0.timelineStart.seconds }, [0, 2, 4])
    }

    private func request(media: [MediaReference], smartMontage: SmartMontageSettings?) -> AutoCutRequest {
        AutoCutRequest(
            selectedMedia: media,
            beatAnalysis: BeatAnalysis(
                bpm: 120,
                confidence: 1,
                beatTimes: [TimelineTime(seconds: 1), TimelineTime(seconds: 2), TimelineTime(seconds: 3), TimelineTime(seconds: 4)],
                strongBeatTimes: [],
                downbeatTimes: []
            ),
            targetRange: MediaTimeRange(start: .zero, duration: TimelineTime(seconds: 5)),
            pattern: .everyBeat,
            minimumClipDuration: TimelineTime(seconds: 0.5),
            maximumClipDuration: TimelineTime(seconds: 4),
            preserveSourceOrder: true,
            randomSeed: 1,
            smartMontage: smartMontage
        )
    }

    private func analysis(score: Double) -> MediaQualityAnalysis {
        MediaQualityAnalysis(overallScore: score, visualQualityScore: score, motionScore: score, faceScore: 0, rangeScores: [])
    }

    private func video(_ name: String, duration: Double) -> MediaReference {
        MediaReference(displayName: name, originalURL: URL(fileURLWithPath: "/fixtures/\(name).mov"), kind: .video, duration: TimelineTime(seconds: duration))
    }
}
