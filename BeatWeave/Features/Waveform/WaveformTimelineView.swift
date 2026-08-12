import SwiftUI

struct WaveformTimelineView: View {
    let music: MediaReference?
    let cache: WaveformCache?
    let beatAnalysis: BeatAnalysis?
    let playheadSeconds: Double
    let isGenerating: Bool
    let isAnalyzing: Bool
    let onGenerate: () -> Void
    let onAnalyze: () -> Void
    let onApplyManualBPM: (Double) -> Void
    let onTapTempo: () -> Double?

    @State private var pointsPerSecond = 80.0
    @State private var manualBPM = 120.0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("M1 音乐波形")
                    .font(.headline)
                if let music {
                    Text(music.displayName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if music != nil {
                    Button(cache == nil ? "生成波形" : "重新生成") {
                        onGenerate()
                    }
                    .disabled(isGenerating)
                    Button(beatAnalysis == nil ? "分析节拍" : "重新分析") {
                        onAnalyze()
                    }
                    .disabled(isAnalyzing)
                }
                Slider(value: $pointsPerSecond, in: 30...360) {
                    Text("时间线缩放")
                }
                .frame(width: 140)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            if music != nil {
                beatControls
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            Divider()
            waveformContent
                .frame(height: 140)
        }
        .background(.bar)
        .onAppear {
            if let beatAnalysis {
                manualBPM = beatAnalysis.bpm
            }
        }
        .onChange(of: beatAnalysis?.bpm) { _, bpm in
            if let bpm {
                manualBPM = bpm
            }
        }
    }

    private var beatControls: some View {
        HStack(spacing: 8) {
            if isAnalyzing {
                ProgressView("正在分析节拍…")
                    .controlSize(.small)
            } else if let beatAnalysis {
                Text("BPM \(beatAnalysis.bpm, format: .number.precision(.fractionLength(1)))")
                    .font(.subheadline.weight(.semibold))
                Text("置信度 \(beatAnalysis.confidence, format: .percent.precision(.fractionLength(0)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !beatAnalysis.alternateBPMs.isEmpty {
                    Text("候选 \(beatAnalysis.alternateBPMs.map { String(format: "%.1f", $0) }.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("尚未分析节拍")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            TextField("BPM", value: $manualBPM, format: .number.precision(.fractionLength(1)))
                .frame(width: 68)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onApplyManualBPM(manualBPM) }
            Button("应用") {
                onApplyManualBPM(manualBPM)
            }
            .disabled(!(30...400).contains(manualBPM))
            Button("×0.5") {
                manualBPM *= 0.5
                onApplyManualBPM(manualBPM)
            }
            .disabled(!(60...400).contains(manualBPM))
            Button("×2") {
                manualBPM *= 2
                onApplyManualBPM(manualBPM)
            }
            .disabled(!(30...200).contains(manualBPM))
            Button("Tap") {
                if let bpm = onTapTempo() {
                    manualBPM = bpm
                }
            }
            .help("按节拍连续点击，取最近点击间隔的中位数。")
        }
    }

    @ViewBuilder
    private var waveformContent: some View {
        if isGenerating {
            ProgressView("正在解码 PCM 并生成波形…")
        } else if let cache, let music {
            ScrollView(.horizontal) {
                WaveformCanvas(
                    cache: cache,
                    beatAnalysis: beatAnalysis,
                    playheadSeconds: playheadSeconds,
                    pointsPerSecond: pointsPerSecond
                )
                .frame(width: max(480, music.duration.seconds * pointsPerSecond), height: 138)
            }
        } else if music != nil {
            ContentUnavailableView("尚未生成波形", systemImage: "waveform", description: Text("波形缓存可随时删除并重新生成。"))
        } else {
            ContentUnavailableView("选择音乐轨道", systemImage: "music.note", description: Text("在媒体列表中将一个音频设为音乐。"))
        }
    }
}

private struct WaveformCanvas: View {
    let cache: WaveformCache
    let beatAnalysis: BeatAnalysis?
    let playheadSeconds: Double
    let pointsPerSecond: Double

    var body: some View {
        Canvas { context, size in
            guard let level = cache.level(forDisplayWidth: Int(size.width)) else { return }
            let centerY = size.height / 2
            let sampleWidth = size.width / CGFloat(level.samples.count)
            for (index, sample) in level.samples.enumerated() {
                let height = CGFloat(min(1, max(0, sample.peak))) * centerY
                let x = (CGFloat(index) + 0.5) * sampleWidth
                var waveformBar = Path()
                waveformBar.move(to: CGPoint(x: x, y: centerY - height))
                waveformBar.addLine(to: CGPoint(x: x, y: centerY + height))
                context.stroke(
                    waveformBar,
                    with: .color(.accentColor),
                    lineWidth: max(1, sampleWidth)
                )
            }
            if let beatAnalysis {
                let strongBeats = Set(beatAnalysis.strongBeatTimes)
                for beat in beatAnalysis.beatTimes {
                    let x = CGFloat(beat.seconds * pointsPerSecond)
                    var marker = Path()
                    marker.move(to: CGPoint(x: x, y: 0))
                    marker.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(
                        marker,
                        with: .color(strongBeats.contains(beat) ? .purple : .blue.opacity(0.55)),
                        lineWidth: strongBeats.contains(beat) ? 2 : 1
                    )
                }
                for onset in beatAnalysis.onsets {
                    let x = CGFloat(onset.time.seconds * pointsPerSecond)
                    var onsetMarker = Path()
                    onsetMarker.move(to: CGPoint(x: x, y: centerY - 8))
                    onsetMarker.addLine(to: CGPoint(x: x, y: centerY + 8))
                    context.stroke(onsetMarker, with: .color(.orange.opacity(0.7)), lineWidth: 1)
                }
            }
            let playheadX = CGFloat(playheadSeconds * pointsPerSecond)
            var playhead = Path()
            playhead.move(to: CGPoint(x: playheadX, y: 0))
            playhead.addLine(to: CGPoint(x: playheadX, y: size.height))
            context.stroke(
                playhead,
                with: .color(.red),
                lineWidth: 1
            )
        }
    }
}
