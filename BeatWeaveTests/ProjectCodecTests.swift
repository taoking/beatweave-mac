import XCTest
@testable import BeatWeave

final class ProjectCodecTests: XCTestCase {
    func testRoundTripPreservesProjectAndPreciseTimelineTime() throws {
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-13T00:00:00Z"))
        var project = ProjectFile.new(name: "旅程", now: createdAt)
        let mediaID = UUID(uuidString: "B14E5F69-7BFE-4E0A-A432-17F2395AA617") ?? UUID()
        project.mediaLibrary.items = [
            MediaReference(
                id: mediaID,
                displayName: "coast.mov",
                originalURL: URL(fileURLWithPath: "/fixtures/coast.mov"),
                kind: .video,
                duration: TimelineTime(seconds: 12.345, timescale: 1_000),
                videoMetadata: VideoMetadata(width: 1_920, height: 1_080, nominalFrameRate: 30)
            )
        ]
        project.timeline.videoTracks = [
            VideoTrack(
                id: UUID(uuidString: "A3B4F39D-6768-4ACD-8B4D-A3B6024D7315") ?? UUID(),
                clips: [
                    TimelineClip(
                        id: UUID(uuidString: "24E22F5B-3539-4AF0-B60C-D6E1B23E4BCD") ?? UUID(),
                        mediaID: mediaID,
                        sourceRange: MediaTimeRange(start: .zero, duration: TimelineTime(seconds: 4.125, timescale: 1_000)),
                        timelineStart: TimelineTime(seconds: 0.5, timescale: 1_000),
                        playbackRate: 1,
                        transform: .identity,
                        opacity: 1,
                        volume: 1,
                        transitionIn: .hardCut,
                        transitionOut: .hardCut
                    )
                ]
            )
        ]

        let encoded = try ProjectCodec.encode(project)
        let decoded = try ProjectCodec.decode(encoded)

        XCTAssertEqual(decoded, project)
        XCTAssertEqual(decoded.timeline.videoTracks[0].clips[0].sourceRange.duration.seconds, 4.125)
    }

    func testDecodeRejectsUnsupportedProjectFormat() throws {
        let data = Data("{\"projectFormatVersion\":99}".utf8)

        XCTAssertThrowsError(try ProjectCodec.decode(data)) { error in
            XCTAssertEqual(
                error as? ProjectCodecError,
                .unsupportedFormatVersion(found: 99, supported: ProjectFile.currentFormatVersion)
            )
        }
    }

    func testRoundTripPreservesSubsecondProjectDates() throws {
        let timestamp = Date(timeIntervalSinceReferenceDate: 123_456_789.125)
        let project = ProjectFile.new(name: "带毫秒的项目", now: timestamp)

        let restored = try ProjectCodec.decode(ProjectCodec.encode(project))

        XCTAssertEqual(restored.createdAt, timestamp)
        XCTAssertEqual(restored.modifiedAt, timestamp)
    }

    func testTimelineTimeRejectsZeroTimescaleFromProjectData() {
        let data = Data("{\"value\":10,\"timescale\":0}".utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(TimelineTime.self, from: data))
    }
}
