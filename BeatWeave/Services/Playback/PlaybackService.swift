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
    var currentTimeSeconds = 0.0
    private var timeObserver: Any?

    init() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.currentTimeSeconds = max(0, time.seconds)
            }
        }
    }

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
                currentTimeSeconds = 0
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

    func seek(to seconds: Double) {
        let clampedSeconds = max(0, seconds)
        let target = CMTime(seconds: clampedSeconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTimeSeconds = clampedSeconds
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentMediaID = nil
        currentTimeSeconds = 0
        releaseSecurityScope()
    }

    private func releaseSecurityScope() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }
}
