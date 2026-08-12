# BeatWeave 实施跟踪

权威产品与技术规格位于 [BEATWEAVE_MAC_PLAN.md](BEATWEAVE_MAC_PLAN.md)。本文件记录实际交付状态，避免将计划中的未来能力误认为已经实现。

| 阶段 | 状态 | 交付范围 |
| --- | --- | --- |
| Phase 0 — Repository and foundation | 已完成 | 原生 macOS 文档应用、版本化 `.beatweave` 包、基础测试、CI 与文档 |
| Phase 1 — Media import and viewer | 已完成 | 媒体导入、元数据、缩略图、预览、缺失媒体重连 |
| Phase 2 — Music + waveform | 已完成 | 音乐轨道、PCM、多层波形缓存、波形视图与播放头同步 |
| Phase 3 — Beat detection | 已完成 | 本地节拍分析、BPM、网格与手动校正 |
| Phase 4 — Real timeline editor | 已完成 | 可编辑时间线、吸附与撤销 |
| Phase 5 — AutoCut MVP | 进行中 | 节拍同步自动剪辑 |
| Phase 6 — Export | 未开始 | 本地视频导出 |

不在完成标记前宣称对应功能可用。每阶段完成后记录构建、测试和人工验证情况。

## Phase 0 验证（2026-08-13）

- `xcodegen generate`：成功生成 `BeatWeave.xcodeproj`。
- `xcodebuild ... test CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=26.5`：8 个测试全部通过。
- 手动 UI：启动、新建项目、项目名编辑和 `.beatweave` 保存面板均已检查；为避免在用户 Documents 留下测试项目，保存面板已取消。
- 风险：项目配置按产品规格使用 macOS 27.0；本机 Xcode 26.6 仅带 macOS 26.5 SDK，默认构建会报告不支持 27.0 部署目标的环境警告。为执行本地测试而临时覆盖为 26.5，不能替代 macOS 27 SDK 上的最终构建验证。

## Phase 1 验证（2026-08-13）

- 单元测试以临时生成的 WAV 验证 `MediaImportService` 读取音频名称、种类、时长和安全书签；同时覆盖来源状态与媒体库的添加、重连、删除依赖项。
- 手动 UI：已用临时生成的 M4A 文件通过文件选择器导入，看到音频、2.54 秒时长和“媒体源可用”状态；AVPlayer 控件与播放按钮均出现。
- 未验证：仓库内没有可重新分发的 1080p/4K H.264、4K HEVC 样本，因此该三类视频的导入与画面预览仍需在具备授权素材的环境中手工验收。

## Phase 2 验证（2026-08-13）

- `WaveformServiceTests` 使用临时生成 WAV，验证 `AVAssetReader` PCM 解码会得到三个多分辨率波形层及非零峰值。
- `ProjectPackageTests` 验证波形缓存保存在 `.beatweave/waveforms/` 中，并随项目包读取恢复。
- `xcodebuild test` 共执行 15 项测试，0 失败；已手工检查空项目会显示 M1 波形区域、缩放控件及“选择音乐轨道”提示。
- 未验证：长音频文件的滚动性能和保存后经 GUI 重新打开的波形显示仍需以授权的真实音乐素材进行手工验收。

## Phase 3 验证（2026-08-13）

- `BeatAnalysisDSPTests` 覆盖起音峰值选择、120 BPM 估计、稳定网格、手动 BPM 与 Tap Tempo；`BeatAnalysisServiceTests` 用 8 秒、120 BPM 合成点击 WAV 验证完整 AVAssetReader/vDSP 管线。
- `ProjectPackageTests` 验证 BPM、起音和节拍标记经项目包重开后完全一致；`ProjectCodecTests` 验证旧版 `BeatAnalysis` 缺少新增字段时仍以安全默认值读取。
- 未验证：EDM、流行、摇滚、嘻哈、影视/原声、原声乐器、前导静音与半/双拍歧义等真实音乐集的算法效果，以及真实素材上节拍叠加控件的 GUI 操作，仍需授权测试素材人工验收。

## Phase 4 验证（2026-08-13）

- `TimelineEngineTests` 覆盖追加与节拍吸附、插入时分割并波纹后移、移动重排、两端裁剪、分割、波纹删除、播放头优先吸附与撤销/重做快照。
- 时间线视图支持视频/剪辑拖放、缩放、播放头点击定位、吸附开关以及上述编辑命令；所有时间线状态修改均通过命令层，可撤销/重做。
- 未验证：使用真实视频素材拖放并完成一段手工节拍蒙太奇、时间线级预览播放以及键盘快捷键的端到端 GUI 验收，仍需授权素材人工验收。
