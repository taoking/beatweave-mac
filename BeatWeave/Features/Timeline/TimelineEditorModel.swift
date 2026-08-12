import Foundation
import Observation

@MainActor
@Observable
final class TimelineEditorModel {
    private var undoStack: [TimelineEditCommand] = []
    private var redoStack: [TimelineEditCommand] = []

    var selectedClipID: UUID?
    var snapConfiguration = TimelineSnapConfiguration()
    var lastSnapTarget: TimelineSnapTarget?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

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
        if changed, selectedClipID == clipID {
            selectedClipID = nil
        }
        return changed
    }

    @discardableResult
    func applyAutoCut(_ plan: AutoCutPlan, to project: inout ProjectFile) -> Bool {
        guard !plan.placements.isEmpty else { return false }
        let timeline = TimelineEngine.applying(plan, to: project.timeline)
        selectedClipID = nil
        return commit(name: "应用 AutoCut", timeline: timeline, to: &project)
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
        undoStack.append(command)
        redoStack.removeAll(keepingCapacity: true)
        return true
    }
}
