import SwiftUI

struct ProjectEditorView: View {
    @Binding private var document: BeatWeaveDocument
    @State private var selectedMediaID: UUID?
    @State private var mediaBrowser = MediaBrowserModel()
    @State private var playback = PlaybackService()
    @State private var waveform = WaveformModel()
    @State private var beatAnalysis = BeatAnalysisModel()
    @State private var timeline = TimelineEditorModel()
    @State private var autoCut = AutoCutModel()
    @State private var export = ExportModel()
    private let projectStore: DefaultProjectStore

    init(document: Binding<BeatWeaveDocument>, projectStore: DefaultProjectStore) {
        _document = document
        self.projectStore = projectStore
    }

    var body: some View {
        ProjectEditorThreeColumnLayout(
            mediaBrowser: mediaBrowserPane,
            editor: editorPane,
            sidebar: workflowSidebar
        )
        .frame(minWidth: 1_180, minHeight: 560)
        .task {
            await mediaBrowser.refreshSourceStatuses(for: document.project.mediaLibrary.items)
        }
        .onChange(of: selectedMediaID) { _, _ in
            playback.preview(selectedMedia, proxyData: selectedMedia.flatMap { document.proxyCaches[$0.id] })
        }
        .onChange(of: document.project.mediaLibrary.items) { _, items in
            Task {
                await mediaBrowser.refreshSourceStatuses(for: items)
            }
        }
        .alert("无法生成波形", isPresented: Binding(
            get: { waveform.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    waveform.errorMessage = nil
                }
            }
        )) {
            Button("好", role: .cancel) {
                waveform.errorMessage = nil
            }
        } message: {
            Text(waveform.errorMessage ?? "未知错误")
        }
        .alert("无法分析节拍", isPresented: Binding(
            get: { beatAnalysis.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    beatAnalysis.errorMessage = nil
                }
            }
        )) {
            Button("好", role: .cancel) {
                beatAnalysis.errorMessage = nil
            }
        } message: {
            Text(beatAnalysis.errorMessage ?? "未知错误")
        }
        .alert("无法保存项目", isPresented: Binding(
            get: { projectStore.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    projectStore.errorMessage = nil
                }
            }
        )) {
            Button("好", role: .cancel) {
                projectStore.errorMessage = nil
            }
        } message: {
            Text(projectStore.errorMessage ?? "未知错误")
        }
    }

    private var mediaBrowserPane: AnyView {
        AnyView(MediaBrowserView(
            project: $document.project,
            selectedMediaID: $selectedMediaID,
            thumbnailCaches: $document.thumbnailCaches,
            proxyCaches: $document.proxyCaches,
            model: mediaBrowser,
            onProjectMutation: markProjectModified,
            onSetMusic: setMusic
        ))
    }

    private var editorPane: AnyView {
        AnyView(editorCanvas)
    }

    private var editorCanvas: some View {
        VStack(spacing: 0) {
            ViewerView(project: document.project, selectedMedia: selectedMedia, playback: playback)
            WaveformTimelineView(
                music: musicMedia,
                cache: musicMedia.flatMap { document.waveformCaches[$0.id] },
                beatAnalysis: musicBeatAnalysis,
                playheadSeconds: playback.currentTimeSeconds,
                isGenerating: waveform.isGenerating,
                isAnalyzing: beatAnalysis.isAnalyzing,
                onGenerate: generateWaveform,
                onAnalyze: analyzeBeats,
                onApplyManualBPM: applyManualBPM,
                onTapTempo: beatAnalysis.registerTap
            )
            TimelineEditorView(
                project: $document.project,
                selectedMedia: selectedMedia,
                beatAnalysis: musicBeatAnalysis,
                playheadSeconds: playback.currentTimeSeconds,
                model: timeline,
                onSeek: playback.seek,
                onProjectMutation: markProjectModified
            )
        }
    }

    private var workflowSidebar: AnyView {
        AnyView(ProjectEditorWorkflowSidebar(
            project: $document.project,
            recoveredFromBackup: document.recoveredFromBackup,
            defaultProjectDirectory: projectStore.projectDirectory,
            onChooseDefaultDirectory: projectStore.chooseDefaultDirectory,
            selectedClipID: timeline.selectedClipID,
            timeline: timeline,
            autoCut: autoCut,
            export: export,
            beatAnalysis: musicBeatAnalysis,
            musicDuration: musicMedia?.duration,
            onApplyAutoCut: applyAutoCut,
            onProjectMutation: markProjectModified
        ))
    }

    private var selectedMedia: MediaReference? {
        guard let selectedMediaID else {
            return nil
        }
        return document.project.mediaLibrary.items.first { $0.id == selectedMediaID }
    }

    private func markProjectModified() {
        document.project.markModified()
        projectStore.save(document)
    }

    private var musicMedia: MediaReference? {
        guard let musicID = document.project.timeline.musicTrack?.mediaID else { return nil }
        return document.project.mediaLibrary.items.first { $0.id == musicID }
    }

    private var musicBeatAnalysis: BeatAnalysis? {
        guard let musicMedia,
              let analysis = document.project.beatAnalysis,
              analysis.mediaID == musicMedia.id
        else {
            return nil
        }
        return analysis
    }

    private func setMusic(_ media: MediaReference) {
        document.project.timeline.musicTrack = MusicTrack(
            mediaID: media.id,
            timelineStart: .zero,
            volume: 1,
            fadeInDuration: .zero,
            fadeOutDuration: .zero
        )
        if document.project.beatAnalysis?.mediaID != media.id {
            document.project.beatAnalysis = nil
        }
        markProjectModified()
        playback.preview(media)
        generateWaveform()
        analyzeBeats()
    }

    private func generateWaveform() {
        guard let musicMedia else { return }
        Task {
            if let cache = await waveform.generate(for: musicMedia),
               document.project.timeline.musicTrack?.mediaID == musicMedia.id {
                document.waveformCaches[musicMedia.id] = cache
                markProjectModified()
            }
        }
    }

    private func analyzeBeats() {
        guard let musicMedia else { return }
        Task {
            if let analysis = await beatAnalysis.analyze(for: musicMedia),
               document.project.timeline.musicTrack?.mediaID == musicMedia.id {
                document.project.beatAnalysis = analysis
                markProjectModified()
            }
        }
    }

    private func applyManualBPM(_ bpm: Double) {
        guard let musicMedia,
              let analysis = BeatAnalysisDSP.applyManualBPM(
                  bpm,
                  mediaID: musicMedia.id,
                  duration: musicMedia.duration,
                  existingAnalysis: musicBeatAnalysis
              )
        else {
            return
        }
        document.project.beatAnalysis = analysis
        markProjectModified()
    }

    private func applyAutoCut(_ plan: AutoCutPlan) {
        if timeline.applyAutoCut(plan, to: &document.project) {
            markProjectModified()
        }
    }
}

private struct ProjectEditorThreeColumnLayout: View {
    let mediaBrowser: AnyView
    let editor: AnyView
    let sidebar: AnyView

    var body: some View {
        HStack(spacing: 0) {
            mediaBrowser
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320, maxHeight: .infinity)

            Divider()

            editor
                .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            sidebar
                .frame(width: 320)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(12)
        }
    }
}

private struct ProjectEditorWorkflowSidebar: View {
    @Binding var project: ProjectFile
    let recoveredFromBackup: Bool
    let defaultProjectDirectory: URL
    let onChooseDefaultDirectory: () -> Void
    let selectedClipID: UUID?
    let timeline: TimelineEditorModel
    let autoCut: AutoCutModel
    let export: ExportModel
    let beatAnalysis: BeatAnalysis?
    let musicDuration: TimelineTime?
    let onApplyAutoCut: (AutoCutPlan) -> Void
    let onProjectMutation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProjectWorkflowView(
                project: $project,
                recoveredFromBackup: recoveredFromBackup,
                defaultProjectDirectory: defaultProjectDirectory,
                onChooseDefaultDirectory: onChooseDefaultDirectory,
                onProjectMutation: onProjectMutation
            )
            EditingInspectorView(
                project: $project,
                selectedClipID: selectedClipID,
                timeline: timeline,
                onProjectMutation: onProjectMutation
            )
            AutoCutView(
                media: project.mediaLibrary.items,
                beatAnalysis: beatAnalysis,
                musicDuration: musicDuration,
                smartMontage: $project.smartMontage,
                model: autoCut,
                onApply: onApplyAutoCut,
                onProjectMutation: onProjectMutation
            )
            ExportView(
                project: project,
                settings: $project.exportSettings,
                model: export,
                onSettingsMutation: onProjectMutation
            )
        }
    }
}
