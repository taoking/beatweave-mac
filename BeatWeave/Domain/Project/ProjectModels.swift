import Foundation

struct ProjectFile: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    var projectFormatVersion: Int
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var canvas: CanvasSettings
    var frameRate: FrameRate
    var mediaLibrary: MediaLibrary
    var timeline: Timeline
    var beatAnalysis: BeatAnalysis?
    var exportSettings: ExportSettings

    static func new(name: String = "未命名项目", now: Date = .now) -> ProjectFile {
        ProjectFile(
            projectFormatVersion: currentFormatVersion,
            id: UUID(),
            name: name,
            createdAt: now,
            modifiedAt: now,
            canvas: .hdLandscape,
            frameRate: .fps30,
            mediaLibrary: .init(items: []),
            timeline: .init(videoTracks: [], audioTracks: [], musicTrack: nil, markers: []),
            beatAnalysis: nil,
            exportSettings: .default
        )
    }

    mutating func markModified(at date: Date = .now) {
        modifiedAt = date
    }
}

struct CanvasSettings: Codable, Equatable, Sendable {
    var width: Int
    var height: Int

    static let hdLandscape = CanvasSettings(width: 1_920, height: 1_080)

    var displayName: String {
        "\(width) × \(height)"
    }
}

enum FrameRate: Int, Codable, CaseIterable, Sendable {
    case fps24 = 24
    case fps25 = 25
    case fps30 = 30
    case fps60 = 60

    var displayName: String {
        "\(rawValue) fps"
    }
}

struct MediaLibrary: Codable, Equatable, Sendable {
    var items: [MediaReference]
}

struct MediaReference: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var displayName: String
    var originalURL: URL
    var securityScopedBookmark: Data?
    var kind: MediaKind
    var duration: TimelineTime
    var videoMetadata: VideoMetadata?

    init(
        id: UUID = UUID(),
        displayName: String,
        originalURL: URL,
        securityScopedBookmark: Data? = nil,
        kind: MediaKind,
        duration: TimelineTime,
        videoMetadata: VideoMetadata? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.originalURL = originalURL
        self.securityScopedBookmark = securityScopedBookmark
        self.kind = kind
        self.duration = duration
        self.videoMetadata = videoMetadata
    }
}

enum MediaKind: String, Codable, Sendable {
    case video
    case audio
}

struct VideoMetadata: Codable, Equatable, Sendable {
    var width: Int
    var height: Int
    var nominalFrameRate: Double
}

struct Timeline: Codable, Equatable, Sendable {
    var videoTracks: [VideoTrack]
    var audioTracks: [AudioTrack]
    var musicTrack: MusicTrack?
    var markers: [ProjectMarker]
}

struct VideoTrack: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var clips: [TimelineClip]

    init(id: UUID = UUID(), clips: [TimelineClip] = []) {
        self.id = id
        self.clips = clips
    }
}

struct AudioTrack: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var clips: [AudioClip]

    init(id: UUID = UUID(), clips: [AudioClip] = []) {
        self.id = id
        self.clips = clips
    }
}

struct TimelineClip: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var mediaID: UUID
    var sourceRange: MediaTimeRange
    var timelineStart: TimelineTime
    var playbackRate: Double
    var transform: ClipTransform
    var opacity: Double
    var volume: Double
    var transitionIn: Transition
    var transitionOut: Transition
}

struct AudioClip: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var mediaID: UUID
    var sourceRange: MediaTimeRange
    var timelineStart: TimelineTime
    var volume: Double
}

struct MusicTrack: Codable, Equatable, Sendable {
    var mediaID: UUID
    var timelineStart: TimelineTime
    var volume: Double
    var fadeInDuration: TimelineTime
    var fadeOutDuration: TimelineTime
}

struct ClipTransform: Codable, Equatable, Sendable {
    var scale: Double
    var positionX: Double
    var positionY: Double
    var rotationDegrees: Double

    static let identity = ClipTransform(scale: 1, positionX: 0, positionY: 0, rotationDegrees: 0)
}

enum Transition: String, Codable, Sendable {
    case hardCut
    case crossDissolve
    case dipToBlack
}

struct ProjectMarker: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var time: TimelineTime
    var name: String
}

struct MediaTimeRange: Codable, Equatable, Sendable {
    var start: TimelineTime
    var duration: TimelineTime
}

struct TimelineTime: Codable, Equatable, Comparable, Hashable, Sendable {
    let value: Int64
    let timescale: Int32

    init(seconds: Double, timescale: Int32 = 600) {
        self.value = Int64((seconds * Double(timescale)).rounded())
        self.timescale = timescale
    }

    var seconds: Double {
        Double(value) / Double(timescale)
    }

    static let zero = TimelineTime(seconds: 0)

    static func < (lhs: TimelineTime, rhs: TimelineTime) -> Bool {
        lhs.seconds < rhs.seconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedValue = try container.decode(Int64.self, forKey: .value)
        let decodedTimescale = try container.decode(Int32.self, forKey: .timescale)
        guard decodedTimescale > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .timescale,
                in: container,
                debugDescription: "Timeline time timescale must be positive."
            )
        }
        value = decodedValue
        timescale = decodedTimescale
    }
}

struct BeatAnalysis: Codable, Equatable, Sendable {
    var bpm: Double
    var confidence: Double
    var beatTimes: [TimelineTime]
    var strongBeatTimes: [TimelineTime]
    var downbeatTimes: [TimelineTime]
    var analysisVersion: Int
}

struct ExportSettings: Codable, Equatable, Sendable {
    var codec: ExportCodec
    var width: Int
    var height: Int
    var frameRate: FrameRate
    var quality: ExportQuality

    static let `default` = ExportSettings(
        codec: .h264,
        width: 1_920,
        height: 1_080,
        frameRate: .fps30,
        quality: .high
    )
}

enum ExportCodec: String, Codable, Sendable {
    case h264
    case hevc
}

enum ExportQuality: String, Codable, Sendable {
    case medium
    case high
}
