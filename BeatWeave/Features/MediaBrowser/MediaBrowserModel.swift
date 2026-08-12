import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class MediaBrowserModel {
    private let importer = MediaImportService()
    private let resolver = MediaSourceResolver()

    let thumbnails = ThumbnailStore()
    var errorMessage: String?
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

    func loadThumbnail(for media: MediaReference) async {
        guard media.kind == .video,
              dataByMediaID[media.id] == nil,
              !loadingIDs.contains(media.id) else {
            return
        }
        loadingIDs.insert(media.id)
        defer {
            loadingIDs.remove(media.id)
        }

        do {
            if let thumbnail = try await service.makePNGThumbnail(for: media) {
                dataByMediaID[media.id] = thumbnail
            }
        } catch {
            failureMessages[media.id] = error.localizedDescription
        }
    }

    func removeThumbnail(for mediaID: UUID) {
        dataByMediaID[mediaID] = nil
        failureMessages[mediaID] = nil
    }
}
