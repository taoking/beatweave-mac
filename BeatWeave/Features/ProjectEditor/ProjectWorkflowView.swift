import SwiftUI

struct ProjectWorkflowView: View {
    @Binding var project: ProjectFile
    let recoveredFromBackup: Bool
    let defaultProjectDirectory: URL
    let onChooseDefaultDirectory: () -> Void
    let onProjectMutation: () -> Void

    private var diagnostics: ProjectDiagnostics {
        ProjectDiagnostics.make(for: project)
    }

    var body: some View {
        GroupBox("项目工作流") {
            VStack(alignment: .leading, spacing: 8) {
                if recoveredFromBackup {
                    Label("已从最近可用恢复快照打开；请另存为以确认恢复结果。", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                DisclosureGroup("键盘快捷键") {
                    shortcutFields
                }
                DisclosureGroup("项目诊断") {
                    diagnosticsView
                }
                DisclosureGroup("默认项目目录") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(defaultProjectDirectory.path)
                            .font(.caption)
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Button("更改默认目录…", action: onChooseDefaultDirectory)
                            .controlSize(.small)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var shortcutFields: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                Text("撤销 ⌘")
                TextField("Z", text: shortcutBinding(\.undoKey))
                    .frame(width: 42)
            }
            GridRow {
                Text("重做 ⌘")
                TextField("Y", text: shortcutBinding(\.redoKey))
                    .frame(width: 42)
            }
            GridRow {
                Text("分割")
                TextField("S", text: shortcutBinding(\.splitKey))
                    .frame(width: 42)
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(.caption)
        .padding(.top, 4)
    }

    private var diagnosticsView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("视频轨 \(diagnostics.videoTrackCount) · 音频轨 \(diagnostics.audioTrackCount)")
            Text("视频剪辑 \(diagnostics.videoClipCount) · 音频剪辑 \(diagnostics.audioClipCount)")
            Text("时长 \(diagnostics.projectDuration.seconds, format: .number.precision(.fractionLength(2))) 秒 · 代理 \(diagnostics.proxyCount)")
            Text("模型估计 \(ByteCountFormatter.string(fromByteCount: Int64(diagnostics.estimatedTimelineBytes), countStyle: .file))")
            if diagnostics.missingMediaCount > 0 {
                Text("\(diagnostics.missingMediaCount) 个媒体源不可用")
                    .foregroundStyle(.orange)
            } else {
                Text("所有已引用媒体源状态正常")
                    .foregroundStyle(.green)
            }
        }
        .font(.caption)
        .padding(.top, 4)
    }

    private func shortcutBinding(_ keyPath: WritableKeyPath<EditorKeyboardShortcuts, String>) -> Binding<String> {
        Binding(
            get: { (project.editorKeyboardShortcuts ?? .default)[keyPath: keyPath] },
            set: { value in
                var shortcuts = project.editorKeyboardShortcuts ?? .default
                shortcuts[keyPath: keyPath] = value
                project.editorKeyboardShortcuts = shortcuts.validated()
                onProjectMutation()
            }
        )
    }
}
