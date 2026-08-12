import AVFoundation
import Observation

@MainActor
@Observable
final class PlaybackService {
    let player = AVPlayer()

    private let resolver = MediaSourceResolver()
    private var scopedURL: URL?

    var currentMediaID: UUID?
    var errorMessage: String?

    func preview(_ media: MediaReference?) {
        guard let media else {
            stop()
            return
        }

        Task {
            do {
                let url = try await resolver.resolvedURL(for: media)
                releaseSecurityScope()
                if url.startAccessingSecurityScopedResource() {
                    scopedURL = url
                }
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                currentMediaID = media.id
                errorMessage = nil
            } catch {
                player.replaceCurrentItem(with: nil)
                currentMediaID = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func togglePlayback() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentMediaID = nil
        releaseSecurityScope()
    }

    private func releaseSecurityScope() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }
}
