import AVKit
import SwiftUI

struct ViewerView: View {
    let project: ProjectFile
    let selectedMedia: MediaReference?
    @Bindable var playback: PlaybackService

    var body: some View {
        VStack(spacing: 0) {
            PlayerContainer(player: playback.player)
                .background(.black)
                .overlay {
                    if playback.previewKind == nil {
                        ContentUnavailableView(
                            "选择预览来源",
                            systemImage: "play.rectangle",
                            description: Text("可预览左侧选中的媒体，或播放整个项目时间线。")
                        )
                        .foregroundStyle(.white.opacity(0.9))
                    }
                }
            Divider()
            HStack {
                Text(previewTitle)
                    .lineLimit(1)
                if playback.isUsingProxy {
                    Label("代理预览", systemImage: "bolt.horizontal.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    playback.togglePlayback()
                } label: {
                    Label("播放或暂停", systemImage: "playpause")
                }
                .disabled(playback.previewKind == nil)
                Menu {
                    Button("预览所选媒体") {
                        playback.preview(selectedMedia)
                    }
                    .disabled(selectedMedia == nil)
                    Button("播放项目时间线") {
                        playback.previewTimeline(project)
                    }
                    .disabled(project.timeline.videoTracks.allSatisfy { $0.clips.isEmpty })
                } label: {
                    Label("预览来源", systemImage: "rectangle.on.rectangle")
                }
            }
            .padding(10)
        }
        .alert(
            "无法预览媒体",
            isPresented: Binding(
                get: { playback.errorMessage != nil },
                set: { if !$0 { playback.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {
                playback.errorMessage = nil
            }
        } message: {
            Text(playback.errorMessage ?? "未知错误")
        }
    }

    private var previewTitle: String {
        switch playback.previewKind {
        case .timeline:
            "项目时间线"
        case .media, nil:
            selectedMedia?.displayName ?? "未选择媒体"
        }
    }
}

private struct PlayerContainer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}
