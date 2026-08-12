import SwiftUI

struct AutoCutView: View {
    let media: [MediaReference]
    let beatAnalysis: BeatAnalysis?
    let musicDuration: TimelineTime?
    @Binding var smartMontage: SmartMontageSettings?
    @Bindable var model: AutoCutModel
    let onApply: (AutoCutPlan) -> Void
    let onProjectMutation: () -> Void

    var body: some View {
        GroupBox("AutoCut") {
            if let beatAnalysis, let musicDuration {
                controls(beatAnalysis: beatAnalysis, musicDuration: musicDuration)
            } else {
                ContentUnavailableView(
                    "先完成音乐节拍分析",
                    systemImage: "waveform.path.ecg",
                    description: Text("AutoCut 需要音乐轨及其节拍网格。")
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func controls(beatAnalysis: BeatAnalysis, musicDuration: TimelineTime) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup("视频素材（\(selectedVideoCount)/\(videoMedia.count)）") {
                ForEach(videoMedia) { video in
                    Toggle(video.displayName, isOn: Binding(
                        get: { model.selectedMediaIDs.contains(video.id) },
                        set: { model.setMedia(video.id, isSelected: $0) }
                    ))
                    .lineLimit(1)
                }
            }
            Picker("切点", selection: $model.pattern) {
                ForEach(AutoCutPattern.allCases) { pattern in
                    Text(pattern.displayName).tag(pattern)
                }
            }
            Toggle("按导入顺序", isOn: $model.preservesSourceOrder)
            Toggle("按素材质量自适应排序", isOn: $model.usesSmartMontage)
            Toggle("优先强拍", isOn: $model.prefersStrongBeats)
                .disabled(!model.usesSmartMontage || beatAnalysis.strongBeatTimes.count < 2)
            HStack {
                Button(model.isAnalyzingMedia ? "正在分析…" : "分析所选素材") {
                    Task {
                        smartMontage = await model.analyzeSelectedMedia(media: media, smartMontage: smartMontage)
                        onProjectMutation()
                    }
                }
                .disabled(model.isAnalyzingMedia || selectedVideoCount == 0)
                if let smartMontage {
                    Text("已分析 \(smartMontage.analyses.count) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let error = model.analysisErrorMessage {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            DisclosureGroup("智能素材偏好") {
                ForEach(videoMedia) { video in
                    Picker(video.displayName, selection: decisionBinding(for: video.id)) {
                        ForEach(SmartMediaDecision.allCases) { decision in
                            Text(decision.displayName).tag(decision)
                        }
                    }
                    .pickerStyle(.menu)
                    .lineLimit(1)
                }
            }
            HStack {
                Text("最短")
                TextField("秒", value: $model.minimumDuration, format: .number.precision(.fractionLength(1)))
                    .frame(width: 58)
                Text("最长")
                TextField("秒", value: $model.maximumDuration, format: .number.precision(.fractionLength(1)))
                    .frame(width: 58)
            }
            HStack {
                Text("音乐范围")
                TextField("起点", value: $model.targetStart, format: .number.precision(.fractionLength(1)))
                    .frame(width: 58)
                Text("至")
                TextField("终点", value: $model.targetEnd, format: .number.precision(.fractionLength(1)))
                    .frame(width: 58)
                Text("/ \(musicDuration.seconds, format: .number.precision(.fractionLength(1))) 秒")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Button("预览 AutoCut 计划") {
                model.preparePlan(media: media, beatAnalysis: beatAnalysis, musicDuration: musicDuration, smartMontage: smartMontage)
            }
            .disabled(selectedVideoCount == 0 || model.minimumDuration <= 0 || model.maximumDuration < model.minimumDuration)
            if let plan = model.plan {
                planSummary(plan)
            }
        }
        .textFieldStyle(.roundedBorder)
        .onAppear {
            if model.selectedMediaIDs.isEmpty {
                model.selectAllVideos(in: media)
            }
            if model.targetEnd == 0 {
                model.targetEnd = musicDuration.seconds
            }
        }
    }

    private var videoMedia: [MediaReference] {
        media.filter { $0.kind == .video }
    }

    private var selectedVideoCount: Int {
        videoMedia.count { model.selectedMediaIDs.contains($0.id) }
    }

    private func decisionBinding(for mediaID: UUID) -> Binding<SmartMediaDecision> {
        Binding(
            get: { smartMontage?.decisions[mediaID] ?? .included },
            set: { decision in
                var settings = smartMontage ?? SmartMontageSettings()
                settings.decisions[mediaID] = decision
                smartMontage = settings
                onProjectMutation()
            }
        )
    }

    private func planSummary(_ plan: AutoCutPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("计划摘要")
                .font(.subheadline.weight(.semibold))
            Text("\(plan.placements.count) 个剪辑 · \(plan.diagnostics.plannedDuration.seconds, format: .number.precision(.fractionLength(2))) / \(plan.diagnostics.targetDuration.seconds, format: .number.precision(.fractionLength(2))) 秒")
                .font(.caption)
            Text("未使用 \(plan.unusedMediaIDs.count) 个素材 · \(plan.diagnostics.beatBoundaryCount) 个节拍边界")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(plan.diagnostics.messages, id: \.self) { message in
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("放弃") {
                    model.clearPlan()
                }
                Button("应用到时间线") {
                    onApply(plan)
                    model.clearPlan()
                }
                .disabled(plan.placements.isEmpty)
            }
        }
    }
}
