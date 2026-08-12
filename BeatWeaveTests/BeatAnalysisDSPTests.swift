import XCTest
@testable import BeatWeave

final class BeatAnalysisDSPTests: XCTestCase {
    func testPeakPickerFindsSyntheticOnsets() {
        var envelope = (0..<180).map { index in
            OnsetEnvelopePoint(time: Double(index) * 0.05, strength: 0.002)
        }
        for index in stride(from: 10, through: 150, by: 10) {
            envelope[index].strength = 1
        }

        let onsets = BeatAnalysisDSP.detectOnsets(from: envelope)

        XCTAssertGreaterThanOrEqual(onsets.count, 14)
        XCTAssertEqual(onsets.first?.time.seconds ?? 0, 0.4, accuracy: 0.1)
    }

    func testBPMEstimatorPrefersFull120BPMGridOverHalfTempo() throws {
        let onsets = syntheticOnsets(interval: 0.5, count: 16)

        let result = try XCTUnwrap(
            BeatAnalysisDSP.estimateBPM(from: onsets, minimumBPM: 60, maximumBPM: 200)
        )

        XCTAssertEqual(result.bpm, 120, accuracy: 0.5)
        XCTAssertTrue(result.alternateBPMs.contains { abs($0 - 60) <= 0.5 })
        XCTAssertGreaterThan(result.confidence, 0.5)
    }

    func testBeatGridSnapsToOnsetsWithoutAccumulatingDrift() {
        let onsets = syntheticOnsets(interval: 0.5, count: 12).enumerated().map { index, onset in
            var adjusted = onset
            adjusted.time = TimelineTime(seconds: onset.time.seconds + (index.isMultiple(of: 2) ? 0.02 : -0.02))
            return adjusted
        }

        let grid = BeatAnalysisDSP.makeBeatGrid(
            bpm: 120,
            duration: TimelineTime(seconds: 6),
            onsets: onsets
        )

        XCTAssertGreaterThanOrEqual(grid.beatTimes.count, 11)
        XCTAssertEqual(grid.beatTimes[1].seconds - grid.beatTimes[0].seconds, 0.46, accuracy: 0.08)
        XCTAssertEqual(grid.beatTimes[5].seconds - grid.beatTimes[4].seconds, 0.46, accuracy: 0.08)
        XCTAssertEqual(grid.strongBeatTimes.first, grid.beatTimes.first)
        XCTAssertEqual(grid.downbeatTimes.first, grid.beatTimes.first)
    }

    func testManualBPMRebuildsGridAndPreservesDetectedOnsets() throws {
        let onsets = syntheticOnsets(interval: 0.5, count: 10)
        let existing = BeatAnalysis(
            mediaID: UUID(),
            bpm: 120,
            confidence: 0.7,
            onsets: onsets,
            beatTimes: [],
            strongBeatTimes: [],
            downbeatTimes: []
        )

        let updated = try XCTUnwrap(
            BeatAnalysisDSP.applyManualBPM(
                90,
                mediaID: UUID(),
                duration: TimelineTime(seconds: 8),
                existingAnalysis: existing
            )
        )

        XCTAssertEqual(updated.bpm, 90)
        XCTAssertEqual(updated.onsets, onsets)
        XCTAssertEqual(updated.beatTimes[1].seconds - updated.beatTimes[0].seconds, 60 / 90, accuracy: 0.01)
    }

    func testTapTempoUsesMedianOfRecentIntervals() {
        var tracker = TapTempoTracker()
        XCTAssertNil(tracker.registerTap(at: 1))
        XCTAssertEqual(tracker.registerTap(at: 1.5) ?? 0, 120, accuracy: 0.1)
        XCTAssertEqual(tracker.registerTap(at: 2.0) ?? 0, 120, accuracy: 0.1)
        XCTAssertEqual(tracker.registerTap(at: 2.52) ?? 0, 120, accuracy: 3)
    }

    private func syntheticOnsets(interval: Double, count: Int) -> [Onset] {
        (0..<count).map { index in
            Onset(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1)) ?? UUID(),
                time: TimelineTime(seconds: 0.5 + (Double(index) * interval)),
                strength: 1
            )
        }
    }
}
