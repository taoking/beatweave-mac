import Foundation

struct ExportVideoSegment: Equatable, Sendable {
    var clip: TimelineClip
    var media: MediaReference
}

struct ExportAudioSegment: Equatable, Sendable {
    var clip: AudioClip
    var media: MediaReference
}

struct ExportMusicSegment: Equatable, Sendable {
    var track: MusicTrack
    var media: MediaReference
}

struct ExportTimelinePlan: Equatable, Sendable {
    var videoSegments: [ExportVideoSegment]
    var audioSegments: [ExportAudioSegment]
    var musicSegment: ExportMusicSegment?
    var duration: TimelineTime
}

enum ExportTimelinePlanError: LocalizedError, Equatable {
    case noVideoClips
    case missingMedia(UUID)
    case nonVideoMediaOnVideoTrack(UUID)
    case overlappingVideoClips

    var errorDescription: String? {
        switch self {
        case .noVideoClips:
            "时间线没有可导出的视频剪辑。"
        case let .missingMedia(id):
            "时间线引用的媒体（\(id.uuidString)）不在项目媒体库中。"
        case let .nonVideoMediaOnVideoTrack(id):
            "媒体（\(id.uuidString)）不是视频，不能放在视频轨导出。"
        case .overlappingVideoClips:
            "当前 MVP 不支持同一视频轨上的重叠剪辑，请先调整剪辑位置。"
        }
    }
}

enum ExportTimelinePlanner {
    static func makePlan(for project: ProjectFile) throws -> ExportTimelinePlan {
        let mediaByID = Dictionary(uniqueKeysWithValues: project.mediaLibrary.items.map { ($0.id, $0) })
        let videoClips = project.timeline.videoTracks.flatMap(\.clips).sorted { $0.timelineStart < $1.timelineStart }
        guard !videoClips.isEmpty else {
            throw ExportTimelinePlanError.noVideoClips
        }
        let videoSegments = try videoClips.map { clip -> ExportVideoSegment in
            guard let media = mediaByID[clip.mediaID] else {
                throw ExportTimelinePlanError.missingMedia(clip.mediaID)
            }
            guard media.kind == .video else {
                throw ExportTimelinePlanError.nonVideoMediaOnVideoTrack(clip.mediaID)
            }
            return ExportVideoSegment(clip: clip, media: media)
        }
        guard !hasOverlaps(videoSegments.map(\.clip)) else {
            throw ExportTimelinePlanError.overlappingVideoClips
        }

        let audioSegments = try project.timeline.audioTracks.flatMap(\.clips).map { clip -> ExportAudioSegment in
            guard let media = mediaByID[clip.mediaID] else {
                throw ExportTimelinePlanError.missingMedia(clip.mediaID)
            }
            return ExportAudioSegment(clip: clip, media: media)
        }
        let musicSegment = try project.timeline.musicTrack.map { track -> ExportMusicSegment in
            guard let media = mediaByID[track.mediaID] else {
                throw ExportTimelinePlanError.missingMedia(track.mediaID)
            }
            return ExportMusicSegment(track: track, media: media)
        }
        let duration = TimelineTime(seconds: videoSegments.map { $0.clip.timelineEnd.seconds }.max() ?? 0)
        return ExportTimelinePlan(
            videoSegments: videoSegments,
            audioSegments: audioSegments,
            musicSegment: musicSegment,
            duration: duration
        )
    }

    private static func hasOverlaps(_ clips: [TimelineClip]) -> Bool {
        for (current, next) in zip(clips, clips.dropFirst()) where current.timelineEnd > next.timelineStart {
            return true
        }
        return false
    }
}

enum ExportResolutionPreset: String, CaseIterable, Identifiable, Sendable {
    case hdLandscape
    case fullHDLandscape
    case fullHDPortrait
    case ultraHDLandscape

    var id: String { rawValue }

    var dimensions: (width: Int, height: Int) {
        switch self {
        case .hdLandscape: (1_280, 720)
        case .fullHDLandscape: (1_920, 1_080)
        case .fullHDPortrait: (1_080, 1_920)
        case .ultraHDLandscape: (3_840, 2_160)
        }
    }

    var displayName: String {
        let dimensions = dimensions
        return "\(dimensions.width) × \(dimensions.height)"
    }

    static func closest(to settings: ExportSettings) -> ExportResolutionPreset {
        allCases.min { lhs, rhs in
            let lhsSize = lhs.dimensions
            let rhsSize = rhs.dimensions
            let lhsDifference = abs(lhsSize.width - settings.width) + abs(lhsSize.height - settings.height)
            let rhsDifference = abs(rhsSize.width - settings.width) + abs(rhsSize.height - settings.height)
            return lhsDifference < rhsDifference
        } ?? .fullHDLandscape
    }
}
