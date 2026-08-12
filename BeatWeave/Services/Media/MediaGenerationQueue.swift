import Foundation

/// Serializes CPU and I/O-heavy cache generation so importing several long clips
/// does not compete with playback or exhaust the user's storage bandwidth.
actor MediaGenerationQueue {
    static let shared = MediaGenerationQueue()

    private var tail: Task<Void, Never>?

    func perform<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let previous = tail
        let task = Task {
            _ = await previous?.result
            try Task.checkCancellation()
            return try await operation()
        }
        tail = Task {
            _ = await task.result
        }
        return try await task.value
    }
}
