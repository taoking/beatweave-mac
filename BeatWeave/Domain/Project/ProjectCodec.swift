import Foundation

enum ProjectCodec {
    private struct VersionEnvelope: Decodable {
        let projectFormatVersion: Int
    }

    static func encode(_ project: ProjectFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(makeDateFormatter(includeFractionalSeconds: true).string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(project)
    }

    static func decode(_ data: Data) throws -> ProjectFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let encodedDate = try container.decode(String.self)
            if let date = makeDateFormatter(includeFractionalSeconds: true).date(from: encodedDate)
                ?? makeDateFormatter(includeFractionalSeconds: false).date(from: encodedDate) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Project dates must use ISO-8601 format."
            )
        }
        let version = try decoder.decode(VersionEnvelope.self, from: data).projectFormatVersion

        guard version == ProjectFile.currentFormatVersion else {
            throw ProjectCodecError.unsupportedFormatVersion(
                found: version,
                supported: ProjectFile.currentFormatVersion
            )
        }

        return try decoder.decode(ProjectFile.self, from: data)
    }

    private static func makeDateFormatter(includeFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = includeFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}

enum ProjectCodecError: LocalizedError, Equatable {
    case unsupportedFormatVersion(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormatVersion(found, supported):
            "无法打开项目格式版本 \(found)；此版本仅支持格式版本 \(supported)。"
        }
    }
}
