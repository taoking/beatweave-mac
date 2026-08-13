import XCTest
@testable import BeatWeave

final class LUTCubeTests: XCTestCase {
    func testParsesThreeDimensionalCubeAndBuildsRGBAData() throws {
        let cube = try LUTCube(contents: """
        TITLE \"Identity\"
        LUT_3D_SIZE 2
        0 0 0
        1 0 0
        0 1 0
        1 1 0
        0 0 1
        1 0 1
        0 1 1
        1 1 1
        """)

        XCTAssertEqual(cube.dimension, 2)
        XCTAssertEqual(cube.entries.count, 8)
        XCTAssertEqual(cube.colorCubeData(intensity: 1).count, 2 * 2 * 2 * 4 * MemoryLayout<Float>.stride)
    }

    func testIntensityInterpolatesBetweenIdentityAndCube() throws {
        let cube = try LUTCube(contents: """
        LUT_3D_SIZE 2
        0 0 0
        0 0 0
        0 0 0
        0 0 0
        0 0 0
        0 0 0
        0 0 0
        0 0 0
        """)

        let identity = floatValues(from: cube.colorCubeData(intensity: 0))
        let transformed = floatValues(from: cube.colorCubeData(intensity: 1))

        XCTAssertEqual(identity[4], 1, accuracy: 0.0001)
        XCTAssertEqual(identity[5], 0, accuracy: 0.0001)
        XCTAssertEqual(identity[6], 0, accuracy: 0.0001)
        XCTAssertEqual(transformed[4], 0, accuracy: 0.0001)
        XCTAssertEqual(transformed[5], 0, accuracy: 0.0001)
        XCTAssertEqual(transformed[6], 0, accuracy: 0.0001)
        XCTAssertEqual(transformed[7], 1, accuracy: 0.0001)
    }

    func testRejectsIncompleteCube() {
        XCTAssertThrowsError(try LUTCube(contents: "LUT_3D_SIZE 2\n0 0 0")) { error in
            XCTAssertEqual(error as? LUTCubeError, .incomplete(expected: 8, actual: 1))
        }
    }

    func testRejectsUnsupportedDomainInsteadOfApplyingItIncorrectly() {
        XCTAssertThrowsError(try LUTCube(contents: """
        DOMAIN_MIN 0.1 0.1 0.1
        LUT_3D_SIZE 2
        0 0 0
        1 0 0
        0 1 0
        1 1 0
        0 0 1
        1 0 1
        0 1 1
        1 1 1
        """)) { error in
            XCTAssertEqual(error as? LUTCubeError, .unsupportedDomain)
        }
    }

    private func floatValues(from data: Data) -> [Float] {
        var values = [Float](repeating: 0, count: data.count / MemoryLayout<Float>.stride)
        _ = values.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return values
    }
}
