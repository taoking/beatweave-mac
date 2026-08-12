import Foundation

extension TimelineClip {
    var timelineDuration: TimelineTime {
        TimelineTime(seconds: sourceRange.duration.seconds / max(playbackRate, .leastNonzeroMagnitude))
    }

    var timelineEnd: TimelineTime {
        TimelineTime(seconds: timelineStart.seconds + timelineDuration.seconds)
    }
}

extension AudioClip {
    var timelineDuration: TimelineTime {
        sourceRange.duration
    }

    var timelineEnd: TimelineTime {
        TimelineTime(seconds: timelineStart.seconds + timelineDuration.seconds)
    }
}

enum TimelineSnapTarget: String, Equatable, Sendable {
    case playhead
    case beat
    case clipEdge
    case marker
}

struct TimelineSnapConfiguration: Equatable, Sendable {
    var isEnabled: Bool = true
    var snapToBeats: Bool = true
    var snapToClipEdges: Bool = true
    var snapToMarkers: Bool = true

    /// Eight screen points gives a visible but non-sticky target at every timeline zoom level.
    static let visualSnapDistance = 8.0
    static let minimumToleranceSeconds = 0.02

    func tolerance(pointsPerSecond: Double) -> Double {
        max(Self.minimumToleranceSeconds, Self.visualSnapDistance / max(pointsPerSecond, 1))
    }
}

struct TimelineSnapResult: Equatable, Sendable {
    var time: TimelineTime
    var target: TimelineSnapTarget?
}

struct TimelineEditCommand: Equatable, Sendable {
    var name: String
    var before: Timeline
    var after: Timeline

    func apply(to project: inout ProjectFile) {
        project.timeline = after
    }

    func undo(in project: inout ProjectFile) {
        project.timeline = before
    }
}

enum TimelineEngine {
    static func append(
        media: MediaReference,
        to timeline: Timeline,
        beatAnalysis: BeatAnalysis?,
        playhead: TimelineTime,
        snapConfiguration: TimelineSnapConfiguration,
        pointsPerSecond: Double
    ) -> (timeline: Timeline, snap: TimelineSnapResult) {
        var updated = timeline
        ensurePrimaryVideoTrack(in: &updated)
        let end = updated.videoTracks[0].clips.map(\.timelineEnd.seconds).max() ?? 0
        let snap = snappedTime(
            TimelineTime(seconds: end),
            in: updated,
            beatAnalysis: beatAnalysis,
            playhead: playhead,
            configuration: snapConfiguration,
            pointsPerSecond: pointsPerSecond
        )
        let clip = makeClip(media: media, at: snap.time)
        updated.videoTracks[0].clips.append(clip)
        updated.videoTracks[0].clips.sort { $0.timelineStart < $1.timelineStart }
        ensurePrimaryAudioTrack(in: &updated)
        updated.audioTracks[0].clips.append(makeAudioClip(for: clip))
        updated.audioTracks[0].clips.sort { $0.timelineStart < $1.timelineStart }
        return (updated, snap)
    }

    static func insert(
        media: MediaReference,
        at proposedTime: TimelineTime,
        in timeline: Timeline,
        beatAnalysis: BeatAnalysis?,
        playhead: TimelineTime,
        snapConfiguration: TimelineSnapConfiguration,
        pointsPerSecond: Double
    ) -> (timeline: Timeline, snap: TimelineSnapResult) {
        var updated = timeline
        ensurePrimaryVideoTrack(in: &updated)
        let snap = snappedTime(
            proposedTime,
            in: updated,
            beatAnalysis: beatAnalysis,
            playhead: playhead,
            configuration: snapConfiguration,
            pointsPerSecond: pointsPerSecond
        )
        if let containingClip = updated.videoTracks[0].clips.first(where: {
            $0.timelineStart < snap.time && snap.time < $0.timelineEnd
        }), let splitTimeline = split(clipID: containingClip.id, at: snap.time, in: updated) {
            updated = splitTimeline
        }
        let clip = makeClip(media: media, at: snap.time)
        for index in updated.videoTracks[0].clips.indices where updated.videoTracks[0].clips[index].timelineStart >= snap.time {
            updated.videoTracks[0].clips[index].timelineStart = TimelineTime(
                seconds: updated.videoTracks[0].clips[index].timelineStart.seconds + clip.timelineDuration.seconds
            )
        }
        updated.videoTracks[0].clips.append(clip)
        updated.videoTracks[0].clips.sort { $0.timelineStart < $1.timelineStart }
        ensurePrimaryAudioTrack(in: &updated)
        for index in updated.audioTracks[0].clips.indices where updated.audioTracks[0].clips[index].timelineStart >= snap.time {
            updated.audioTracks[0].clips[index].timelineStart = TimelineTime(
                seconds: updated.audioTracks[0].clips[index].timelineStart.seconds + clip.timelineDuration.seconds
            )
        }
        updated.audioTracks[0].clips.append(makeAudioClip(for: clip))
        updated.audioTracks[0].clips.sort { $0.timelineStart < $1.timelineStart }
        return (updated, snap)
    }

    static func insertAudio(
        media: MediaReference,
        at time: TimelineTime,
        intoAudioTrack trackID: UUID,
        in timeline: Timeline
    ) -> Timeline? {
        guard media.kind == .audio,
              let trackIndex = timeline.audioTracks.firstIndex(where: { $0.id == trackID })
        else {
            return nil
        }
        var updated = timeline
        updated.audioTracks[trackIndex].clips.append(AudioClip(
            id: UUID(),
            mediaID: media.id,
            sourceRange: MediaTimeRange(start: .zero, duration: media.duration),
            timelineStart: time,
            volume: 1
        ))
        updated.audioTracks[trackIndex].clips.sort { $0.timelineStart < $1.timelineStart }
        return updated
    }

    static func move(
        clipID: UUID,
        to proposedTime: TimelineTime,
        in timeline: Timeline,
        beatAnalysis: BeatAnalysis?,
        playhead: TimelineTime,
        snapConfiguration: TimelineSnapConfiguration,
        pointsPerSecond: Double
    ) -> (timeline: Timeline, snap: TimelineSnapResult)? {
        var updated = timeline
        guard let location = clipLocation(id: clipID, in: updated) else { return nil }
        let snap = snappedTime(
            proposedTime,
            in: updated,
            beatAnalysis: beatAnalysis,
            playhead: playhead,
            configuration: snapConfiguration,
            pointsPerSecond: pointsPerSecond
        )
        let clip = updated.videoTracks[location.trackIndex].clips[location.clipIndex]
        updated.videoTracks[location.trackIndex].clips[location.clipIndex].timelineStart = snap.time
        let movedClip = updated.videoTracks[location.trackIndex].clips[location.clipIndex]
        updated.videoTracks[location.trackIndex].clips.sort { $0.timelineStart < $1.timelineStart }
        replaceMatchingAudioClip(clip, with: movedClip, in: &updated)
        return (updated, snap)
    }

    static func trimStart(
        clipID: UUID,
        to timelineTime: TimelineTime,
        in timeline: Timeline
    ) -> Timeline? {
        var updated = timeline
        guard let location = clipLocation(id: clipID, in: updated) else { return nil }
        let clip = updated.videoTracks[location.trackIndex].clips[location.clipIndex]
        let clampedTime = min(max(timelineTime.seconds, clip.timelineStart.seconds), clip.timelineEnd.seconds - minimumClipDuration)
        guard clampedTime > clip.timelineStart.seconds else { return nil }
        let timelineDelta = clampedTime - clip.timelineStart.seconds
        let sourceDelta = timelineDelta * clip.playbackRate
        updated.videoTracks[location.trackIndex].clips[location.clipIndex].sourceRange.start = TimelineTime(
            seconds: clip.sourceRange.start.seconds + sourceDelta
        )
        updated.videoTracks[location.trackIndex].clips[location.clipIndex].sourceRange.duration = TimelineTime(
            seconds: clip.sourceRange.duration.seconds - sourceDelta
        )
        updated.videoTracks[location.trackIndex].clips[location.clipIndex].timelineStart = TimelineTime(seconds: clampedTime)
        replaceMatchingAudioClip(
            clip,
            with: updated.videoTracks[location.trackIndex].clips[location.clipIndex],
            in: &updated
        )
        return updated
    }

    static func trimEnd(
        clipID: UUID,
        to timelineTime: TimelineTime,
        in timeline: Timeline
    ) -> Timeline? {
        var updated = timeline
        guard let location = clipLocation(id: clipID, in: updated) else { return nil }
        let clip = updated.videoTracks[location.trackIndex].clips[location.clipIndex]
        let clampedTime = max(min(timelineTime.seconds, clip.timelineEnd.seconds), clip.timelineStart.seconds + minimumClipDuration)
        guard clampedTime < clip.timelineEnd.seconds else { return nil }
        let timelineDuration = clampedTime - clip.timelineStart.seconds
        updated.videoTracks[location.trackIndex].clips[location.clipIndex].sourceRange.duration = TimelineTime(
            seconds: timelineDuration * clip.playbackRate
        )
        replaceMatchingAudioClip(
            clip,
            with: updated.videoTracks[location.trackIndex].clips[location.clipIndex],
            in: &updated
        )
        return updated
    }

    static func split(
        clipID: UUID,
        at timelineTime: TimelineTime,
        in timeline: Timeline
    ) -> Timeline? {
        var updated = timeline
        guard let location = clipLocation(id: clipID, in: updated) else { return nil }
        let clip = updated.videoTracks[location.trackIndex].clips[location.clipIndex]
        guard timelineTime > clip.timelineStart, timelineTime < clip.timelineEnd else { return nil }
        let sourceOffset = (timelineTime.seconds - clip.timelineStart.seconds) * clip.playbackRate
        guard sourceOffset >= minimumClipDuration,
              clip.sourceRange.duration.seconds - sourceOffset >= minimumClipDuration
        else {
            return nil
        }

        var first = clip
        first.sourceRange.duration = TimelineTime(seconds: sourceOffset)
        let second = TimelineClip(
            id: UUID(),
            mediaID: clip.mediaID,
            sourceRange: MediaTimeRange(
                start: TimelineTime(seconds: clip.sourceRange.start.seconds + sourceOffset),
                duration: TimelineTime(seconds: clip.sourceRange.duration.seconds - sourceOffset)
            ),
            timelineStart: timelineTime,
            playbackRate: clip.playbackRate,
            transform: clip.transform,
            opacity: clip.opacity,
            volume: clip.volume,
            transitionIn: .hardCut,
            transitionOut: clip.transitionOut,
            appearance: clip.appearance
        )
        updated.videoTracks[location.trackIndex].clips[location.clipIndex] = first
        updated.videoTracks[location.trackIndex].clips.insert(second, at: location.clipIndex + 1)
        replaceMatchingAudioClip(clip, with: first, in: &updated)
        appendMatchingAudioClip(for: second, in: &updated)
        return updated
    }

    static func delete(
        clipID: UUID,
        ripple: Bool,
        in timeline: Timeline
    ) -> Timeline? {
        var updated = timeline
        guard let location = clipLocation(id: clipID, in: updated) else { return nil }
        let removed = updated.videoTracks[location.trackIndex].clips.remove(at: location.clipIndex)
        removeMatchingAudioClips(for: removed, in: &updated)
        guard ripple else { return updated }
        for index in updated.videoTracks[location.trackIndex].clips.indices
        where updated.videoTracks[location.trackIndex].clips[index].timelineStart >= removed.timelineEnd {
            updated.videoTracks[location.trackIndex].clips[index].timelineStart = TimelineTime(
                seconds: updated.videoTracks[location.trackIndex].clips[index].timelineStart.seconds - removed.timelineDuration.seconds
            )
        }
        for trackIndex in updated.audioTracks.indices {
            for index in updated.audioTracks[trackIndex].clips.indices
            where updated.audioTracks[trackIndex].clips[index].timelineStart >= removed.timelineEnd {
                updated.audioTracks[trackIndex].clips[index].timelineStart = TimelineTime(
                    seconds: updated.audioTracks[trackIndex].clips[index].timelineStart.seconds - removed.timelineDuration.seconds
                )
            }
        }
        return updated
    }

    static func applying(
        _ plan: AutoCutPlan,
        to timeline: Timeline
    ) -> Timeline {
        var updated = timeline
        let videoClips = plan.placements.map { placement in
            TimelineClip(
                id: UUID(),
                mediaID: placement.mediaID,
                sourceRange: placement.sourceRange,
                timelineStart: placement.timelineStart,
                playbackRate: 1,
                transform: .identity,
                opacity: 1,
                volume: 1,
                transitionIn: .hardCut,
                transitionOut: .hardCut
            )
        }
        updated.videoTracks = videoClips.isEmpty ? [] : [VideoTrack(clips: videoClips)]
        updated.audioTracks = videoClips.isEmpty ? [] : [
            AudioTrack(clips: videoClips.map(makeAudioClip(for:)))
        ]
        return updated
    }

    static func snappedTime(
        _ proposedTime: TimelineTime,
        in timeline: Timeline,
        beatAnalysis: BeatAnalysis?,
        playhead: TimelineTime,
        configuration: TimelineSnapConfiguration,
        pointsPerSecond: Double
    ) -> TimelineSnapResult {
        guard configuration.isEnabled else {
            return TimelineSnapResult(time: proposedTime, target: nil)
        }
        let tolerance = configuration.tolerance(pointsPerSecond: pointsPerSecond)
        let candidates: [(TimelineSnapTarget, [TimelineTime])] = [
            (.playhead, [playhead]),
            (.beat, configuration.snapToBeats ? (beatAnalysis?.beatTimes ?? []) : []),
            (.clipEdge, configuration.snapToClipEdges ? clipEdges(in: timeline) : []),
            (.marker, configuration.snapToMarkers ? timeline.markers.map(\.time) : [])
        ]
        for (target, times) in candidates {
            if let time = times.min(by: { abs($0.seconds - proposedTime.seconds) < abs($1.seconds - proposedTime.seconds) }),
               abs(time.seconds - proposedTime.seconds) <= tolerance {
                return TimelineSnapResult(time: time, target: target)
            }
        }
        return TimelineSnapResult(time: proposedTime, target: nil)
    }

    private static let minimumClipDuration = 1.0 / 30.0

    private static func makeClip(media: MediaReference, at time: TimelineTime) -> TimelineClip {
        TimelineClip(
            id: UUID(),
            mediaID: media.id,
            sourceRange: MediaTimeRange(start: .zero, duration: media.duration),
            timelineStart: time,
            playbackRate: 1,
            transform: .identity,
            opacity: 1,
            volume: 1,
            transitionIn: .hardCut,
            transitionOut: .hardCut
        )
    }

    private static func ensurePrimaryVideoTrack(in timeline: inout Timeline) {
        if timeline.videoTracks.isEmpty {
            timeline.videoTracks.append(VideoTrack())
        }
    }

    private static func ensurePrimaryAudioTrack(in timeline: inout Timeline) {
        if timeline.audioTracks.isEmpty {
            timeline.audioTracks.append(AudioTrack())
        }
    }

    private static func makeAudioClip(for videoClip: TimelineClip) -> AudioClip {
        AudioClip(
            id: UUID(),
            mediaID: videoClip.mediaID,
            sourceRange: videoClip.sourceRange,
            timelineStart: videoClip.timelineStart,
            volume: videoClip.volume
        )
    }

    private static func replaceMatchingAudioClip(
        _ oldVideoClip: TimelineClip,
        with newVideoClip: TimelineClip,
        in timeline: inout Timeline
    ) {
        for trackIndex in timeline.audioTracks.indices {
            if let index = timeline.audioTracks[trackIndex].clips.firstIndex(where: { audioClipMatches($0, videoClip: oldVideoClip) }) {
                let muted = timeline.audioTracks[trackIndex].clips[index].isMuted
                var replacement = makeAudioClip(for: newVideoClip)
                replacement.isMuted = muted
                timeline.audioTracks[trackIndex].clips[index] = replacement
                return
            }
        }
    }

    private static func appendMatchingAudioClip(for videoClip: TimelineClip, in timeline: inout Timeline) {
        ensurePrimaryAudioTrack(in: &timeline)
        timeline.audioTracks[0].clips.append(makeAudioClip(for: videoClip))
        timeline.audioTracks[0].clips.sort { $0.timelineStart < $1.timelineStart }
    }

    private static func removeMatchingAudioClips(for videoClip: TimelineClip, in timeline: inout Timeline) {
        for trackIndex in timeline.audioTracks.indices {
            timeline.audioTracks[trackIndex].clips.removeAll { audioClipMatches($0, videoClip: videoClip) }
        }
    }

    private static func audioClipMatches(_ audioClip: AudioClip, videoClip: TimelineClip) -> Bool {
        audioClip.mediaID == videoClip.mediaID
            && audioClip.sourceRange == videoClip.sourceRange
            && audioClip.timelineStart == videoClip.timelineStart
    }

    private static func clipLocation(id: UUID, in timeline: Timeline) -> (trackIndex: Int, clipIndex: Int)? {
        for trackIndex in timeline.videoTracks.indices {
            if let clipIndex = timeline.videoTracks[trackIndex].clips.firstIndex(where: { $0.id == id }) {
                return (trackIndex, clipIndex)
            }
        }
        return nil
    }

    private static func clipEdges(in timeline: Timeline) -> [TimelineTime] {
        timeline.videoTracks.flatMap { track in
            track.clips.flatMap { [$0.timelineStart, $0.timelineEnd] }
        }
    }
}
