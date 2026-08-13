import SwiftUI
import UniformTypeIdentifiers

/// Project and clip controls deliberately edit the document through `TimelineEditorModel`.
/// This keeps the inspector's mutations on the same undo/redo path as the timeline.
struct EditingInspectorView: View {
    @Binding var project: ProjectFile
    let selectedClipID: UUID?
    @Bindable var timeline: TimelineEditorModel
    let onProjectMutation: () -> Void

    @State private var isImportingLUT = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                canvasControls
                audioControls
                if let selectedClip {
                    clipControls(for: selectedClip)
                } else {
                    ContentUnavailableView(
                        "选择一个剪辑",
                        systemImage: "slider.horizontal.3",
                        description: Text("在时间线上选择视频剪辑后可调整速度、转场、画面和原声。")
                    )
                }
            }
            .padding(.vertical, 2)
        }
        .fileImporter(
            isPresented: $isImportingLUT,
            allowedContentTypes: [.cubeLUT],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            mutateClip("导入 LUT") { clip in
                var appearance = clip.appearance ?? .default
                appearance.lut = LUTReference(
                    displayName: url.lastPathComponent,
                    fileURL: url,
                    intensity: 1,
                    securityScopedBookmark: bookmark
                )
                clip.appearance = appearance
            }
        }
    }

    private var canvasControls: some View {
        GroupBox("画布") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("比例", selection: canvasPresetBinding) {
                    ForEach(CanvasPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                if project.canvas.preset == .custom || project.canvas.preset == nil {
                    HStack {
                        Stepper("宽 (project.canvas.width)", value: canvasWidthBinding, in: 240...7_680, step: 10)
                        Stepper("高 (project.canvas.height)", value: canvasHeightBinding, in: 240...7_680, step: 10)
                    }
                    .font(.caption)
                }
                Text("当前：(project.canvas.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .pickerStyle(.menu)
        }
    }

    private var audioControls: some View {
        GroupBox("音频") {
            VStack(alignment: .leading, spacing: 8) {
                Slider(value: masterVolumeBinding, in: 0...1) {
                    Text("主音量")
                } minimumValueLabel: {
                    Text("0")
                } maximumValueLabel: {
                    Text("100")
                }
                .accessibilityLabel("主音量")
                if project.timeline.musicTrack != nil {
                    Slider(value: musicVolumeBinding, in: 0...1) {
                        Text("音乐音量")
                    }
                    HStack {
                        Stepper("淡入 (musicFadeInBinding.wrappedValue, format: .number.precision(.fractionLength(1))) 秒", value: musicFadeInBinding, in: 0...20, step: 0.25)
                        Stepper("淡出 (musicFadeOutBinding.wrappedValue, format: .number.precision(.fractionLength(1))) 秒", value: musicFadeOutBinding, in: 0...20, step: 0.25)
                    }
                    .font(.caption)
                } else {
                    Text("尚未设置音乐轨道")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func clipControls(for clip: TimelineClip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("剪辑") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("入场转场", selection: transitionInBinding) {
                        transitionChoices
                    }
                    Picker("出场转场", selection: transitionOutBinding) {
                        transitionChoices
                    }
                    Text("交叉叠化会在同一视频轨的相邻剪辑实际重叠时生效；请将两段剪辑拖动为重叠。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("速度", selection: playbackRateBinding) {
                        ForEach([0.25, 0.5, 1, 2, 4], id: \.self) { rate in
                            Text("\(rate, format: .number.precision(.fractionLength(2)))×").tag(rate)
                        }
                    }
                    Slider(value: playbackRateBinding, in: 0.25...4, step: 0.05) {
                        Text("自定义速度")
                    }
                    Toggle("静音原声", isOn: originalAudioMutedBinding)
                    Slider(value: originalAudioVolumeBinding, in: 0...1) {
                        Text("原声音量")
                    }
                }
                .pickerStyle(.menu)
            }

            GroupBox("构图") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("填充方式", selection: contentModeBinding) {
                        ForEach(ClipContentMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    Slider(value: scaleBinding, in: 0.25...3) { Text("缩放") }
                    Slider(value: positionXBinding, in: -960...960) { Text("水平位置") }
                    Slider(value: positionYBinding, in: -960...960) { Text("垂直位置") }
                    Slider(value: rotationBinding, in: -180...180) { Text("旋转") }
                    Slider(value: cropXBinding, in: 0...0.9) { Text("裁剪左") }
                    Slider(value: cropYBinding, in: 0...0.9) { Text("裁剪上") }
                    Slider(value: cropWidthBinding, in: 0.05...1) { Text("裁剪宽") }
                    Slider(value: cropHeightBinding, in: 0.05...1) { Text("裁剪高") }
                    Slider(value: opacityBinding, in: 0...1) { Text("不透明度") }
                }
                .pickerStyle(.menu)
            }

            GroupBox("基础调色") {
                VStack(alignment: .leading, spacing: 8) {
                    Slider(value: exposureBinding, in: -2...2) { Text("曝光") }
                    Slider(value: contrastBinding, in: 0...2) { Text("对比度") }
                    Slider(value: saturationBinding, in: 0...2) { Text("饱和度") }
                    Slider(value: temperatureBinding, in: -1...1) { Text("色温") }
                    Slider(value: tintBinding, in: -1...1) { Text("色调") }
                    Slider(value: highlightsBinding, in: -1...1) { Text("高光") }
                    Slider(value: shadowsBinding, in: -1...1) { Text("阴影") }
                    HStack {
                        Button("导入 .cube LUT…") { isImportingLUT = true }
                        if let lut = clip.appearance?.lut {
                            Text(lut.displayName)
                                .lineLimit(1)
                                .font(.caption)
                            Button("移除") {
                                mutateClip("移除 LUT") { edited in
                                    var appearance = edited.appearance ?? .default
                                    appearance.lut = nil
                                    edited.appearance = appearance
                                }
                            }
                        }
                    }
                    if clip.appearance?.lut != nil {
                        Slider(value: lutIntensityBinding, in: 0...1) { Text("LUT 强度") }
                    }
                }
            }
        }
    }

    private var transitionChoices: some View {
        Group {
            Text("硬切").tag(Transition.hardCut)
            Text("交叉叠化").tag(Transition.crossDissolve)
            Text("叠至黑场").tag(Transition.dipToBlack)
        }
    }

    private var selectedClip: TimelineClip? {
        guard let selectedClipID else { return nil }
        return project.timeline.videoTracks.flatMap(\.clips).first { $0.id == selectedClipID }
    }

    private var canvasPresetBinding: Binding<CanvasPreset> {
        Binding(
            get: { project.canvas.preset ?? .custom },
            set: { preset in
                let source = selectedClip.flatMap { clip in
                    project.mediaLibrary.items.first(where: { $0.id == clip.mediaID })?.videoMetadata
                }
                if let canvas = preset.canvas(sourceSize: source) {
                    mutateCanvas(canvas)
                } else if preset == .custom {
                    var canvas = project.canvas
                    canvas.preset = .custom
                    mutateCanvas(canvas)
                }
            }
        )
    }

    private var canvasWidthBinding: Binding<Int> {
        Binding(
            get: { project.canvas.width },
            set: { width in
                var canvas = project.canvas
                canvas.width = width
                canvas.preset = .custom
                mutateCanvas(canvas)
            }
        )
    }

    private var canvasHeightBinding: Binding<Int> {
        Binding(
            get: { project.canvas.height },
            set: { height in
                var canvas = project.canvas
                canvas.height = height
                canvas.preset = .custom
                mutateCanvas(canvas)
            }
        )
    }

    private var masterVolumeBinding: Binding<Double> {
        Binding(
            get: { project.timeline.masterVolume ?? 1 },
            set: { value in
                if timeline.updateMasterVolume(value, in: &project) { onProjectMutation() }
            }
        )
    }

    private var musicVolumeBinding: Binding<Double> {
        musicDoubleBinding(default: 1, name: "调整音乐音量", keyPath: \.volume, set: { track, value in
            track.volume = min(1, max(0, value))
        })
    }

    private var musicFadeInBinding: Binding<Double> {
        musicDoubleBinding(default: 0, name: "调整音乐淡入", keyPath: \.fadeInDuration.seconds, set: { track, value in
            track.fadeInDuration = TimelineTime(seconds: value)
        })
    }

    private var musicFadeOutBinding: Binding<Double> {
        musicDoubleBinding(default: 0, name: "调整音乐淡出", keyPath: \.fadeOutDuration.seconds, set: { track, value in
            track.fadeOutDuration = TimelineTime(seconds: value)
        })
    }

    private var transitionInBinding: Binding<Transition> {
        clipBinding(default: .hardCut, name: "调整入场转场", get: \.transitionIn, set: { $0.transitionIn = $1 })
    }

    private var transitionOutBinding: Binding<Transition> {
        clipBinding(default: .hardCut, name: "调整出场转场", get: \.transitionOut, set: { $0.transitionOut = $1 })
    }

    private var playbackRateBinding: Binding<Double> {
        clipBinding(default: 1, name: "调整剪辑速度", get: \.playbackRate, set: { $0.playbackRate = max(0.25, min(4, $1)) })
    }

    private var originalAudioMutedBinding: Binding<Bool> {
        Binding(
            get: { audioClip?.isMuted ?? false },
            set: { value in mutateAudio("切换原声静音") { $0.isMuted = value } }
        )
    }

    private var originalAudioVolumeBinding: Binding<Double> {
        Binding(
            get: { audioClip?.volume ?? 1 },
            set: { value in mutateAudio("调整原声音量") { $0.volume = min(1, max(0, value)) } }
        )
    }

    private var scaleBinding: Binding<Double> {
        clipBinding(default: 1, name: "调整缩放", get: \.transform.scale, set: { $0.transform.scale = $1 })
    }

    private var positionXBinding: Binding<Double> {
        clipBinding(default: 0, name: "调整水平位置", get: \.transform.positionX, set: { $0.transform.positionX = $1 })
    }

    private var positionYBinding: Binding<Double> {
        clipBinding(default: 0, name: "调整垂直位置", get: \.transform.positionY, set: { $0.transform.positionY = $1 })
    }

    private var rotationBinding: Binding<Double> {
        clipBinding(default: 0, name: "调整旋转", get: \.transform.rotationDegrees, set: { $0.transform.rotationDegrees = $1 })
    }

    private var opacityBinding: Binding<Double> {
        clipBinding(default: 1, name: "调整不透明度", get: \.opacity, set: { $0.opacity = $1 })
    }

    private var contentModeBinding: Binding<ClipContentMode> {
        clipAppearanceBinding(default: .fit, name: "调整填充方式", get: { $0.contentMode }, set: { $0.contentMode = $1 })
    }

    private var cropXBinding: Binding<Double> { cropBinding(name: "调整裁剪左", get: { $0.x }, set: { $0.x = $1 }) }
    private var cropYBinding: Binding<Double> { cropBinding(name: "调整裁剪上", get: { $0.y }, set: { $0.y = $1 }) }
    private var cropWidthBinding: Binding<Double> { cropBinding(name: "调整裁剪宽", get: { $0.width }, set: { $0.width = $1 }) }
    private var cropHeightBinding: Binding<Double> { cropBinding(name: "调整裁剪高", get: { $0.height }, set: { $0.height = $1 }) }

    private var exposureBinding: Binding<Double> { colorBinding(name: "调整曝光", get: { $0.exposure }, set: { $0.exposure = $1 }) }
    private var contrastBinding: Binding<Double> { colorBinding(name: "调整对比度", get: { $0.contrast }, set: { $0.contrast = $1 }) }
    private var saturationBinding: Binding<Double> { colorBinding(name: "调整饱和度", get: { $0.saturation }, set: { $0.saturation = $1 }) }
    private var temperatureBinding: Binding<Double> { colorBinding(name: "调整色温", get: { $0.temperature }, set: { $0.temperature = $1 }) }
    private var tintBinding: Binding<Double> { colorBinding(name: "调整色调", get: { $0.tint }, set: { $0.tint = $1 }) }
    private var highlightsBinding: Binding<Double> { colorBinding(name: "调整高光", get: { $0.highlights }, set: { $0.highlights = $1 }) }
    private var shadowsBinding: Binding<Double> { colorBinding(name: "调整阴影", get: { $0.shadows }, set: { $0.shadows = $1 }) }

    private var lutIntensityBinding: Binding<Double> {
        Binding(
            get: { selectedClip?.appearance?.lut?.intensity ?? 1 },
            set: { value in
                mutateClip("调整 LUT 强度") { clip in
                    guard var appearance = clip.appearance, var lut = appearance.lut else { return }
                    lut.intensity = min(1, max(0, value))
                    appearance.lut = lut
                    clip.appearance = appearance
                }
            }
        )
    }

    private var audioClip: AudioClip? {
        guard let selectedClip else { return nil }
        return project.timeline.audioTracks
            .flatMap(\.clips)
            .first {
                $0.mediaID == selectedClip.mediaID
                    && $0.sourceRange == selectedClip.sourceRange
                    && $0.timelineStart == selectedClip.timelineStart
            }
    }

    private func clipBinding<Value>(
        default fallback: Value,
        name: String,
        get: @escaping (TimelineClip) -> Value,
        set: @escaping (inout TimelineClip, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { selectedClip.map(get) ?? fallback },
            set: { value in mutateClip(name) { set(&$0, value) } }
        )
    }

    private func clipAppearanceBinding<Value>(
        default fallback: Value,
        name: String,
        get: @escaping (ClipAppearance) -> Value,
        set: @escaping (inout ClipAppearance, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { selectedClip.map { get($0.appearance ?? .default) } ?? fallback },
            set: { value in
                mutateClip(name) { clip in
                    var appearance = clip.appearance ?? .default
                    set(&appearance, value)
                    clip.appearance = appearance
                }
            }
        )
    }

    private func cropBinding(
        name: String,
        get: @escaping (ClipCrop) -> Double,
        set: @escaping (inout ClipCrop, Double) -> Void
    ) -> Binding<Double> {
        clipAppearanceBinding(default: get(.fullFrame), name: name, get: { get($0.crop) }, set: { appearance, value in
            set(&appearance.crop, value)
            appearance.crop = appearance.crop.clamped()
        })
    }

    private func colorBinding(
        name: String,
        get: @escaping (ClipColorAdjustments) -> Double,
        set: @escaping (inout ClipColorAdjustments, Double) -> Void
    ) -> Binding<Double> {
        clipAppearanceBinding(default: get(.neutral), name: name, get: { get($0.color) }, set: { appearance, value in
            set(&appearance.color, value)
        })
    }

    private func musicDoubleBinding(
        default fallback: Double,
        name: String,
        keyPath: KeyPath<MusicTrack, Double>? = nil,
        set: ((inout MusicTrack, Double) -> Void)? = nil
    ) -> Binding<Double> {
        Binding(
            get: {
                guard let music = project.timeline.musicTrack else { return fallback }
                return keyPath.map { music[keyPath: $0] } ?? fallback
            },
            set: { value in
                guard let set else { return }
                if timeline.updateMusic(name: name, in: &project, { track in
                    set(&track, value)
                }) {
                    onProjectMutation()
                }
            }
        )
    }

    private func mutateCanvas(_ canvas: CanvasSettings) {
        if timeline.updateCanvas(canvas, in: &project) { onProjectMutation() }
    }

    private func mutateClip(_ name: String, _ mutation: @escaping (inout TimelineClip) -> Void) {
        guard let selectedClipID else { return }
        if timeline.updateClip(id: selectedClipID, name: name, in: &project, mutation) {
            onProjectMutation()
        }
    }

    private func mutateAudio(_ name: String, _ mutation: @escaping (inout AudioClip) -> Void) {
        guard let selectedClipID else { return }
        if timeline.updateAudio(forVideoClipID: selectedClipID, name: name, in: &project, mutation) {
            onProjectMutation()
        }
    }
}

private extension UTType {
    static let cubeLUT = UTType(filenameExtension: "cube") ?? .data
}
