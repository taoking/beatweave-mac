# BeatWeave 实施跟踪

权威产品与技术规格位于 [BEATWEAVE_MAC_PLAN.md](BEATWEAVE_MAC_PLAN.md)。本文件记录实际交付状态，避免将计划中的未来能力误认为已经实现。

| 阶段 | 状态 | 交付范围 |
| --- | --- | --- |
| Phase 0 — Repository and foundation | 已完成 | 原生 macOS 文档应用、版本化 `.beatweave` 包、基础测试、CI 与文档 |
| Phase 1 — Media import and viewer | 已完成 | 媒体导入、元数据、缩略图、预览、缺失媒体重连 |
| Phase 2 — Music + waveform | 已完成 | 音乐轨道、PCM、多层波形缓存、波形视图与播放头同步 |
| Phase 3 — Beat detection | 已完成 | 本地节拍分析、BPM、网格与手动校正 |
| Phase 4 — Real timeline editor | 已完成 | 可编辑时间线、吸附与撤销 |
| Phase 5 — AutoCut MVP | 已完成 | 节拍同步计划、预览与一次性应用 |
| Phase 6 — Export | 已完成 | 本地 H.264/HEVC 导出与后台任务状态 |
| Phase 7 — Editing quality | 已完成 | 转场、画布、音频、基础调色、`.cube` LUT 与项目时间线预览 |
| Phase 8 — Smart montage | 已完成 | 素材质量分析与自适应 AutoCut |
| Phase 9 — Performance and professional workflow | 已完成 | 代理、恢复、诊断、多轨与高级工作流 |

## 启动稳定性与默认项目（2026-08-21）

- 已移除 macOS 27 beta 上会在启动时触发尺寸约束崩溃的嵌套 SwiftUI 分栏容器，改用稳定的三栏编辑布局。
- 启动现在直接打开并持久化默认项目；默认保存在应用安全存储中，用户可在“项目工作流”中选择并记忆任意默认项目目录。
- `DEVELOPER_DIR=/Users/tao/Downloads/Xcode-beta.app/Contents/Developer xcodebuild ... test CODE_SIGNING_ALLOWED=NO`：61 项测试通过（新增默认项目创建、写回与重开测试）。
- `DEVELOPER_DIR=/Users/tao/Downloads/Xcode-beta.app/Contents/Developer xcodebuild ... -configuration Release build CODE_SIGNING_ALLOWED=NO`：成功，产物为 macOS 27 arm64 app；本机启动后持续运行 8 秒，未生成新的崩溃报告。自动 GUI 驱动当前无法取得任何系统窗口，主界面仍需用户手动验收。

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
- 已实现：预览来源菜单可切换到“播放项目时间线”；它使用和导出相同的时间线合成状态，播放头与时间线同步。切回媒体预览或停止播放会清理预览调色产生的临时文件。
- 未验证：使用真实视频素材拖放并完成一段手工节拍蒙太奇、时间线级预览播放以及键盘快捷键的端到端 GUI 验收，仍需授权素材人工验收。

## Phase 5 验证（2026-08-13）

- `AutoCutEngineTests` 覆盖每 4 拍的节拍对齐与源顺序、固定种子的确定性打乱、无法填充的短素材诊断，以及将完整计划作为一条命令应用并撤销/重做。
- 界面允许选择视频素材、每 1/2/4/8 拍、按顺序或打乱、最短/最长片段和目标音乐范围；生成计划只显示摘要，用户确认“应用到时间线”后才改动项目。
- 未验证：20 个真实视频素材配合真实音乐的 AutoCut→时间线预览→撤销→再次 AutoCut 的端到端 GUI 验收，仍需授权素材人工验收。

## Phase 6 验证（2026-08-13）

- `ExportTimelinePlannerTests` 验证导出时序直接来自规范化时间线、剪辑速率影响最终时长、缺失媒体、同轨重叠和多轨层级均会得到正确计划。
- `ExportServiceTests` 生成临时 H.264 视频和 WAV 音乐，实际导出可被 AVFoundation 重新打开的 H.264 MP4（含视频/音频轨、1 秒时长、64×64 尺寸）和 HEVC MP4；同时验证不会覆盖任何已有最终文件。
- 导出先写唯一临时 MP4，只有成功后才移动到最终路径；取消按钮会取消活动 `AVAssetExportSession`，失败或取消均由 `defer` 清理临时文件。
- 未验证：真实 H.264/HEVC/4K 长素材在 QuickTime 中打开、长片段音画同步、用户取消时的端到端 GUI 操作和访达定位，仍需授权素材人工验收。

## Phase 7 验证（2026-08-13）

- 已实现：可撤销的画布预设（16:9、9:16、1:1、4:5、源比例和自定义），并在更换画布时同步导出尺寸；剪辑检查器可设置速度、入/出场转场、适应/填充、缩放、位置、旋转、裁剪与不透明度；音频支持原声静音、原声音量、主音量、音乐音量和淡入淡出。
- 导出已使用同一份时间线状态执行画布尺寸、适应/填充、裁剪、透明度渐变、原声静音/音量和音乐淡入淡出；`EditingControlsTests` 覆盖旧项目兼容性、检查器命令的撤销/重做以及主音量规范化。
- 已实现：基础调色与 `.cube` LUT 在每个剪辑进入多轨合成前以 Core Image 渲染为私有临时 MP4，保证不会与 AVFoundation 的多指令图混用；预览和导出均使用这一合成路径。`LUTCubeTests` 覆盖解析、强度插值和无效文件；`ExportServiceTests` 实际读取导出帧，验证饱和度、LUT、同轨重叠式交叉叠化及高视频轨覆盖低视频轨。
- 已实现：预览来源菜单的“播放项目时间线”复用导出合成器，因此画布、剪辑速率、构图、转场、音频混合、调色和 LUT 状态与导出一致；切换来源或停止时会释放安全作用域和临时调色视频。
- 未验证：仓库不含可再分发的真实 LUT 或长视频素材，因此复杂 LUT、不同相机素材和完整 GUI 编辑工作流仍需在拥有授权素材的环境人工验收。

## Phase 8 验证（2026-08-13）

- 已实现：后台对所选视频稀疏抽取三帧，以分辨率/帧率估计画面质量、亮度差估计运动、Vision 人脸检测估计人物信号，并将总分及分段得分作为可选项目元数据保存。
- 自适应 AutoCut 只在用户开启时生效，支持素材参与/排除/固定优先、质量排序、强拍切点和在同一长素材中顺序使用不同源区间以降低重复画面；关闭后仍使用原有确定性 AutoCut。
- `SmartMontageTests` 覆盖排除与固定优先、不同源区间和强拍网格；真实视频的分析质量、实际 UI 操作以及面部/运动场景排序尚未手工验证。这是外部测试素材限制，而非未实现功能。

## Phase 9 验证（2026-08-13）

- 已实现：项目包内持久化缩略图与 H.264 预览代理；预览仅在可用时读取代理，导出始终解析原始媒体。删除代理只清理可再生缓存，不会破坏项目。
- 缩略图与代理共享串行后台生成队列；时间线只创建带一秒缓冲的当前可见剪辑视图，支持垂直滚动的多视频/音频轨、Command 多选、批量删除、批量移轨和把音频拖放到指定音轨。
- 已实现：交付预设（Web 1080p、社媒竖屏、4K HEVC 母版）、可持久化的撤销/重做/分割快捷键、只读项目诊断，以及主 `project.json` 不可读时从上一份可读项目快照恢复。
- `ProjectPackageTests` 覆盖缓存往返和恢复快照；`TimelineEngineTests` 覆盖多选命令、指定音轨插入音频；`ExportTimelinePlannerTests` 覆盖交付预设。`xcodebuild ... test CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=26.5` 共执行 60 项测试，0 失败。
- 未验证：规格要求的 20/100/500 剪辑、4K HEVC、30 分钟项目及真实长音乐的性能测量与 GUI 操作；当前实现避免视口外剪辑视图创建，但不能将其替代为真实性能基准。
