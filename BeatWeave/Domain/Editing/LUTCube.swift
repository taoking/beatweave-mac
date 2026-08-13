import Foundation

enum LUTCubeError: LocalizedError, Equatable {
    case unreadable
    case missingDimension
    case unsupportedDimension(Int)
    case unsupportedOneDimensionalLUT
    case unsupportedDomain
    case invalidEntry(String)
    case incomplete(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .unreadable: "无法读取 .cube LUT 文件。"
        case .missingDimension: "LUT 缺少 LUT_3D_SIZE。"
        case let .unsupportedDimension(size): "LUT 的 3D 尺寸 \(size) 不受支持。"
        case .unsupportedOneDimensionalLUT: "仅支持 3D .cube LUT，不支持包含 1D 表的数据。"
        case .unsupportedDomain: "仅支持输入范围为 0 到 1 的标准 .cube LUT。"
        case let .invalidEntry(line): "LUT 包含无效颜色项：\(line)。"
        case let .incomplete(expected, actual): "LUT 应有 \(expected) 个颜色项，实际为 \(actual) 个。"
        }
    }
}

/// A parsed Resolve-style 3D `.cube` lookup table. The parser is deliberately
/// strict about its finite size so an imported file cannot allocate unbounded
/// render memory during export.
struct LUTCube: Equatable, Sendable {
    let dimension: Int
    let entries: [SIMD3<Float>]

    init(data: Data) throws {
        guard let contents = String(data: data, encoding: .utf8) else {
            throw LUTCubeError.unreadable
        }
        try self.init(contents: contents)
    }

    init(contents: String) throws {
        var dimension: Int?
        var entries: [SIMD3<Float>] = []
        var domainMinimum = SIMD3<Float>(repeating: 0)
        var domainMaximum = SIMD3<Float>(repeating: 1)
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let keyword = fields.first else { continue }
            switch keyword.uppercased() {
            case "TITLE":
                continue
            case "DOMAIN_MIN", "DOMAIN_MAX":
                guard fields.count == 4,
                      let red = Float(fields[1]),
                      let green = Float(fields[2]),
                      let blue = Float(fields[3])
                else {
                    throw LUTCubeError.invalidEntry(line)
                }
                if keyword.uppercased() == "DOMAIN_MIN" {
                    domainMinimum = SIMD3(red, green, blue)
                } else {
                    domainMaximum = SIMD3(red, green, blue)
                }
            case "LUT_3D_SIZE":
                guard fields.count == 2, let value = Int(fields[1]), value >= 2, value <= 64 else {
                    throw LUTCubeError.unsupportedDimension(Int(fields.dropFirst().first ?? "") ?? -1)
                }
                dimension = value
            case "LUT_1D_SIZE":
                throw LUTCubeError.unsupportedOneDimensionalLUT
            default:
                guard fields.count == 3,
                      let red = Float(fields[0]),
                      let green = Float(fields[1]),
                      let blue = Float(fields[2])
                else {
                    throw LUTCubeError.invalidEntry(line)
                }
                entries.append(SIMD3(red, green, blue))
            }
        }
        guard let dimension else { throw LUTCubeError.missingDimension }
        guard domainMinimum == SIMD3(repeating: 0), domainMaximum == SIMD3(repeating: 1) else {
            throw LUTCubeError.unsupportedDomain
        }
        let expectedCount = dimension * dimension * dimension
        guard entries.count == expectedCount else {
            throw LUTCubeError.incomplete(expected: expectedCount, actual: entries.count)
        }
        self.dimension = dimension
        self.entries = entries
    }

    static func load(from reference: LUTReference) throws -> LUTCube {
        var url = reference.fileURL
        if !FileManager.default.fileExists(atPath: url.path), let bookmark = reference.securityScopedBookmark {
            var stale = false
            url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        }
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try LUTCube(data: Data(contentsOf: url))
    }

    /// `CIColorCube` consumes an RGBA float buffer. Interpolating the cube with
    /// identity here makes LUT intensity deterministic and avoids a second image
    /// blend in the export filter chain.
    func colorCubeData(intensity: Double) -> Data {
        let amount = Float(min(1, max(0, intensity)))
        var result = Data(capacity: entries.count * MemoryLayout<Float>.stride * 4)
        for blueIndex in 0..<dimension {
            for greenIndex in 0..<dimension {
                for redIndex in 0..<dimension {
                    let identity = SIMD3<Float>(
                        Float(redIndex) / Float(dimension - 1),
                        Float(greenIndex) / Float(dimension - 1),
                        Float(blueIndex) / Float(dimension - 1)
                    )
                    let entryIndex = (blueIndex * dimension * dimension) + (greenIndex * dimension) + redIndex
                    let adjusted = identity + ((entries[entryIndex] - identity) * amount)
                    let values = [adjusted.x, adjusted.y, adjusted.z, Float(1)]
                    values.withUnsafeBytes { result.append(contentsOf: $0) }
                }
            }
        }
        return result
    }
}
