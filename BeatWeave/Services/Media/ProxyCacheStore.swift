import Foundation

actor ProxyCacheStore {
    func materializedURL(for mediaID: UUID, data: Data) throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BeatWeave/PreviewProxies", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(mediaID.uuidString).appendingPathExtension("mp4")
        if !FileManager.default.fileExists(atPath: url.path) || (try? Data(contentsOf: url)) != data {
            try data.write(to: url, options: .atomic)
        }
        return url
    }

    func removeMaterializedProxy(for mediaID: UUID) throws {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BeatWeave/PreviewProxies", isDirectory: true)
            .appendingPathComponent(mediaID.uuidString)
            .appendingPathExtension("mp4")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
