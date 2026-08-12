import Foundation
import Observation

@MainActor
@Observable
final class AutoCutModel {
    var selectedMediaIDs = Set<UUID>()
    var pattern: AutoCutPattern = .every4Beats
    var preservesSourceOrder = true
    var minimumDuration = 0.5
    var maximumDuration = 12.0
    var targetStart = 0.0
    var targetEnd = 0.0
    var plan: AutoCutPlan?

    func preparePlan(
        media: [MediaReference],
        beatAnalysis: BeatAnalysis,
        musicDuration: TimelineTime
    ) {
        let normalizedStart = min(max(0, targetStart), musicDuration.seconds)
        let normalizedEnd = targetEnd > normalizedStart
            ? min(targetEnd, musicDuration.seconds)
            : musicDuration.seconds
        let selectedMedia = media.filter { selectedMediaIDs.contains($0.id) }
        plan = AutoCutEngine.makePlan(
            for: AutoCutRequest(
                selectedMedia: selectedMedia,
                beatAnalysis: beatAnalysis,
                targetRange: MediaTimeRange(
                    start: TimelineTime(seconds: normalizedStart),
                    duration: TimelineTime(seconds: max(0, normalizedEnd - normalizedStart))
                ),
                pattern: pattern,
                minimumClipDuration: TimelineTime(seconds: max(0.1, minimumDuration)),
                maximumClipDuration: TimelineTime(seconds: max(minimumDuration, maximumDuration)),
                preserveSourceOrder: preservesSourceOrder,
                randomSeed: 0xBEE7_2026
            )
        )
    }

    func clearPlan() {
        plan = nil
    }

    func selectAllVideos(in media: [MediaReference]) {
        selectedMediaIDs = Set(media.filter { $0.kind == .video }.map(\.id))
    }

    func setMedia(_ mediaID: UUID, isSelected: Bool) {
        if isSelected {
            selectedMediaIDs.insert(mediaID)
        } else {
            selectedMediaIDs.remove(mediaID)
        }
    }
}
