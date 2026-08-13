import AVFoundation
import Observation

@MainActor
@Observable
final class PlaybackService {
    enum PreviewKind: Equatable {
        case media(UUID)
        case timeline
    }

    let player = AVPlayer()

    private let resolver = MediaSourceResolver()
    private let proxyCacheStore = ProxyCacheStore()
    private var scopedURLs: [URL] = []
    private var temporaryVideoURLs: [URL] = []
    private var previewGeneration = 0

    var currentMediaID: UUID?
    var errorMessage: String?
    var currentTimeSeconds = 0.0
    var isUsingProxy = false
    var previewKind: PreviewKind?
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

    func preview(_ media: MediaReference?, proxyData: Data? = nil) {
        guard let media else {
            stop()
            return
        }

        let generation = beginPreviewRequest()
        Task {
            var acquiredScope: URL?
            do {
                let url: URL
                if let proxyData, media.proxy != nil {
                    url = try await proxyCacheStore.materializedURL(for: media.id, data: proxyData)
                    isUsingProxy = true
                } else {
                    url = try await resolver.resolvedURL(for: media)
                    isUsingProxy = false
                }
                if url.startAccessingSecurityScopedResource() {
                    acquiredScope = url
                }
                guard generation == previewGeneration else {
                    acquiredScope?.stopAccessingSecurityScopedResource()
                    return
                }
                releasePreviewResources()
                if let acquiredScope {
                    scopedURLs = [acquiredScope]
                }
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                currentTimeSeconds = 0
                currentMediaID = media.id
                previewKind = .media(media.id)
                errorMessage = nil
            } catch {
                acquiredScope?.stopAccessingSecurityScopedResource()
                guard generation == previewGeneration else { return }
                player.replaceCurrentItem(with: nil)
                releasePreviewResources()
                currentMediaID = nil
                isUsingProxy = false
                previewKind = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Builds the same timeline composition used by export, so preview timing,
    /// transitions, layer order, audio mix, canvas and color changes agree with
    /// the rendered deliverable. Generated color intermediates are released when
    /// the user changes preview source or stops playback.
    func previewTimeline(_ project: ProjectFile) {
        let generation = beginPreviewRequest()
        Task {
            var acquiredScopes: [URL] = []
            var generatedVideos: [URL] = []
            do {
                let plan = try ExportTimelinePlanner.makePlan(for: project)
                acquiredScopes = try await acquireSecurityScopes(for: plan)
                let built = try await CompositionBuilder(resolver: resolver).build(
                    plan: plan,
                    settings: project.exportSettings
                )
                generatedVideos = built.temporaryVideoURLs
                guard generation == previewGeneration else {
                    release(scopes: acquiredScopes, temporaryVideos: generatedVideos)
                    return
                }
                releasePreviewResources()
                scopedURLs = acquiredScopes
                temporaryVideoURLs = generatedVideos
                let item = AVPlayerItem(asset: built.composition)
                item.videoComposition = built.videoComposition
                item.audioMix = built.audioMix
                player.replaceCurrentItem(with: item)
                currentTimeSeconds = 0
                currentMediaID = nil
                isUsingProxy = false
                previewKind = .timeline
                errorMessage = nil
            } catch {
                release(scopes: acquiredScopes, temporaryVideos: generatedVideos)
                guard generation == previewGeneration else { return }
                player.replaceCurrentItem(with: nil)
                releasePreviewResources()
                currentMediaID = nil
                isUsingProxy = false
                previewKind = nil
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
        previewGeneration &+= 1
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentMediaID = nil
        currentTimeSeconds = 0
        isUsingProxy = false
        previewKind = nil
        releasePreviewResources()
    }

    private func beginPreviewRequest() -> Int {
        previewGeneration &+= 1
        player.pause()
        return previewGeneration
    }

    private func acquireSecurityScopes(for plan: ExportTimelinePlan) async throws -> [URL] {
        let media = plan.videoSegments.map(\.media)
            + plan.audioSegments.map(\.media)
            + (plan.musicSegment.map { [$0.media] } ?? [])
        var scopes: [URL] = []
        do {
            for mediaReference in Dictionary(uniqueKeysWithValues: media.map { ($0.id, $0) }).values {
                let url = try await resolver.resolvedURL(for: mediaReference)
                if url.startAccessingSecurityScopedResource() {
                    scopes.append(url)
                }
            }
            return scopes
        } catch {
            scopes.forEach { $0.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    private func releasePreviewResources() {
        release(scopes: scopedURLs, temporaryVideos: temporaryVideoURLs)
        scopedURLs = []
        temporaryVideoURLs = []
    }

    private func release(scopes: [URL], temporaryVideos: [URL]) {
        scopes.forEach { $0.stopAccessingSecurityScopedResource() }
        for url in temporaryVideos {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
