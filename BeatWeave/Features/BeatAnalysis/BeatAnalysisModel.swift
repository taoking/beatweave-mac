import Foundation
import Observation

@MainActor
@Observable
final class BeatAnalysisModel {
    private let service = BeatAnalysisService()
    private var tapTempo = TapTempoTracker()

    var isAnalyzing = false
    var errorMessage: String?
    var latestDiagnostics: BeatAnalysisDiagnostics?

    func analyze(for media: MediaReference) async -> BeatAnalysis? {
        guard !isAnalyzing else { return nil }
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let analysis = try await service.analyze(for: media)
            latestDiagnostics = analysis.diagnostics
            return analysis
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func registerTap() -> Double? {
        tapTempo.registerTap(at: Date.timeIntervalSinceReferenceDate)
    }
}
