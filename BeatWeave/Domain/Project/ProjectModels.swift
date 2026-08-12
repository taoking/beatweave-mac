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
    /// Optional smart-montage metadata keeps projects written before Phase 8 compatible.
    var smartMontage: SmartMontageSettings? = nil
    /// Optional editor preferences introduced after the MVP.
    var editorKeyboardShortcuts: EditorKeyboardShortcuts? = nil
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

struct SmartMontageSettings: Codable, Equatable, Sendable {
    static let currentAnalysisVersion = 1

    var analyses: [UUID: MediaQualityAnalysis]
    var decisions: [UUID: SmartMediaDecision]

    init(analyses: [UUID: MediaQualityAnalysis] = [:], decisions: [UUID: SmartMediaDecision] = [:]) {
        self.analyses = analyses
        self.decisions = decisions
    }
}

struct MediaQualityAnalysis: Codable, Equatable, Sendable {
    var overallScore: Double
    var visualQualityScore: Double
    var motionScore: Double
    var faceScore: Double
    var rangeScores: [MediaRangeScore]
    var analysisVersion: Int

    init(
        overallScore: Double,
        visualQualityScore: Double,
        motionScore: Double,
        faceScore: Double,
        rangeScores: [MediaRangeScore],
        analysisVersion: Int = SmartMontageSettings.currentAnalysisVersion
    ) {
        self.overallScore = overallScore
        self.visualQualityScore = visualQualityScore
        self.motionScore = motionScore
        self.faceScore = faceScore
        self.rangeScores = rangeScores
        self.analysisVersion = analysisVersion
    }
}

struct MediaRangeScore: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var sourceRange: MediaTimeRange
    var score: Double
}

enum SmartMediaDecision: String, Codable, CaseIterable, Identifiable, Sendable {
    case included
    case excluded
    case pinned

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .included: "参与"
        case .excluded: "排除"
        case .pinned: "固定优先"
        }
    }
}

struct CanvasSettings: Codable, Equatable, Sendable {
    var width: Int
    var height: Int
    /// Nil represents projects written before canvas presets were introduced.
    var preset: CanvasPreset? = nil

    static let hdLandscape = CanvasSettings(width: 1_920, height: 1_080, preset: .landscape16x9)

    var displayName: String {
        "\(width) × \(height)"
    }
}

enum CanvasPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case landscape16x9
    case portrait9x16
    case square1x1
    case portrait4x5
    case source
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .landscape16x9: "16:9 横向"
        case .portrait9x16: "9:16 竖向"
        case .square1x1: "1:1 方形"
        case .portrait4x5: "4:5 竖向"
        case .source: "源素材比例"
        case .custom: "自定义"
        }
    }

    func canvas(sourceSize: VideoMetadata? = nil) -> CanvasSettings? {
        switch self {
        case .landscape16x9:
            return CanvasSettings(width: 1_920, height: 1_080, preset: self)
        case .portrait9x16:
            return CanvasSettings(width: 1_080, height: 1_920, preset: self)
        case .square1x1:
            return CanvasSettings(width: 1_080, height: 1_080, preset: self)
        case .portrait4x5:
            return CanvasSettings(width: 1_080, height: 1_350, preset: self)
        case .source:
            guard let sourceSize, sourceSize.width > 0, sourceSize.height > 0 else { return nil }
            return CanvasSettings(width: sourceSize.width, height: sourceSize.height, preset: self)
        case .custom:
            return nil
        }
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
    /// Proxy data lives in the regenerable project cache; originals remain export sources.
    var proxy: ProxyMediaInfo? = nil

    init(
        id: UUID = UUID(),
        displayName: String,
        originalURL: URL,
        securityScopedBookmark: Data? = nil,
        kind: MediaKind,
        duration: TimelineTime,
        videoMetadata: VideoMetadata? = nil,
        proxy: ProxyMediaInfo? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.originalURL = originalURL
        self.securityScopedBookmark = securityScopedBookmark
        self.kind = kind
        self.duration = duration
        self.videoMetadata = videoMetadata
        self.proxy = proxy
    }
}

struct ProxyMediaInfo: Codable, Equatable, Sendable {
    var cacheFilename: String
    var width: Int
    var height: Int
    var codec: ExportCodec
}

struct EditorKeyboardShortcuts: Codable, Equatable, Sendable {
    var undoKey: String
    var redoKey: String
    var splitKey: String

    static let `default` = EditorKeyboardShortcuts(undoKey: "z", redoKey: "y", splitKey: "s")

    func validated() -> EditorKeyboardShortcuts {
        EditorKeyboardShortcuts(
            undoKey: Self.normalized(undoKey, fallback: "z"),
            redoKey: Self.normalized(redoKey, fallback: "y"),
            splitKey: Self.normalized(splitKey, fallback: "s")
        )
    }

    private static func normalized(_ key: String, fallback: String) -> String {
        guard let character = key.lowercased().first, character.isLetter || character.isNumber else {
            return fallback
        }
        return String(character)
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
    /// Applies to every audio source at export. Nil is the legacy value of 1.
    var masterVolume: Double? = nil
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
    /// Optional so documents created by the MVP keep decoding without migration.
    var appearance: ClipAppearance? = nil
}

struct AudioClip: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var mediaID: UUID
    var sourceRange: MediaTimeRange
    var timelineStart: TimelineTime
    var volume: Double
    /// Nil is compatible with older documents and means the clip is audible.
    var isMuted: Bool? = nil
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

struct ClipAppearance: Codable, Equatable, Sendable {
    var crop: ClipCrop
    var contentMode: ClipContentMode
    var color: ClipColorAdjustments
    var lut: LUTReference?

    static let `default` = ClipAppearance(
        crop: .fullFrame,
        contentMode: .fit,
        color: .neutral,
        lut: nil
    )
}

struct ClipCrop: Codable, Equatable, Sendable {
    /// Normalized source-space rectangle. Every value is constrained before export.
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let fullFrame = ClipCrop(x: 0, y: 0, width: 1, height: 1)

    func clamped() -> ClipCrop {
        let normalizedX = min(1, max(0, x))
        let normalizedY = min(1, max(0, y))
        return ClipCrop(
            x: normalizedX,
            y: normalizedY,
            width: min(1 - normalizedX, max(0.05, width)),
            height: min(1 - normalizedY, max(0.05, height))
        )
    }
}

enum ClipContentMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fit
    case fill

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fit: "适应"
        case .fill: "填充"
        }
    }
}

struct ClipColorAdjustments: Codable, Equatable, Sendable {
    var exposure: Double
    var contrast: Double
    var saturation: Double
    var temperature: Double
    var tint: Double
    var highlights: Double
    var shadows: Double

    static let neutral = ClipColorAdjustments(
        exposure: 0,
        contrast: 1,
        saturation: 1,
        temperature: 0,
        tint: 0,
        highlights: 0,
        shadows: 0
    )
}

struct LUTReference: Codable, Equatable, Sendable {
    var displayName: String
    var fileURL: URL
    var intensity: Double
    var securityScopedBookmark: Data? = nil
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
    static let currentAnalysisVersion = 1

    var mediaID: UUID?
    var bpm: Double
    var confidence: Double
    var alternateBPMs: [Double]
    var onsets: [Onset]
    var beatTimes: [TimelineTime]
    var strongBeatTimes: [TimelineTime]
    var downbeatTimes: [TimelineTime]
    var analysisVersion: Int
    var parameters: BeatAnalysisParameters?
    var diagnostics: BeatAnalysisDiagnostics?

    init(
        mediaID: UUID? = nil,
        bpm: Double,
        confidence: Double,
        alternateBPMs: [Double] = [],
        onsets: [Onset] = [],
        beatTimes: [TimelineTime],
        strongBeatTimes: [TimelineTime],
        downbeatTimes: [TimelineTime],
        analysisVersion: Int = currentAnalysisVersion,
        parameters: BeatAnalysisParameters? = nil,
        diagnostics: BeatAnalysisDiagnostics? = nil
    ) {
        self.mediaID = mediaID
        self.bpm = bpm
        self.confidence = confidence
        self.alternateBPMs = alternateBPMs
        self.onsets = onsets
        self.beatTimes = beatTimes
        self.strongBeatTimes = strongBeatTimes
        self.downbeatTimes = downbeatTimes
        self.analysisVersion = analysisVersion
        self.parameters = parameters
        self.diagnostics = diagnostics
    }

    private enum CodingKeys: String, CodingKey {
        case mediaID, bpm, confidence, alternateBPMs, onsets, beatTimes, strongBeatTimes
        case downbeatTimes, analysisVersion, parameters, diagnostics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaID = try container.decodeIfPresent(UUID.self, forKey: .mediaID)
        bpm = try container.decode(Double.self, forKey: .bpm)
        confidence = try container.decode(Double.self, forKey: .confidence)
        alternateBPMs = try container.decodeIfPresent([Double].self, forKey: .alternateBPMs) ?? []
        onsets = try container.decodeIfPresent([Onset].self, forKey: .onsets) ?? []
        beatTimes = try container.decode([TimelineTime].self, forKey: .beatTimes)
        strongBeatTimes = try container.decode([TimelineTime].self, forKey: .strongBeatTimes)
        downbeatTimes = try container.decode([TimelineTime].self, forKey: .downbeatTimes)
        analysisVersion = try container.decodeIfPresent(Int.self, forKey: .analysisVersion) ?? 1
        parameters = try container.decodeIfPresent(BeatAnalysisParameters.self, forKey: .parameters)
        diagnostics = try container.decodeIfPresent(BeatAnalysisDiagnostics.self, forKey: .diagnostics)
    }
}

struct Onset: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var time: TimelineTime
    var strength: Double

    init(id: UUID = UUID(), time: TimelineTime, strength: Double) {
        self.id = id
        self.time = time
        self.strength = strength
    }
}

struct BeatAnalysisParameters: Codable, Equatable, Sendable {
    static let `default` = BeatAnalysisParameters(
        sampleRate: 44_100,
        windowSize: 1_024,
        hopSize: 512,
        minimumBPM: 60,
        maximumBPM: 200
    )

    var sampleRate: Double
    var windowSize: Int
    var hopSize: Int
    var minimumBPM: Double
    var maximumBPM: Double
}

struct BeatAnalysisDiagnostics: Codable, Equatable, Sendable {
    var duration: TimelineTime
    var sampleRate: Double
    var parameters: BeatAnalysisParameters
    var detectedBPM: Double
    var alternateBPMs: [Double]
    var confidence: Double
    var onsetCount: Int
    var beatCount: Int
    var executionMilliseconds: Int
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

enum ExportCodec: String, Codable, CaseIterable, Sendable {
    case h264
    case hevc
}

enum ExportQuality: String, Codable, CaseIterable, Sendable {
    case medium
    case high
}
