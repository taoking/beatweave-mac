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

    init(document: Binding<BeatWeaveDocument>) {
        _document = document
    }

    var body: some View {
        NavigationSplitView {
            MediaBrowserView(
                project: $document.project,
                selectedMediaID: $selectedMediaID,
                thumbnailCaches: $document.thumbnailCaches,
                proxyCaches: $document.proxyCaches,
                model: mediaBrowser,
                onProjectMutation: markProjectModified,
                onSetMusic: setMusic
            )
        } detail: {
            HSplitView {
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
                .frame(minWidth: 620)
                VStack(alignment: .leading, spacing: 12) {
                    ProjectWorkflowView(
                        project: $document.project,
                        recoveredFromBackup: document.recoveredFromBackup,
                        onProjectMutation: markProjectModified
                    )
                    EditingInspectorView(
                        project: $document.project,
                        selectedClipID: timeline.selectedClipID,
                        timeline: timeline,
                        onProjectMutation: markProjectModified
                    )
                    AutoCutView(
                        media: document.project.mediaLibrary.items,
                        beatAnalysis: musicBeatAnalysis,
                        musicDuration: musicMedia?.duration,
                        smartMontage: $document.project.smartMontage,
                        model: autoCut,
                        onApply: applyAutoCut,
                        onProjectMutation: markProjectModified
                    )
                    ExportView(
                        project: document.project,
                        settings: $document.project.exportSettings,
                        model: export,
                        onSettingsMutation: markProjectModified
                    )
                }
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340, maxHeight: .infinity, alignment: .top)
                .padding(12)
            }
            .navigationTitle(document.project.name)
        }
        .frame(minWidth: 900, minHeight: 560)
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
    }

    private var selectedMedia: MediaReference? {
        guard let selectedMediaID else {
            return nil
        }
        return document.project.mediaLibrary.items.first { $0.id == selectedMediaID }
    }

    private func markProjectModified() {
        document.project.markModified()
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
