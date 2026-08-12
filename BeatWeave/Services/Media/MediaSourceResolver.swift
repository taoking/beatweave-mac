import Foundation

enum MediaSourceStatus: Equatable, Sendable {
    case available
    case missing
}

enum MediaSourceResolverError: LocalizedError {
    case unavailable(MediaReference)

    var errorDescription: String? {
        switch self {
        case let .unavailable(media):
            "找不到媒体源“\(media.displayName)”。"
        }
    }
}

actor MediaSourceResolver {
    func status(for media: MediaReference) -> MediaSourceStatus {
        FileManager.default.fileExists(atPath: media.originalURL.path) ? .available : .missing
    }

    func resolvedURL(for media: MediaReference) throws -> URL {
        if FileManager.default.fileExists(atPath: media.originalURL.path) {
            return media.originalURL
        }

        guard let bookmark = media.securityScopedBookmark else {
            throw MediaSourceResolverError.unavailable(media)
        }

        var isStale = false
        let bookmarkedURL = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard FileManager.default.fileExists(atPath: bookmarkedURL.path) else {
            throw MediaSourceResolverError.unavailable(media)
        }
        return bookmarkedURL
    }
}
