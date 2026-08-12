import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ExportModel {
    private let service = ExportService()
    private var exportTask: Task<Void, Never>?

    var progress = 0.0
    var isExporting = false
    var isCancelling = false
    var errorMessage: String?
    var completedURL: URL?
    var statusMessage: String?

    func export(project: ProjectFile, to outputURL: URL) {
        guard exportTask == nil else { return }
        progress = 0
        isExporting = true
        isCancelling = false
        errorMessage = nil
        completedURL = nil
        statusMessage = "正在准备导出…"
        exportTask = Task { [weak self, service] in
            guard let self else { return }
            let progressTask = Task { [weak self, service] in
                while !Task.isCancelled {
                    guard let self else { return }
                    if let value = await service.progress() {
                        self.progress = value
                        self.statusMessage = "正在导出 \(Int((value * 100).rounded()))%"
                    }
                    try? await Task.sleep(for: .milliseconds(120))
                }
            }
            defer {
                progressTask.cancel()
                exportTask = nil
                isExporting = false
                isCancelling = false
            }
            do {
                let result = try await service.export(project: project, to: outputURL)
                progress = 1
                completedURL = result.outputURL
                statusMessage = "已导出 \(String(format: "%.2f", result.duration.seconds)) 秒视频。"
            } catch let error as ExportServiceError where error == .cancelled {
                statusMessage = "导出已取消，未写入最终文件。"
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = nil
            }
        }
    }

    func cancel() {
        guard isExporting else { return }
        isCancelling = true
        statusMessage = "正在取消导出…"
        exportTask?.cancel()
        Task {
            await service.cancel()
        }
    }

    func revealCompletedFile() {
        guard let completedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([completedURL])
    }
}
