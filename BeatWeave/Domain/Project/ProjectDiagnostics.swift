import Foundation

/// A lightweight project-health report. It intentionally does not resolve
/// security-scoped URLs, so it is safe to refresh from the editor UI.
struct ProjectDiagnostics: Equatable, Sendable {
    var videoTrackCount: Int
    var audioTrackCount: Int
    var videoClipCount: Int
    var audioClipCount: Int
    var projectDuration: TimelineTime
    var proxyCount: Int
    var missingMediaCount: Int
    var estimatedTimelineBytes: Int

    static func make(for project: ProjectFile) -> ProjectDiagnostics {
        let videoClips = project.timeline.videoTracks.flatMap(\.clips)
        let audioClips = project.timeline.audioTracks.flatMap(\.clips)
        let maximumEnd = videoClips.map(\.timelineEnd.seconds).max() ?? 0
        let proxies = project.mediaLibrary.items.filter { $0.proxy != nil }.count
        let referencedMediaIDs = Set(videoClips.map(\.mediaID) + audioClips.map(\.mediaID) + [project.timeline.musicTrack?.mediaID].compactMap { $0 })
        let missing = project.mediaLibrary.items.filter {
            referencedMediaIDs.contains($0.id) && !FileManager.default.fileExists(atPath: $0.originalURL.path)
        }.count
        // This is a model-only estimate used to surface unusually dense edits without
        // walking media files or claiming a disk-usage measurement.
        let estimatedBytes = (videoClips.count * 384) + (audioClips.count * 160) + (project.timeline.markers.count * 96)
        return ProjectDiagnostics(
            videoTrackCount: project.timeline.videoTracks.count,
            audioTrackCount: project.timeline.audioTracks.count,
            videoClipCount: videoClips.count,
            audioClipCount: audioClips.count,
            projectDuration: TimelineTime(seconds: maximumEnd),
            proxyCount: proxies,
            missingMediaCount: missing,
            estimatedTimelineBytes: estimatedBytes
        )
    }
}
