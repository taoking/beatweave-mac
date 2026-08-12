import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class MediaBrowserModel {
    private let importer = MediaImportService()
    private let resolver = MediaSourceResolver()
    private let proxyService = ProxyService()
    private let proxyCacheStore = ProxyCacheStore()

    let thumbnails = ThumbnailStore()
    var errorMessage: String?
    var generatingProxyIDs = Set<UUID>()
    private(set) var sourceStatuses: [UUID: MediaSourceStatus] = [:]

    func importMedia(from urls: [URL]) async -> [MediaReference] {
        var imported: [MediaReference] = []
        var failures: [String] = []

        for url in urls {
            do {
                imported.append(try await importer.import(url: url).reference)
            } catch {
                failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            errorMessage = failures.joined(separator: "\n")
        }
        return imported
    }

    func refreshSourceStatuses(for media: [MediaReference]) async {
        var updatedStatuses: [UUID: MediaSourceStatus] = [:]
        for item in media {
            updatedStatuses[item.id] = await resolver.status(for: item)
        }
        sourceStatuses = updatedStatuses
    }

    func sourceStatus(for media: MediaReference) -> MediaSourceStatus? {
        sourceStatuses[media.id]
    }

    func revealInFinder(_ media: MediaReference) {
        NSWorkspace.shared.activateFileViewerSelecting([media.originalURL])
    }

    func generateProxy(for media: MediaReference) async -> GeneratedProxy? {
        guard media.kind == .video, !generatingProxyIDs.contains(media.id) else { return nil }
        generatingProxyIDs.insert(media.id)
        defer { generatingProxyIDs.remove(media.id) }
        do {
            return try await proxyService.generate(for: media)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func removeMaterializedProxy(for mediaID: UUID) async {
        try? await proxyCacheStore.removeMaterializedProxy(for: mediaID)
    }
}

@MainActor
@Observable
final class ThumbnailStore {
    private let service = ThumbnailService()

    private(set) var dataByMediaID: [UUID: Data] = [:]
    private(set) var failureMessages: [UUID: String] = [:]
    private var loadingIDs: Set<UUID> = []

    func thumbnailData(for media: MediaReference) -> Data? {
        dataByMediaID[media.id]
    }

    func loadThumbnail(for media: MediaReference, cachedData: Data? = nil) async -> Data? {
        if let cachedData {
            dataByMediaID[media.id] = cachedData
            return cachedData
        }
        guard media.kind == .video,
              !loadingIDs.contains(media.id) else {
            return dataByMediaID[media.id]
        }
        if let existing = dataByMediaID[media.id] { return existing }
        loadingIDs.insert(media.id)
        defer {
            loadingIDs.remove(media.id)
        }

        do {
            if let thumbnail = try await MediaGenerationQueue.shared.perform({ [service] in
                try await service.makePNGThumbnail(for: media)
            }) {
                dataByMediaID[media.id] = thumbnail
                return thumbnail
            }
        } catch {
            failureMessages[media.id] = error.localizedDescription
        }
        return nil
    }

    func removeThumbnail(for mediaID: UUID) {
        dataByMediaID[mediaID] = nil
        failureMessages[mediaID] = nil
    }
}
