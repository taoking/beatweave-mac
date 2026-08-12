import SwiftUI

struct WaveformTimelineView: View {
    let music: MediaReference?
    let cache: WaveformCache?
    let playheadSeconds: Double
    let isGenerating: Bool
    let onGenerate: () -> Void

    @State private var pointsPerSecond = 80.0

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
                }
                Slider(value: $pointsPerSecond, in: 30...360) {
                    Text("时间线缩放")
                }
                .frame(width: 140)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            waveformContent
                .frame(height: 140)
        }
        .background(.bar)
    }

    @ViewBuilder
    private var waveformContent: some View {
        if isGenerating {
            ProgressView("正在解码 PCM 并生成波形…")
        } else if let cache, let music {
            ScrollView(.horizontal) {
                WaveformCanvas(
                    cache: cache,
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
                context.stroke(
                    Path(CGRect(x: x, y: centerY - height, width: max(1, sampleWidth), height: height * 2)),
                    with: .color(.accentColor),
                    lineWidth: 1
                )
            }
            let playheadX = CGFloat(playheadSeconds * pointsPerSecond)
            context.stroke(
                Path(CGRect(x: playheadX, y: 0, width: 1, height: size.height)),
                with: .color(.red),
                lineWidth: 1
            )
        }
    }
}
