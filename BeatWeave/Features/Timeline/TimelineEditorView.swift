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

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            ScrollView(.horizontal) {
                timelineCanvas
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .frame(height: 150)
        }
        .background(.background)
    }

    private var controls: some View {
        VStack(spacing: 6) {
            HStack {
                Text("V1 时间线")
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
                Spacer()
                Button("撤销") {
                    mutate { model.undo(in: &project) }
                }
                .disabled(!model.canUndo)
                Button("重做") {
                    mutate { model.redo(in: &project) }
                }
                .disabled(!model.canRedo)
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
            Button("删除", role: .destructive) {
                mutate { model.delete(clipID: selectedClipID, ripple: false, in: &project) }
            }
            Button("波纹删除", role: .destructive) {
                mutate { model.delete(clipID: selectedClipID, ripple: true, in: &project) }
            }
        }
    }

    private var timelineCanvas: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(width: contentWidth, height: 126)
            ruler
            beatMarkers
            clipEdges
            playheadMarker
            clips
        }
        .frame(width: contentWidth, height: 126, alignment: .topLeading)
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
                    .frame(width: 1, height: 112)
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
                    .frame(width: strongBeats.contains(beat) ? 2 : 1, height: 96)
                    .offset(x: beat.seconds * pointsPerSecond, y: 28)
            }
        }
    }

    private var clipEdges: some View {
        ForEach(project.timeline.videoTracks.flatMap(\.clips)) { clip in
            Rectangle()
                .fill(.secondary.opacity(0.45))
                .frame(width: 1, height: 96)
                .offset(x: clip.timelineEnd.seconds * pointsPerSecond, y: 28)
        }
    }

    private var playheadMarker: some View {
        Rectangle()
            .fill(.red)
            .frame(width: 2, height: 120)
            .offset(x: playheadSeconds * pointsPerSecond, y: 4)
            .accessibilityLabel("当前播放头")
    }

    private var clips: some View {
        ForEach(project.timeline.videoTracks.flatMap(\.clips)) { clip in
            TimelineClipTile(
                clip: clip,
                title: mediaName(for: clip.mediaID),
                pointsPerSecond: pointsPerSecond,
                isSelected: model.selectedClipID == clip.id
            ) {
                model.selectedClipID = clip.id
            }
            .offset(x: clip.timelineStart.seconds * pointsPerSecond, y: 46)
        }
    }

    private var playheadTime: TimelineTime {
        TimelineTime(seconds: playheadSeconds)
    }

    private var contentWidth: Double {
        let clipEnd = project.timeline.videoTracks
            .flatMap(\.clips)
            .map(\.timelineEnd.seconds)
            .max() ?? 0
        let beatEnd = beatAnalysis?.beatTimes.last?.seconds ?? 0
        return max(640, (max(clipEnd, beatEnd, playheadSeconds) + 4) * pointsPerSecond)
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
}

private struct TimelineClipTile: View {
    let clip: TimelineClip
    let title: String
    let pointsPerSecond: Double
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
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
