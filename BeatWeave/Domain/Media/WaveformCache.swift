import Foundation

struct WaveformCache: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var mediaID: UUID
    var duration: TimelineTime
    var levels: [WaveformLevel]

    func level(forDisplayWidth width: Int) -> WaveformLevel? {
        levels.first(where: { $0.samples.count >= width }) ?? levels.last
    }
}

struct WaveformLevel: Codable, Equatable, Sendable {
    var bucketCount: Int
    var samples: [WaveformSample]
}

struct WaveformSample: Codable, Equatable, Sendable {
    var peak: Float
    var rms: Float
}
