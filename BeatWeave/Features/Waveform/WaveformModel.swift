import Observation

@MainActor
@Observable
final class WaveformModel {
    private let service = WaveformService()

    var isGenerating = false
    var errorMessage: String?

    func generate(for media: MediaReference) async -> WaveformCache? {
        guard !isGenerating else { return nil }
        isGenerating = true
        defer { isGenerating = false }
        do {
            return try await service.generate(for: media)
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
