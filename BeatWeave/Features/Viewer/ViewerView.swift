import AVKit
import SwiftUI

struct ViewerView: View {
    let selectedMedia: MediaReference?
    @Bindable var playback: PlaybackService

    var body: some View {
        VStack(spacing: 0) {
            PlayerContainer(player: playback.player)
                .background(.black)
                .overlay {
                    if selectedMedia == nil {
                        ContentUnavailableView(
                            "选择一个媒体以预览",
                            systemImage: "play.rectangle",
                            description: Text("从左侧导入视频或音频文件。")
                        )
                        .foregroundStyle(.white.opacity(0.9))
                    }
                }
            Divider()
            HStack {
                Text(selectedMedia?.displayName ?? "未选择媒体")
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
                .disabled(selectedMedia == nil)
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
