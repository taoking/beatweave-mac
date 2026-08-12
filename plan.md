# BeatWeave 实施跟踪

权威产品与技术规格位于 [BEATWEAVE_MAC_PLAN.md](BEATWEAVE_MAC_PLAN.md)。本文件记录实际交付状态，避免将计划中的未来能力误认为已经实现。

| 阶段 | 状态 | 交付范围 |
| --- | --- | --- |
| Phase 0 — Repository and foundation | 已完成 | 原生 macOS 文档应用、版本化 `.beatweave` 包、基础测试、CI 与文档 |
| Phase 1 — Media import and viewer | 未开始 | 媒体导入、元数据、缩略图、预览 |
| Phase 2 — Music + waveform | 未开始 | 音乐轨道、PCM 与波形缓存 |
| Phase 3 — Beat detection | 未开始 | 本地节拍分析 |
| Phase 4 — Real timeline editor | 未开始 | 可编辑时间线与撤销 |
| Phase 5 — AutoCut MVP | 未开始 | 节拍同步自动剪辑 |
| Phase 6 — Export | 未开始 | 本地视频导出 |

不在完成标记前宣称对应功能可用。每阶段完成后记录构建、测试和人工验证情况。

## Phase 0 验证（2026-08-13）

- `xcodegen generate`：成功生成 `BeatWeave.xcodeproj`。
- `xcodebuild ... test CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=26.5`：8 个测试全部通过。
- 手动 UI：启动、新建项目、项目名编辑和 `.beatweave` 保存面板均已检查；为避免在用户 Documents 留下测试项目，保存面板已取消。
- 风险：项目配置按产品规格使用 macOS 27.0；本机 Xcode 26.6 仅带 macOS 26.5 SDK，默认构建会报告不支持 27.0 部署目标的环境警告。为执行本地测试而临时覆盖为 26.5，不能替代 macOS 27 SDK 上的最终构建验证。
