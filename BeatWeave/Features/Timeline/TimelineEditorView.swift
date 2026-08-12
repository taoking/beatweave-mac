import AppKit
import SwiftUI

struct TimelineEditorView: View {
    @Binding var project: ProjectFile
    let selectedMedia: MediaReference?
    let beatAnalysis: BeatAnalysis?
    let playheadSeconds: Double
    @Bindable var model: TimelineEditorModel
    let onSeek: (Double) -> Void
    let onProjectMutation: () -> Void

    @State private var pointsPerSecond = 80.0
    @State private var horizontalScrollOffset = 0.0
    @State private var timelineViewportWidth = 900.0

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            ScrollView([.horizontal, .vertical]) {
                timelineCanvas
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .frame(height: min(310, max(150, timelineHeight + 24)))
            .onScrollGeometryChange(for: Double.self, of: { geometry in
                geometry.contentOffset.x
            }, action: { _, offset in
                horizontalScrollOffset = offset
            })
            .onScrollGeometryChange(for: Double.self, of: { geometry in
                geometry.containerSize.width
            }, action: { _, width in
                timelineViewportWidth = width
            })
        }
        .background(.background)
    }

    private var controls: some View {
        VStack(spacing: 6) {
            HStack {
                Text("多轨时间线")
                    .font(.headline)
                if let selectedMedia, selectedMedia.kind == .video {
                    Button("将所选视频插入播放头") {
                        mutate {
                            model.insert(
                                media: selectedMedia,
                                at: playheadTime,
                                into: &project,
                                beatAnalysis: beatAnalysis,
                                playhead: playheadTime,
                                pointsPerSecond: pointsPerSecond
                            )
                        }
                    }
                }
                if let selectedMedia, selectedMedia.kind == .audio {
                    Button("将所选音频添加到 A1") {
                        mutate { model.appendAudio(media: selectedMedia, at: playheadTime, in: &project) }
                    }
                }
                Spacer()
                Button("撤销") {
                    mutate { model.undo(in: &project) }
                }
                .disabled(!model.canUndo)
                .keyboardShortcut(shortcutKey(project.editorKeyboardShortcuts?.validated().undoKey ?? "z"), modifiers: .command)
                Button("重做") {
                    mutate { model.redo(in: &project) }
                }
                .disabled(!model.canRedo)
                .keyboardShortcut(shortcutKey(project.editorKeyboardShortcuts?.validated().redoKey ?? "y"), modifiers: .command)
                Slider(value: $pointsPerSecond, in: 30...360) {
                    Text("时间线缩放")
                }
                .frame(width: 130)
            }
            HStack(spacing: 10) {
                Toggle("吸附", isOn: $model.snapConfiguration.isEnabled)
                Toggle("节拍", isOn: $model.snapConfiguration.snapToBeats)
                    .disabled(!model.snapConfiguration.isEnabled)
                Toggle("剪辑边缘", isOn: $model.snapConfiguration.snapToClipEdges)
                    .disabled(!model.snapConfiguration.isEnabled)
                Toggle("标记", isOn: $model.snapConfiguration.snapToMarkers)
                    .disabled(!model.snapConfiguration.isEnabled)
                if let target = model.lastSnapTarget {
                    Text("已吸附到\(snapName(target))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("+ 视频轨") {
                    mutate { model.addVideoTrack(in: &project) }
                }
                Button("+ 音频轨") {
                    mutate { model.addAudioTrack(in: &project) }
                }
                clipActions
            }
            .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var clipActions: some View {
        if let selectedClipID = model.selectedClipID {
            Button("移至播放头") {
                mutate {
                    model.move(
                        clipID: selectedClipID,
                        to: playheadTime,
                        in: &project,
                        beatAnalysis: beatAnalysis,
                        playhead: playheadTime,
                        pointsPerSecond: pointsPerSecond
                    )
                }
            }
            Button("修剪起点") {
                mutate { model.trimStart(clipID: selectedClipID, to: playheadTime, in: &project) }
            }
            Button("修剪终点") {
                mutate { model.trimEnd(clipID: selectedClipID, to: playheadTime, in: &project) }
            }
            Button("分割") {
                mutate { model.split(clipID: selectedClipID, at: playheadTime, in: &project) }
            }
            .keyboardShortcut(shortcutKey(project.editorKeyboardShortcuts?.validated().splitKey ?? "s"), modifiers: [])
            if project.timeline.videoTracks.count > 1 {
                Menu("移至视频轨") {
                    ForEach(Array(project.timeline.videoTracks.enumerated()), id: \.element.id) { index, track in
                        Button("V\(index + 1)") {
                            mutate { model.moveSelectedClips(toVideoTrack: track.id, in: &project) }
                        }
                    }
                }
            }
            Button("删除", role: .destructive) {
                mutate { model.delete(clipID: selectedClipID, ripple: false, in: &project) }
            }
            Button("波纹删除", role: .destructive) {
                mutate { model.delete(clipID: selectedClipID, ripple: true, in: &project) }
            }
            if model.selectedClipIDs.count > 1 {
                Button("删除所选 \(model.selectedClipIDs.count)", role: .destructive) {
                    mutate { model.deleteSelected(in: &project) }
                }
            }
        }
    }

    private var timelineCanvas: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(width: contentWidth, height: timelineHeight)
            ruler
            beatMarkers
            trackLabels
            clipEdges
            audioClipEdges
            playheadMarker
            clips
            audioClips
        }
        .frame(width: contentWidth, height: timelineHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { value in
                onSeek(max(0, value.location.x / pointsPerSecond))
            }
        )
        .dropDestination(for: String.self) { items, location in
            handleDrop(items, at: location)
        }
        .accessibilityLabel("视频时间线")
    }

    @ViewBuilder
    private var ruler: some View {
        let endSecond = Int(ceil(contentWidth / pointsPerSecond))
        ForEach(0...endSecond, id: \.self) { second in
            VStack(alignment: .leading, spacing: 0) {
                Text("\(second)s")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(.secondary.opacity(0.25))
                    .frame(width: 1, height: timelineHeight - 14)
            }
            .offset(x: Double(second) * pointsPerSecond, y: 2)
        }
    }

    @ViewBuilder
    private var beatMarkers: some View {
        if let beatAnalysis {
            let strongBeats = Set(beatAnalysis.strongBeatTimes)
            ForEach(beatAnalysis.beatTimes, id: \.self) { beat in
                Rectangle()
                    .fill(strongBeats.contains(beat) ? .purple.opacity(0.6) : .blue.opacity(0.35))
                    .frame(width: strongBeats.contains(beat) ? 2 : 1, height: timelineHeight - 30)
                    .offset(x: beat.seconds * pointsPerSecond, y: 28)
            }
        }
    }

    private var clipEdges: some View {
        ForEach(visibleTrackClips, id: \.clip.id) { item in
            Rectangle()
                .fill(.secondary.opacity(0.45))
                .frame(width: 1, height: 52)
                .offset(x: item.clip.timelineEnd.seconds * pointsPerSecond, y: trackOffset(for: item.trackIndex))
        }
    }

    private var audioClipEdges: some View {
        ForEach(visibleAudioTrackClips, id: \.clip.id) { item in
            Rectangle()
                .fill(.secondary.opacity(0.35))
                .frame(width: 1, height: 52)
                .offset(x: item.clip.timelineEnd.seconds * pointsPerSecond, y: audioTrackOffset(for: item.trackIndex))
        }
    }

    private var playheadMarker: some View {
        Rectangle()
            .fill(.red)
            .frame(width: 2, height: timelineHeight - 6)
            .offset(x: playheadSeconds * pointsPerSecond, y: 4)
            .accessibilityLabel("当前播放头")
    }

    private var clips: some View {
        ForEach(visibleTrackClips, id: \.clip.id) { item in
            TimelineClipTile(
                clip: item.clip,
                title: mediaName(for: item.clip.mediaID),
                pointsPerSecond: pointsPerSecond,
                isSelected: model.selectedClipIDs.contains(item.clip.id)
            ) { extendingSelection in
                model.selectClip(item.clip.id, extendingSelection: extendingSelection)
            }
            .offset(x: item.clip.timelineStart.seconds * pointsPerSecond, y: trackOffset(for: item.trackIndex))
        }
    }

    private var audioClips: some View {
        ForEach(visibleAudioTrackClips, id: \.clip.id) { item in
            AudioTimelineClipTile(
                clip: item.clip,
                title: mediaName(for: item.clip.mediaID),
                pointsPerSecond: pointsPerSecond
            )
            .offset(x: item.clip.timelineStart.seconds * pointsPerSecond, y: audioTrackOffset(for: item.trackIndex))
        }
    }

    @ViewBuilder
    private var trackLabels: some View {
        ForEach(Array(project.timeline.videoTracks.enumerated()), id: \.element.id) { index, _ in
            Text("V\(index + 1)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .offset(x: 4, y: trackOffset(for: index) + 17)
        }
        ForEach(Array(project.timeline.audioTracks.enumerated()), id: \.element.id) { index, _ in
            Text("A\(index + 1)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .offset(x: 4, y: audioTrackOffset(for: index) + 17)
        }
    }

    private var playheadTime: TimelineTime {
        TimelineTime(seconds: playheadSeconds)
    }

    private var contentWidth: Double {
        let videoClipEnd = project.timeline.videoTracks
            .flatMap(\.clips)
            .map(\.timelineEnd.seconds)
            .max() ?? 0
        let audioClipEnd = project.timeline.audioTracks
            .flatMap(\.clips)
            .map(\.timelineEnd.seconds)
            .max() ?? 0
        let beatEnd = beatAnalysis?.beatTimes.last?.seconds ?? 0
        return max(640, (max(videoClipEnd, audioClipEnd, beatEnd, playheadSeconds) + 4) * pointsPerSecond)
    }

    private var timelineHeight: Double {
        let tracks = videoLaneCount + project.timeline.audioTracks.count
        return 40 + Double(tracks) * 60 + 10
    }

    private var videoLaneCount: Int {
        max(1, project.timeline.videoTracks.count)
    }

    private var trackClips: [(trackIndex: Int, clip: TimelineClip)] {
        project.timeline.videoTracks.enumerated().flatMap { trackIndex, track in
            track.clips.map { (trackIndex, $0) }
        }
    }

    /// A buffered viewport avoids constructing hundreds of clip buttons for a long
    /// project while keeping neighboring clips ready during normal scrolling.
    private var visibleTrackClips: [(trackIndex: Int, clip: TimelineClip)] {
        let start = max(0, horizontalScrollOffset / pointsPerSecond - 1)
        let end = (horizontalScrollOffset + timelineViewportWidth) / pointsPerSecond + 1
        return trackClips.filter { $0.clip.timelineEnd.seconds >= start && $0.clip.timelineStart.seconds <= end }
    }

    private var audioTrackClips: [(trackIndex: Int, clip: AudioClip)] {
        project.timeline.audioTracks.enumerated().flatMap { trackIndex, track in
            track.clips.map { (trackIndex, $0) }
        }
    }

    private var visibleAudioTrackClips: [(trackIndex: Int, clip: AudioClip)] {
        let start = max(0, horizontalScrollOffset / pointsPerSecond - 1)
        let end = (horizontalScrollOffset + timelineViewportWidth) / pointsPerSecond + 1
        return audioTrackClips.filter { $0.clip.timelineEnd.seconds >= start && $0.clip.timelineStart.seconds <= end }
    }

    private func trackOffset(for trackIndex: Int) -> Double {
        40 + Double(trackIndex) * 60
    }

    private func audioTrackOffset(for trackIndex: Int) -> Double {
        trackOffset(for: videoLaneCount + trackIndex)
    }

    private func shortcutKey(_ rawValue: String) -> KeyEquivalent {
        KeyEquivalent(rawValue.first ?? "z")
    }

    private func mediaName(for mediaID: UUID) -> String {
        project.mediaLibrary.items.first(where: { $0.id == mediaID })?.displayName ?? "缺失媒体"
    }

    private func snapName(_ target: TimelineSnapTarget) -> String {
        switch target {
        case .playhead: "播放头"
        case .beat: "节拍"
        case .clipEdge: "剪辑边缘"
        case .marker: "标记"
        }
    }

    private func mutate(_ operation: () -> Bool) {
        if operation() {
            onProjectMutation()
        }
    }

    private func handleDrop(_ items: [String], at location: CGPoint) -> Bool {
        guard let item = items.first else { return false }
        let time = TimelineTime(seconds: max(0, location.x / pointsPerSecond))
        if item.hasPrefix("media:"),
           let id = UUID(uuidString: String(item.dropFirst("media:".count))),
           let media = project.mediaLibrary.items.first(where: { $0.id == id }),
           media.kind == .video {
            mutate {
                model.insert(
                    media: media,
                    at: time,
                    into: &project,
                    beatAnalysis: beatAnalysis,
                    playhead: playheadTime,
                    pointsPerSecond: pointsPerSecond
                )
            }
            return true
        }
        if item.hasPrefix("media:"),
           let id = UUID(uuidString: String(item.dropFirst("media:".count))),
           let media = project.mediaLibrary.items.first(where: { $0.id == id }),
           media.kind == .audio {
            mutate {
                if let audioTrackIndex = audioTrackIndex(at: location.y) {
                    return model.insertAudio(
                        media: media,
                        at: time,
                        intoAudioTrack: project.timeline.audioTracks[audioTrackIndex].id,
                        in: &project
                    )
                }
                return model.appendAudio(media: media, at: time, in: &project)
            }
            return true
        }
        if item.hasPrefix("clip:"),
           let id = UUID(uuidString: String(item.dropFirst("clip:".count))) {
            mutate {
                model.move(
                    clipID: id,
                    to: time,
                    in: &project,
                    beatAnalysis: beatAnalysis,
                    playhead: playheadTime,
                    pointsPerSecond: pointsPerSecond
                )
            }
            return true
        }
        return false
    }

    private func audioTrackIndex(at verticalPosition: Double) -> Int? {
        let lane = Int((verticalPosition - 40) / 60)
        let audioIndex = lane - videoLaneCount
        guard project.timeline.audioTracks.indices.contains(audioIndex) else { return nil }
        return audioIndex
    }
}

private struct TimelineClipTile: View {
    let clip: TimelineClip
    let title: String
    let pointsPerSecond: Double
    let isSelected: Bool
    let onSelect: (Bool) -> Void

    var body: some View {
        Button {
            onSelect(NSApp.currentEvent?.modifierFlags.contains(.command) == true)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .lineLimit(1)
                Text("\(clip.sourceRange.duration.seconds, format: .number.precision(.fractionLength(2))) 秒")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
            .frame(width: max(54, clip.timelineDuration.seconds * pointsPerSecond), height: 52, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.45) : Color.teal.opacity(0.35), in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .draggable("clip:\(clip.id.uuidString)")
        .accessibilityLabel("时间线剪辑 \(title)")
    }
}

private struct AudioTimelineClipTile: View {
    let clip: AudioClip
    let title: String
    let pointsPerSecond: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .lineLimit(1)
            Text("音频 \(clip.sourceRange.duration.seconds, format: .number.precision(.fractionLength(2))) 秒")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .frame(width: max(54, clip.timelineDuration.seconds * pointsPerSecond), height: 52, alignment: .leading)
        .background(Color.purple.opacity(0.28), in: RoundedRectangle(cornerRadius: 5))
        .accessibilityLabel("音频时间线剪辑 \(title)")
    }
}
