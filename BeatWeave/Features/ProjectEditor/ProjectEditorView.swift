import SwiftUI

struct ProjectEditorView: View {
    @Binding private var document: BeatWeaveDocument

    init(document: Binding<BeatWeaveDocument>) {
        _document = document
    }

    var body: some View {
        NavigationSplitView {
            ProjectMetadataSidebar(project: $document.project)
        } detail: {
            ProjectOverviewView(project: document.project)
        }
        .frame(minWidth: 900, minHeight: 560)
    }
}

private struct ProjectMetadataSidebar: View {
    @Binding var project: ProjectFile

    var body: some View {
        List {
            Section("项目") {
                TextField("项目名称", text: $project.name)
                LabeledContent("格式版本", value: "v\(project.projectFormatVersion)")
                LabeledContent("画布", value: project.canvas.displayName)
                LabeledContent("帧率", value: project.frameRate.displayName)
            }

            Section("媒体") {
                LabeledContent("媒体引用", value: "\(project.mediaLibrary.items.count)")
                LabeledContent("视频轨道", value: "\(project.timeline.videoTracks.count)")
                LabeledContent("音频轨道", value: "\(project.timeline.audioTracks.count)")
            }
        }
        .navigationTitle("BeatWeave")
        .listStyle(.sidebar)
    }
}

private struct ProjectOverviewView: View {
    let project: ProjectFile

    var body: some View {
        ContentUnavailableView {
            Label("\(project.name) 已准备就绪", systemImage: "music.note.list")
        } description: {
            Text("项目格式已初始化。媒体导入和预览将在下一开发阶段加入。")
        }
        .navigationTitle(project.name)
    }
}
