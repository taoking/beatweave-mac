import Foundation

struct ExportVideoSegment: Equatable, Sendable {
    var clip: TimelineClip
    var media: MediaReference
    /// Higher-index video tracks are rendered above lower-index tracks.
    var trackIndex: Int
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
    var masterVolume: Double
    var duration: TimelineTime
}

enum ExportTimelinePlanError: LocalizedError, Equatable {
    case noVideoClips
    case missingMedia(UUID)
    case nonVideoMediaOnVideoTrack(UUID)

    var errorDescription: String? {
        switch self {
        case .noVideoClips:
            "时间线没有可导出的视频剪辑。"
        case let .missingMedia(id):
            "时间线引用的媒体（\(id.uuidString)）不在项目媒体库中。"
        case let .nonVideoMediaOnVideoTrack(id):
            "媒体（\(id.uuidString)）不是视频，不能放在视频轨导出。"
        }
    }
}

enum ExportTimelinePlanner {
    static func makePlan(for project: ProjectFile) throws -> ExportTimelinePlan {
        let mediaByID = Dictionary(uniqueKeysWithValues: project.mediaLibrary.items.map { ($0.id, $0) })
        let tracksWithClips = project.timeline.videoTracks.enumerated().filter { !$0.element.clips.isEmpty }
        guard !tracksWithClips.isEmpty else {
            throw ExportTimelinePlanError.noVideoClips
        }
        var videoSegments: [ExportVideoSegment] = []
        for (trackIndex, track) in tracksWithClips {
            for clip in track.clips.sorted(by: { $0.timelineStart < $1.timelineStart }) {
                guard let media = mediaByID[clip.mediaID] else {
                    throw ExportTimelinePlanError.missingMedia(clip.mediaID)
                }
                guard media.kind == .video else {
                    throw ExportTimelinePlanError.nonVideoMediaOnVideoTrack(clip.mediaID)
                }
                videoSegments.append(ExportVideoSegment(clip: clip, media: media, trackIndex: trackIndex))
            }
        }
        videoSegments.sort {
            $0.clip.timelineStart == $1.clip.timelineStart
                ? $0.trackIndex < $1.trackIndex
                : $0.clip.timelineStart < $1.clip.timelineStart
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
            masterVolume: min(1, max(0, project.timeline.masterVolume ?? 1)),
            duration: duration
        )
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

/// Delivery presets change the complete export configuration; the resolution picker
/// remains available for intentional custom dimensions afterwards.
enum ExportDeliveryPreset: String, CaseIterable, Identifiable, Sendable {
    case web1080p
    case socialVertical
    case master4K

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .web1080p: "Web 1080p（H.264）"
        case .socialVertical: "社媒竖屏（H.264）"
        case .master4K: "4K 母版（HEVC）"
        }
    }

    var settings: ExportSettings {
        switch self {
        case .web1080p:
            ExportSettings(codec: .h264, width: 1_920, height: 1_080, frameRate: .fps30, quality: .high)
        case .socialVertical:
            ExportSettings(codec: .h264, width: 1_080, height: 1_920, frameRate: .fps30, quality: .high)
        case .master4K:
            ExportSettings(codec: .hevc, width: 3_840, height: 2_160, frameRate: .fps60, quality: .high)
        }
    }

    static func closest(to settings: ExportSettings) -> ExportDeliveryPreset {
        allCases.min { lhs, rhs in
            difference(lhs.settings, settings) < difference(rhs.settings, settings)
        } ?? .web1080p
    }

    private static func difference(_ lhs: ExportSettings, _ rhs: ExportSettings) -> Int {
        abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
            + abs(lhs.frameRate.rawValue - rhs.frameRate.rawValue) * 100
            + (lhs.codec == rhs.codec ? 0 : 2_000)
            + (lhs.quality == rhs.quality ? 0 : 200)
    }
}
