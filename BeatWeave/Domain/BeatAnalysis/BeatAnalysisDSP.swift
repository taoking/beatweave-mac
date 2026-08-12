import Foundation

struct OnsetEnvelopePoint: Equatable, Sendable {
    var time: Double
    var strength: Double
}

struct BPMResult: Equatable, Sendable {
    var bpm: Double
    var confidence: Double
    var alternateBPMs: [Double]
}

struct BeatGrid: Equatable, Sendable {
    var beatTimes: [TimelineTime]
    var strongBeatTimes: [TimelineTime]
    var downbeatTimes: [TimelineTime]
}

enum BeatAnalysisDSP {
    static func detectOnsets(from envelope: [OnsetEnvelopePoint]) -> [Onset] {
        guard envelope.count >= 3 else { return [] }
        let smoothed = smooth(envelope.map(\.strength), radius: 2)
        let maximum = smoothed.max() ?? 0
        guard maximum > 0 else { return [] }

        var onsets: [Onset] = []
        for index in 2..<(smoothed.count - 2) {
            let local = localStatistics(smoothed, center: index, radius: 16)
            let threshold = local.mean + (local.standardDeviation * 0.5)
            let value = smoothed[index]
            guard value > threshold, value > maximum * 0.04 else { continue }
            guard (index - 2...index + 2).allSatisfy({ value >= smoothed[$0] }),
                  value > smoothed[index - 1]
            else {
                continue
            }
            onsets.append(
                Onset(
                    time: TimelineTime(seconds: envelope[index].time),
                    strength: value / maximum
                )
            )
        }
        return onsets
    }

    static func estimateBPM(
        from onsets: [Onset],
        minimumBPM: Double,
        maximumBPM: Double
    ) -> BPMResult? {
        let sortedOnsets = onsets.sorted { $0.time < $1.time }
        guard sortedOnsets.count >= 2, minimumBPM > 0, maximumBPM >= minimumBPM else {
            return nil
        }

        let candidates = bpmCandidates(
            from: sortedOnsets,
            minimumBPM: minimumBPM,
            maximumBPM: maximumBPM
        )
        guard !candidates.isEmpty else { return nil }

        let scores = candidates.map { candidate in
            score(candidateBPM: candidate, onsets: sortedOnsets)
        }
        let ranked = scores.sorted { lhs, rhs in
            lhs.score == rhs.score ? lhs.bpm > rhs.bpm : lhs.score > rhs.score
        }
        guard let best = ranked.first else { return nil }
        let runnerUpScore = ranked.dropFirst().first?.score ?? 0
        let separation = best.score == 0 ? 0 : max(0, (best.score - runnerUpScore) / best.score)
        let confidence = min(1, max(0, (best.coverage * 0.7) + (separation * 0.3)))

        let alternates = ranked.dropFirst()
            .filter { abs($0.bpm - best.bpm) >= 1 }
            .prefix(3)
            .map(\.bpm)
        return BPMResult(bpm: best.bpm, confidence: confidence, alternateBPMs: alternates)
    }

    static func makeBeatGrid(
        bpm: Double,
        duration: TimelineTime,
        onsets: [Onset]
    ) -> BeatGrid {
        guard bpm > 0, duration.seconds > 0 else {
            return BeatGrid(beatTimes: [], strongBeatTimes: [], downbeatTimes: [])
        }
        let period = 60 / bpm
        let sortedOnsets = onsets.sorted { $0.time < $1.time }
        let phase = bestPhase(period: period, onsets: sortedOnsets)
        let tolerance = min(0.08, period * 0.2)
        let firstOnsetTime = sortedOnsets.first?.time.seconds ?? phase
        let startIndex = max(0, Int(ceil((firstOnsetTime - tolerance - phase) / period)))

        var beatTimes: [TimelineTime] = []
        var strongBeatTimes: [TimelineTime] = []
        var downbeatTimes: [TimelineTime] = []
        var index = startIndex
        while true {
            let expectedTime = phase + (Double(index) * period)
            guard expectedTime <= duration.seconds + tolerance else { break }
            let refinedTime = closestOnsetTime(
                to: expectedTime,
                tolerance: tolerance,
                in: sortedOnsets
            ) ?? expectedTime
            let time = TimelineTime(seconds: min(duration.seconds, max(0, refinedTime)))
            beatTimes.append(time)
            if beatTimes.count == 1 || (beatTimes.count - 1).isMultiple(of: 4) {
                strongBeatTimes.append(time)
                downbeatTimes.append(time)
            }
            index += 1
        }
        return BeatGrid(
            beatTimes: beatTimes,
            strongBeatTimes: strongBeatTimes,
            downbeatTimes: downbeatTimes
        )
    }

    static func applyManualBPM(
        _ bpm: Double,
        mediaID: UUID,
        duration: TimelineTime,
        existingAnalysis: BeatAnalysis?
    ) -> BeatAnalysis? {
        guard (30...400).contains(bpm) else { return nil }
        let onsets = existingAnalysis?.onsets ?? []
        let grid = makeBeatGrid(bpm: bpm, duration: duration, onsets: onsets)
        var diagnostics = existingAnalysis?.diagnostics
        if var currentDiagnostics = diagnostics {
            currentDiagnostics.detectedBPM = bpm
            currentDiagnostics.beatCount = grid.beatTimes.count
            diagnostics = currentDiagnostics
        }
        return BeatAnalysis(
            mediaID: mediaID,
            bpm: bpm,
            confidence: existingAnalysis?.confidence ?? 0,
            alternateBPMs: existingAnalysis?.alternateBPMs.filter { abs($0 - bpm) >= 1 } ?? [],
            onsets: onsets,
            beatTimes: grid.beatTimes,
            strongBeatTimes: grid.strongBeatTimes,
            downbeatTimes: grid.downbeatTimes,
            parameters: existingAnalysis?.parameters,
            diagnostics: diagnostics
        )
    }

    private static func smooth(_ values: [Double], radius: Int) -> [Double] {
        values.indices.map { index in
            let lower = max(values.startIndex, index - radius)
            let upper = min(values.index(before: values.endIndex), index + radius)
            let slice = values[lower...upper]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    private static func localStatistics(
        _ values: [Double],
        center: Int,
        radius: Int
    ) -> (mean: Double, standardDeviation: Double) {
        let lower = max(values.startIndex, center - radius)
        let upper = min(values.index(before: values.endIndex), center + radius)
        let slice = values[lower...upper]
        let mean = slice.reduce(0, +) / Double(slice.count)
        let variance = slice.reduce(0) { partial, value in
            partial + ((value - mean) * (value - mean))
        } / Double(slice.count)
        return (mean, sqrt(variance))
    }

    private static func bpmCandidates(
        from onsets: [Onset],
        minimumBPM: Double,
        maximumBPM: Double
    ) -> [Double] {
        var candidates = Set<Int>()
        for startIndex in onsets.indices {
            let endIndex = min(startIndex + 8, onsets.count)
            for nextIndex in onsets.index(after: startIndex)..<endIndex {
                let interval = onsets[nextIndex].time.seconds - onsets[startIndex].time.seconds
                guard interval > 0 else { continue }
                var candidate = 60 / interval
                while candidate < minimumBPM { candidate *= 2 }
                while candidate > maximumBPM { candidate /= 2 }
                guard (minimumBPM...maximumBPM).contains(candidate) else { continue }
                candidates.insert(Int((candidate * 2).rounded()))
            }
        }
        return candidates.map { Double($0) / 2 }
    }

    private static func score(candidateBPM: Double, onsets: [Onset]) -> (bpm: Double, score: Double, coverage: Double) {
        let period = 60 / candidateBPM
        let phase = bestPhase(period: period, onsets: onsets)
        let tolerance = min(0.08, period * 0.2)
        let start = onsets.first?.time.seconds ?? phase
        let end = onsets.last?.time.seconds ?? start
        let firstIndex = max(0, Int(ceil((start - tolerance - phase) / period)))
        let lastIndex = max(firstIndex, Int(floor((end + tolerance - phase) / period)))
        let maximumStrength = onsets.map(\.strength).max() ?? 1
        var matched = 0
        var strengthSum = 0.0
        for index in firstIndex...lastIndex {
            let expectedTime = phase + (Double(index) * period)
            if let onset = closestOnset(to: expectedTime, tolerance: tolerance, in: onsets) {
                matched += 1
                strengthSum += onset.strength / maximumStrength
            }
        }
        let expectedCount = max(1, lastIndex - firstIndex + 1)
        let coverage = Double(matched) / Double(expectedCount)
        let normalizedStrength = strengthSum / Double(expectedCount)
        let score = normalizedStrength * log1p(Double(matched))
        return (candidateBPM, score, coverage)
    }

    private static func bestPhase(period: Double, onsets: [Onset]) -> Double {
        guard let first = onsets.first, period > 0 else { return 0 }
        let candidates = Set(onsets.map { onset in
            Int((onset.time.seconds.truncatingRemainder(dividingBy: period) * 10_000).rounded())
        })
        let tolerance = min(0.08, period * 0.2)
        let maximumStrength = onsets.map(\.strength).max() ?? 1
        var best = (phase: first.time.seconds.truncatingRemainder(dividingBy: period), score: -Double.infinity)
        for candidate in candidates {
            let phase = Double(candidate) / 10_000
            let start = onsets.first?.time.seconds ?? phase
            let end = onsets.last?.time.seconds ?? start
            let firstIndex = max(0, Int(ceil((start - tolerance - phase) / period)))
            let lastIndex = max(firstIndex, Int(floor((end + tolerance - phase) / period)))
            var score = 0.0
            for index in firstIndex...lastIndex {
                let expectedTime = phase + (Double(index) * period)
                if let onset = closestOnset(to: expectedTime, tolerance: tolerance, in: onsets) {
                    score += onset.strength / maximumStrength
                }
            }
            if score > best.score {
                best = (phase, score)
            }
        }
        return best.phase
    }

    private static func closestOnsetTime(to time: Double, tolerance: Double, in onsets: [Onset]) -> Double? {
        closestOnset(to: time, tolerance: tolerance, in: onsets)?.time.seconds
    }

    private static func closestOnset(to time: Double, tolerance: Double, in onsets: [Onset]) -> Onset? {
        let candidate = onsets.min { lhs, rhs in
            abs(lhs.time.seconds - time) < abs(rhs.time.seconds - time)
        }
        guard let candidate, abs(candidate.time.seconds - time) <= tolerance else { return nil }
        return candidate
    }
}

struct TapTempoTracker: Sendable {
    private var tapTimes: [TimeInterval] = []

    mutating func registerTap(at time: TimeInterval) -> Double? {
        if let previous = tapTimes.last, time - previous > 3 {
            tapTimes.removeAll(keepingCapacity: true)
        }
        tapTimes.append(time)
        tapTimes = Array(tapTimes.suffix(8))
        guard tapTimes.count >= 2 else { return nil }

        let intervals = zip(tapTimes, tapTimes.dropFirst()).map { previous, next in
            next - previous
        }
        guard intervals.allSatisfy({ (0.15...2).contains($0) }) else { return nil }
        let sorted = intervals.sorted()
        let median = sorted[sorted.count / 2]
        let bpm = 60 / median
        return (30...400).contains(bpm) ? bpm : nil
    }
}
