import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct MediaBrowserView: View {
    @Binding var project: ProjectFile
    @Binding var selectedMediaID: UUID?
    @Binding var thumbnailCaches: [UUID: Data]
    @Binding var proxyCaches: [UUID: Data]
    @Bindable var model: MediaBrowserModel
    let onProjectMutation: () -> Void
    let onSetMusic: (MediaReference) -> Void

    @State private var isImporting = false
    @State private var relinkingMediaID: UUID?

    var body: some View {
        List(selection: $selectedMediaID) {
            Section {
                ForEach(project.mediaLibrary.items) { media in
                    MediaRow(
                        media: media,
                        status: model.sourceStatus(for: media),
                        thumbnailData: model.thumbnails.thumbnailData(for: media)
                    )
                    .tag(media.id)
                    .draggable("media:\(media.id.uuidString)")
                    .contextMenu {
                        Button("在访达中显示") {
                            model.revealInFinder(media)
                        }
                        if media.kind == .audio {
                            Button("设为音乐轨道") {
                                onSetMusic(media)
                            }
                        }
                        if media.kind == .video {
                            if model.generatingProxyIDs.contains(media.id) {
                                Text("正在生成代理…")
                            } else if media.proxy != nil {
                                Button("删除预览代理") {
                                    removeProxy(for: media)
                                }
                            } else {
                                Button("生成预览代理") {
                                    generateProxy(for: media)
                                }
                            }
                        }
                        if model.sourceStatus(for: media) == .missing {
                            Button("重新链接…") {
                                relinkingMediaID = media.id
                            }
                        }
                        Button("从项目移除", role: .destructive) {
                            remove(media)
                        }
                    }
                    .task(id: media.id) {
                        if let data = await model.thumbnails.loadThumbnail(
                            for: media,
                            cachedData: thumbnailCaches[media.id]
                        ), thumbnailCaches[media.id] != data {
                            thumbnailCaches[media.id] = data
                            onProjectMutation()
                        }
                    }
                }
            } header: {
                HStack {
                    Text("媒体")
                    Spacer()
                    Button {
                        isImporting = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("导入媒体")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("媒体")
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: MediaImportService.supportedContentTypes,
            allowsMultipleSelection: true,
            onCompletion: handleImport
        )
        .fileImporter(
            isPresented: Binding(
                get: { relinkingMediaID != nil },
                set: { if !$0 { relinkingMediaID = nil } }
            ),
            allowedContentTypes: MediaImportService.supportedContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handleRelink
        )
        .dropDestination(for: URL.self) { urls, _ in
            importURLs(urls)
            return true
        }
        .alert(
            "无法导入媒体",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            importURLs(urls)
        case let .failure(error):
            model.errorMessage = error.localizedDescription
        }
    }

    private func importURLs(_ urls: [URL]) {
        Task {
            let imported = await model.importMedia(from: urls)
            let appended = MediaLibraryEditor.append(imported, to: &project.mediaLibrary)
            if let first = appended.first {
                selectedMediaID = first.id
                onProjectMutation()
            }
            await model.refreshSourceStatuses(for: project.mediaLibrary.items)
        }
    }

    private func handleRelink(_ result: Result<[URL], Error>) {
        defer {
            relinkingMediaID = nil
        }
        guard let mediaID = relinkingMediaID else {
            return
        }

        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                return
            }
            Task {
                let imported = await model.importMedia(from: [url])
                guard let replacement = imported.first else {
                    return
                }
                if MediaLibraryEditor.relink(mediaID: mediaID, with: replacement, in: &project.mediaLibrary) {
                    onProjectMutation()
                }
                await model.refreshSourceStatuses(for: project.mediaLibrary.items)
            }
        case let .failure(error):
            model.errorMessage = error.localizedDescription
        }
    }

    private func remove(_ media: MediaReference) {
        guard MediaLibraryEditor.remove(mediaID: media.id, from: &project) != nil else {
            return
        }
        model.thumbnails.removeThumbnail(for: media.id)
        thumbnailCaches[media.id] = nil
        proxyCaches[media.id] = nil
        Task { await model.removeMaterializedProxy(for: media.id) }
        if selectedMediaID == media.id {
            selectedMediaID = nil
        }
        onProjectMutation()
    }

    private func generateProxy(for media: MediaReference) {
        Task {
            guard let generated = await model.generateProxy(for: media),
                  let index = project.mediaLibrary.items.firstIndex(where: { $0.id == media.id })
            else {
                return
            }
            proxyCaches[media.id] = generated.data
            project.mediaLibrary.items[index].proxy = generated.info
            onProjectMutation()
        }
    }

    private func removeProxy(for media: MediaReference) {
        guard let index = project.mediaLibrary.items.firstIndex(where: { $0.id == media.id }) else { return }
        proxyCaches[media.id] = nil
        project.mediaLibrary.items[index].proxy = nil
        Task { await model.removeMaterializedProxy(for: media.id) }
        onProjectMutation()
    }
}

private struct MediaRow: View {
    let media: MediaReference
    let status: MediaSourceStatus?
    let thumbnailData: Data?

    var body: some View {
        HStack(spacing: 10) {
            MediaThumbnail(data: thumbnailData, kind: media.kind)
            VStack(alignment: .leading, spacing: 3) {
                Text(media.displayName)
                    .lineLimit(1)
                Text(metadataSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if media.proxy != nil {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .foregroundStyle(.blue)
                    .accessibilityLabel("存在预览代理")
            }
            sourceStatusView
        }
        .padding(.vertical, 3)
    }

    private var metadataSummary: String {
        let duration = String(format: "%.2fs", media.duration.seconds)
        guard let video = media.videoMetadata else {
            return "音频 · \(duration)"
        }
        return "\(video.width)×\(video.height) · \(String(format: "%.0f", video.nominalFrameRate)) fps · \(duration)"
    }

    @ViewBuilder
    private var sourceStatusView: some View {
        switch status {
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("媒体源可用")
        case .missing:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("媒体源丢失")
        case nil:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("正在检查媒体源")
        }
    }
}

private struct MediaThumbnail: View {
    let data: Data?
    let kind: MediaKind

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: kind == .video ? "film" : "waveform")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 52, height: 36)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
