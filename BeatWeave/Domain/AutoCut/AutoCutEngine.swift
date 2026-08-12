import Foundation

enum AutoCutPattern: Int, CaseIterable, Identifiable, Sendable {
    case everyBeat = 1
    case every2Beats = 2
    case every4Beats = 4
    case every8Beats = 8

    var id: Int { rawValue }

    var displayName: String {
        rawValue == 1 ? "每 1 拍" : "每 \(rawValue) 拍"
    }
}

struct AutoCutRequest: Sendable {
    var selectedMedia: [MediaReference]
    var beatAnalysis: BeatAnalysis
    var targetRange: MediaTimeRange
    var pattern: AutoCutPattern
    var minimumClipDuration: TimelineTime
    var maximumClipDuration: TimelineTime
    var preserveSourceOrder: Bool
    var randomSeed: UInt64
}

struct AutoCutPlacement: Equatable, Sendable, Identifiable {
    var id: UUID
    var mediaID: UUID
    var sourceRange: MediaTimeRange
    var timelineStart: TimelineTime
}

struct AutoCutDiagnostics: Equatable, Sendable {
    var targetDuration: TimelineTime
    var plannedDuration: TimelineTime
    var beatBoundaryCount: Int
    var skippedSegmentCount: Int
    var messages: [String]
}

struct AutoCutPlan: Equatable, Sendable, Identifiable {
    var id: UUID
    var placements: [AutoCutPlacement]
    var unusedMediaIDs: [UUID]
    var diagnostics: AutoCutDiagnostics
}

enum AutoCutEngine {
    static func makePlan(for request: AutoCutRequest) -> AutoCutPlan {
        let sourceMedia = request.selectedMedia.filter { $0.kind == .video && $0.duration > .zero }
        guard request.targetRange.duration > .zero,
              request.minimumClipDuration > .zero,
              request.maximumClipDuration >= request.minimumClipDuration,
              !sourceMedia.isEmpty
        else {
            return emptyPlan(
                request: request,
                message: sourceMedia.isEmpty ? "请至少选择一个可用视频素材。" : "AutoCut 时长参数无效。"
            )
        }

        let boundaries = cutBoundaries(for: request)
        guard boundaries.count >= 2 else {
            return emptyPlan(request: request, message: "目标音乐区间内没有足够的节拍边界。")
        }
        let sources = request.preserveSourceOrder ? sourceMedia : shuffled(sourceMedia, seed: request.randomSeed)
        var sourceCursor = 0
        var placements: [AutoCutPlacement] = []
        var usedMediaIDs = Set<UUID>()
        var skippedSegments = 0

        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            let duration = end.seconds - start.seconds
            guard duration >= request.minimumClipDuration.seconds else { continue }
            guard let media = nextSource(
                from: sources,
                cursor: &sourceCursor,
                minimumDuration: duration
            ) else {
                skippedSegments += 1
                continue
            }
            placements.append(
                AutoCutPlacement(
                    id: UUID(),
                    mediaID: media.id,
                    sourceRange: MediaTimeRange(start: .zero, duration: TimelineTime(seconds: duration)),
                    timelineStart: start
                )
            )
            usedMediaIDs.insert(media.id)
        }

        let plannedDuration = placements.reduce(0) { partial, placement in
            partial + placement.sourceRange.duration.seconds
        }
        var messages: [String] = []
        if skippedSegments > 0 {
            messages.append("\(skippedSegments) 个节拍片段没有足够长的源视频，未加入计划。")
        }
        if placements.isEmpty {
            messages.append("没有素材满足所选节拍片段的最小时长。")
        }
        return AutoCutPlan(
            id: UUID(),
            placements: placements,
            unusedMediaIDs: sourceMedia.map(\.id).filter { !usedMediaIDs.contains($0) },
            diagnostics: AutoCutDiagnostics(
                targetDuration: request.targetRange.duration,
                plannedDuration: TimelineTime(seconds: plannedDuration),
                beatBoundaryCount: boundaries.count,
                skippedSegmentCount: skippedSegments,
                messages: messages
            )
        )
    }

    private static func cutBoundaries(for request: AutoCutRequest) -> [TimelineTime] {
        let rangeStart = request.targetRange.start.seconds
        let rangeEnd = rangeStart + request.targetRange.duration.seconds
        let beats = request.beatAnalysis.beatTimes
            .map(\.seconds)
            .filter { $0 > rangeStart && $0 < rangeEnd }
            .sorted()
        var boundaries = [TimelineTime(seconds: rangeStart)]
        var beatCountSinceCut = 0
        for beat in beats {
            let interval = beat - (boundaries.last?.seconds ?? rangeStart)
            beatCountSinceCut += 1
            let reachesPattern = beatCountSinceCut >= request.pattern.rawValue
            let reachesMaximum = interval >= request.maximumClipDuration.seconds
            guard interval >= request.minimumClipDuration.seconds, reachesPattern || reachesMaximum else { continue }
            boundaries.append(TimelineTime(seconds: beat))
            beatCountSinceCut = 0
        }
        if let last = boundaries.last, rangeEnd - last.seconds < request.minimumClipDuration.seconds, boundaries.count > 1 {
            boundaries.removeLast()
        }
        if boundaries.last?.seconds != rangeEnd {
            boundaries.append(TimelineTime(seconds: rangeEnd))
        }
        return boundaries
    }

    private static func nextSource(
        from sources: [MediaReference],
        cursor: inout Int,
        minimumDuration: Double
    ) -> MediaReference? {
        guard !sources.isEmpty else { return nil }
        for offset in sources.indices {
            let index = (cursor + offset) % sources.count
            let candidate = sources[index]
            if candidate.duration.seconds >= minimumDuration {
                cursor = (index + 1) % sources.count
                return candidate
            }
        }
        return nil
    }

    private static func shuffled(_ media: [MediaReference], seed: UInt64) -> [MediaReference] {
        var result = media
        var generator = SeededRandomNumberGenerator(seed: seed)
        guard result.count > 1 else { return result }
        for index in stride(from: result.count - 1, through: 1, by: -1) {
            let swapIndex = Int(generator.next() % UInt64(index + 1))
            result.swapAt(index, swapIndex)
        }
        return result
    }

    private static func emptyPlan(request: AutoCutRequest, message: String) -> AutoCutPlan {
        AutoCutPlan(
            id: UUID(),
            placements: [],
            unusedMediaIDs: request.selectedMedia.filter { $0.kind == .video }.map(\.id),
            diagnostics: AutoCutDiagnostics(
                targetDuration: request.targetRange.duration,
                plannedDuration: .zero,
                beatBoundaryCount: 0,
                skippedSegmentCount: 0,
                messages: [message]
            )
        )
    }
}

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
