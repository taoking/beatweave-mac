import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExportView: View {
    let project: ProjectFile
    @Binding var settings: ExportSettings
    @Bindable var model: ExportModel
    let onSettingsMutation: () -> Void

    @State private var resolution: ExportResolutionPreset = .fullHDLandscape

    var body: some View {
        GroupBox("导出") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("分辨率", selection: $resolution) {
                    ForEach(ExportResolutionPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                Picker("帧率", selection: $settings.frameRate) {
                    ForEach(FrameRate.allCases, id: \.self) { frameRate in
                        Text(frameRate.displayName).tag(frameRate)
                    }
                }
                Picker("编码", selection: $settings.codec) {
                    ForEach(ExportCodec.allCases, id: \.self) { codec in
                        Text(codec.displayName).tag(codec)
                    }
                }
                Picker("质量", selection: $settings.quality) {
                    ForEach(ExportQuality.allCases, id: \.self) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
                Divider()
                if model.isExporting {
                    ProgressView(value: model.progress) {
                        Text(model.statusMessage ?? "正在导出…")
                    }
                    Button(model.isCancelling ? "正在取消…" : "取消导出") {
                        model.cancel()
                    }
                    .disabled(model.isCancelling)
                } else {
                    Button("导出 MP4…") {
                        chooseExportDestination()
                    }
                    .disabled(project.timeline.videoTracks.flatMap(\.clips).isEmpty)
                }
                if let status = model.statusMessage, !model.isExporting {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if model.completedURL != nil {
                    Button("在访达中显示") {
                        model.revealCompletedFile()
                    }
                }
            }
            .pickerStyle(.menu)
            .onAppear {
                resolution = ExportResolutionPreset.closest(to: settings)
            }
            .onChange(of: resolution) { _, preset in
                let dimensions = preset.dimensions
                settings.width = dimensions.width
                settings.height = dimensions.height
            }
            .onChange(of: settings) { _, _ in
                onSettingsMutation()
            }
        }
        .alert("无法导出视频", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    model.errorMessage = nil
                }
            }
        )) {
            Button("好", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
    }

    private func chooseExportDestination() {
        let panel = NSSavePanel()
        panel.title = "导出 BeatWeave 视频"
        panel.message = "导出将在后台进行；取消不会写入最终文件。"
        panel.nameFieldStringValue = "\(project.name).mp4"
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.export(project: project, to: url)
    }
}
