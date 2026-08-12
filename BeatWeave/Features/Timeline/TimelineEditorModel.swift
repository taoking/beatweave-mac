import Foundation
import Observation

@MainActor
@Observable
final class TimelineEditorModel {
    private enum EditCommand {
        case timeline(TimelineEditCommand)
        case canvas(CanvasEditCommand)

        func apply(to project: inout ProjectFile) {
            switch self {
            case let .timeline(command): command.apply(to: &project)
            case let .canvas(command): command.apply(to: &project)
            }
        }

        func undo(in project: inout ProjectFile) {
            switch self {
            case let .timeline(command): command.undo(in: &project)
            case let .canvas(command): command.undo(in: &project)
            }
        }
    }

    private struct CanvasEditCommand {
        var name: String
        var before: CanvasSettings
        var after: CanvasSettings
        var beforeExportSettings: ExportSettings
        var afterExportSettings: ExportSettings

        func apply(to project: inout ProjectFile) {
            project.canvas = after
            project.exportSettings = afterExportSettings
        }

        func undo(in project: inout ProjectFile) {
            project.canvas = before
            project.exportSettings = beforeExportSettings
        }
    }

    private var undoStack: [EditCommand] = []
    private var redoStack: [EditCommand] = []

    var selectedClipID: UUID?
    /// The focused clip remains available to single-clip inspector controls, while this
    /// set lets the timeline perform batch operations without inventing a second
    /// selection model.
    var selectedClipIDs: Set<UUID> = []
    var snapConfiguration = TimelineSnapConfiguration()
    var lastSnapTarget: TimelineSnapTarget?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func selectClip(_ clipID: UUID, extendingSelection: Bool) {
        if extendingSelection {
            if selectedClipIDs.contains(clipID) {
                selectedClipIDs.remove(clipID)
                if selectedClipID == clipID {
                    selectedClipID = selectedClipIDs.first
                }
            } else {
                selectedClipIDs.insert(clipID)
                selectedClipID = clipID
            }
        } else {
            selectedClipIDs = [clipID]
            selectedClipID = clipID
        }
    }

    func clearSelection() {
        selectedClipID = nil
        selectedClipIDs.removeAll()
    }

    @discardableResult
    func append(
        media: MediaReference,
        to project: inout ProjectFile,
        beatAnalysis: BeatAnalysis?,
        playhead: TimelineTime,
        pointsPerSecond: Double
    ) -> Bool {
        let result = TimelineEngine.append(
            media: media,
            to: project.timeline,
            beatAnalysis: beatAnalysis,
            playhead: playhead,
            snapConfiguration: snapConfiguration,
            pointsPerSecond: pointsPerSecond
        )
        lastSnapTarget = result.snap.target
        return commit(name: "追加剪辑", timeline: result.timeline, to: &project)
    }

    @discardableResult
    func insert(
        media: MediaReference,
        at time: TimelineTime,
        into project: inout ProjectFile,
        beatAnalysis: BeatAnalysis?,
        playhead: TimelineTime,
        pointsPerSecond: Double
    ) -> Bool {
        let result = TimelineEngine.insert(
            media: media,
            at: time,
            in: project.timeline,
            beatAnalysis: beatAnalysis,
            playhead: playhead,
            snapConfiguration: snapConfiguration,
            pointsPerSecond: pointsPerSecond
        )
        lastSnapTarget = result.snap.target
        return commit(name: "插入剪辑", timeline: result.timeline, to: &project)
    }

    @discardableResult
    func insertAudio(
        media: MediaReference,
        at time: TimelineTime,
        intoAudioTrack trackID: UUID,
        in project: inout ProjectFile
    ) -> Bool {
        guard let updated = TimelineEngine.insertAudio(
            media: media,
            at: time,
            intoAudioTrack: trackID,
            in: project.timeline
        ) else {
            return false
        }
        return commit(name: "添加音频剪辑", timeline: updated, to: &project)
    }

    @discardableResult
    func appendAudio(media: MediaReference, at time: TimelineTime, in project: inout ProjectFile) -> Bool {
        var timeline = project.timeline
        if timeline.audioTracks.isEmpty {
            timeline.audioTracks.append(AudioTrack())
        }
        guard let updated = TimelineEngine.insertAudio(
            media: media,
            at: time,
            intoAudioTrack: timeline.audioTracks[0].id,
            in: timeline
        ) else {
            return false
        }
        return commit(name: "添加音频剪辑", timeline: updated, to: &project)
    }

    @discardableResult
    func move(
        clipID: UUID,
        to time: TimelineTime,
        in project: inout ProjectFile,
        beatAnalysis: BeatAnalysis?,
        playhead: TimelineTime,
        pointsPerSecond: Double
    ) -> Bool {
        guard let result = TimelineEngine.move(
            clipID: clipID,
            to: time,
            in: project.timeline,
            beatAnalysis: beatAnalysis,
            playhead: playhead,
            snapConfiguration: snapConfiguration,
            pointsPerSecond: pointsPerSecond
        ) else {
            return false
        }
        lastSnapTarget = result.snap.target
        return commit(name: "移动剪辑", timeline: result.timeline, to: &project)
    }

    @discardableResult
    func trimStart(
        clipID: UUID,
        to time: TimelineTime,
        in project: inout ProjectFile
    ) -> Bool {
        guard let timeline = TimelineEngine.trimStart(
            clipID: clipID,
            to: time,
            in: project.timeline
        ) else {
            return false
        }
        return commit(name: "修剪剪辑起点", timeline: timeline, to: &project)
    }

    @discardableResult
    func trimEnd(
        clipID: UUID,
        to time: TimelineTime,
        in project: inout ProjectFile
    ) -> Bool {
        guard let timeline = TimelineEngine.trimEnd(
            clipID: clipID,
            to: time,
            in: project.timeline
        ) else {
            return false
        }
        return commit(name: "修剪剪辑终点", timeline: timeline, to: &project)
    }

    @discardableResult
    func split(
        clipID: UUID,
        at time: TimelineTime,
        in project: inout ProjectFile
    ) -> Bool {
        guard let timeline = TimelineEngine.split(
            clipID: clipID,
            at: time,
            in: project.timeline
        ) else {
            return false
        }
        return commit(name: "分割剪辑", timeline: timeline, to: &project)
    }

    @discardableResult
    func delete(
        clipID: UUID,
        ripple: Bool,
        in project: inout ProjectFile
    ) -> Bool {
        guard let timeline = TimelineEngine.delete(
            clipID: clipID,
            ripple: ripple,
            in: project.timeline
        ) else {
            return false
        }
        let changed = commit(name: ripple ? "波纹删除剪辑" : "删除剪辑", timeline: timeline, to: &project)
        if changed {
            selectedClipIDs.remove(clipID)
            if selectedClipID == clipID {
                selectedClipID = selectedClipIDs.first
            }
        }
        return changed
    }

    @discardableResult
    func deleteSelected(in project: inout ProjectFile) -> Bool {
        guard !selectedClipIDs.isEmpty else { return false }
        var updated = project.timeline
        var removedAny = false
        for clipID in selectedClipIDs {
            guard let timeline = TimelineEngine.delete(clipID: clipID, ripple: false, in: updated) else {
                continue
            }
            updated = timeline
            removedAny = true
        }
        guard removedAny else { return false }
        clearSelection()
        return commit(name: "删除多个剪辑", timeline: updated, to: &project)
    }

    @discardableResult
    func addVideoTrack(in project: inout ProjectFile) -> Bool {
        var updated = project.timeline
        updated.videoTracks.append(VideoTrack())
        return commit(name: "添加视频轨", timeline: updated, to: &project)
    }

    @discardableResult
    func addAudioTrack(in project: inout ProjectFile) -> Bool {
        var updated = project.timeline
        updated.audioTracks.append(AudioTrack())
        return commit(name: "添加音频轨", timeline: updated, to: &project)
    }

    @discardableResult
    func moveSelectedClips(toVideoTrack trackID: UUID, in project: inout ProjectFile) -> Bool {
        guard !selectedClipIDs.isEmpty,
              let destinationIndex = project.timeline.videoTracks.firstIndex(where: { $0.id == trackID })
        else {
            return false
        }
        var updated = project.timeline
        var moving: [TimelineClip] = []
        for index in updated.videoTracks.indices.reversed() {
            let clips = updated.videoTracks[index].clips
            let selected = clips.filter { selectedClipIDs.contains($0.id) }
            guard !selected.isEmpty else { continue }
            moving.append(contentsOf: selected)
            updated.videoTracks[index].clips.removeAll { selectedClipIDs.contains($0.id) }
        }
        guard !moving.isEmpty else { return false }
        updated.videoTracks[destinationIndex].clips.append(contentsOf: moving)
        updated.videoTracks[destinationIndex].clips.sort { $0.timelineStart < $1.timelineStart }
        return commit(name: "移动多个剪辑到视频轨", timeline: updated, to: &project)
    }

    @discardableResult
    func applyAutoCut(_ plan: AutoCutPlan, to project: inout ProjectFile) -> Bool {
        guard !plan.placements.isEmpty else { return false }
        let timeline = TimelineEngine.applying(plan, to: project.timeline)
        clearSelection()
        return commit(name: "应用 AutoCut", timeline: timeline, to: &project)
    }

    @discardableResult
    func updateClip(
        id: UUID,
        name: String,
        in project: inout ProjectFile,
        _ mutation: (inout TimelineClip) -> Void
    ) -> Bool {
        var timeline = project.timeline
        for trackIndex in timeline.videoTracks.indices {
            guard let clipIndex = timeline.videoTracks[trackIndex].clips.firstIndex(where: { $0.id == id }) else {
                continue
            }
            mutation(&timeline.videoTracks[trackIndex].clips[clipIndex])
            return commit(name: name, timeline: timeline, to: &project)
        }
        return false
    }

    @discardableResult
    func updateAudio(
        forVideoClipID id: UUID,
        name: String,
        in project: inout ProjectFile,
        _ mutation: (inout AudioClip) -> Void
    ) -> Bool {
        guard let videoClip = project.timeline.videoTracks
            .flatMap(\.clips)
            .first(where: { $0.id == id })
        else {
            return false
        }
        var timeline = project.timeline
        for trackIndex in timeline.audioTracks.indices {
            if let clipIndex = timeline.audioTracks[trackIndex].clips.firstIndex(where: {
                $0.mediaID == videoClip.mediaID
                    && $0.sourceRange == videoClip.sourceRange
                    && $0.timelineStart == videoClip.timelineStart
            }) {
                mutation(&timeline.audioTracks[trackIndex].clips[clipIndex])
                return commit(name: name, timeline: timeline, to: &project)
            }
        }
        return false
    }

    @discardableResult
    func updateMusic(
        name: String,
        in project: inout ProjectFile,
        _ mutation: (inout MusicTrack) -> Void
    ) -> Bool {
        guard var music = project.timeline.musicTrack else { return false }
        mutation(&music)
        var timeline = project.timeline
        timeline.musicTrack = music
        return commit(name: name, timeline: timeline, to: &project)
    }

    @discardableResult
    func updateMasterVolume(_ volume: Double, in project: inout ProjectFile) -> Bool {
        var timeline = project.timeline
        timeline.masterVolume = min(1, max(0, volume))
        return commit(name: "调整主音量", timeline: timeline, to: &project)
    }

    @discardableResult
    func updateCanvas(_ canvas: CanvasSettings, in project: inout ProjectFile) -> Bool {
        guard canvas.width > 0, canvas.height > 0, canvas != project.canvas else { return false }
        var exportSettings = project.exportSettings
        exportSettings.width = canvas.width
        exportSettings.height = canvas.height
        let command = CanvasEditCommand(
            name: "更改画布",
            before: project.canvas,
            after: canvas,
            beforeExportSettings: project.exportSettings,
            afterExportSettings: exportSettings
        )
        command.apply(to: &project)
        undoStack.append(.canvas(command))
        redoStack.removeAll(keepingCapacity: true)
        return true
    }

    @discardableResult
    func undo(in project: inout ProjectFile) -> Bool {
        guard let command = undoStack.popLast() else { return false }
        command.undo(in: &project)
        redoStack.append(command)
        return true
    }

    @discardableResult
    func redo(in project: inout ProjectFile) -> Bool {
        guard let command = redoStack.popLast() else { return false }
        command.apply(to: &project)
        undoStack.append(command)
        return true
    }

    private func commit(name: String, timeline: Timeline, to project: inout ProjectFile) -> Bool {
        guard timeline != project.timeline else { return false }
        let command = TimelineEditCommand(name: name, before: project.timeline, after: timeline)
        command.apply(to: &project)
        undoStack.append(.timeline(command))
        redoStack.removeAll(keepingCapacity: true)
        return true
    }
}
