# BeatWeave for macOS

BeatWeave 是一款原生 macOS 视频编辑器，专注于本地音乐节拍分析、可编辑的节拍切点和自动卡点剪辑。项目不修改原始媒体，也不依赖云端账户或 AI 服务。

Phase 9 的工作流能力已完成：项目会持久化缩略图和可再生预览代理，时间线支持多轨、多选、交付预设、快捷键定制、诊断和恢复快照。Phase 7 的逐剪辑调色/LUT 像素渲染与真正的同轨交叉叠化，以及 Phase 8 的真实素材验收，仍明确处于未完成状态。

## 要求

- macOS 27 或更高版本
- 含 macOS 27 SDK 的 Xcode（含 Swift 6）
- XcodeGen 2.45 或更高版本

## 构建与测试

```sh
xcodegen generate
xcodebuild -project BeatWeave.xcodeproj -scheme BeatWeave -configuration Debug build
xcodebuild -project BeatWeave.xcodeproj -scheme BeatWeave -configuration Debug test
```

本地开发机若只有 macOS 26.5 SDK，可临时追加 `MACOSX_DEPLOYMENT_TARGET=26.5` 来运行基础测试；这仅用于验证代码，发布构建仍须使用支持 macOS 27 的 SDK。

打开 `BeatWeave.xcodeproj` 后运行 `BeatWeave` scheme。通过“新建”创建项目；文档会以 `.beatweave` 包保存，其中 `project.json` 是唯一权威的持久化编辑状态。

## 项目包

```text
MyVideo.beatweave/
├── project.json
├── thumbnails/
├── waveforms/
├── analysis/
├── proxies/
└── autosave/
```

`thumbnails/`、`waveforms/` 和 `proxies/` 都是可再生缓存；代理只用于预览，导出始终读取原始媒体。`autosave/last-known-good.json` 在后续保存时保留前一份可读项目状态，主文件损坏时会用于恢复。

## 已知限制

- 媒体预览是单个源文件预览，尚不是项目时间线播放。
- 节拍算法已由合成点击音频和信号处理单元测试覆盖；不同音乐风格、长音频滚动和真实素材的 GUI 验收仍需要授权测试素材。
- 时间线操作与撤销/重做由领域测试覆盖；真实素材上的拖放手势、完整手工蒙太奇和项目时间线播放仍需人工验收。
- AutoCut 计划、固定随机、异常素材与一次性撤销由单元测试覆盖；真实音乐与视频素材的完整 AutoCut→预览→撤销 GUI 流程仍需人工验收。
- 质量分析仅稀疏抽取三个画面，旨在供自动剪辑排序参考，不能替代人工素材审阅；真实人脸、运动和复杂场景的排序质量仍需授权素材验收。
- 导出管线由临时 H.264/HEVC 视频、音乐音频轨、时间线时长和输出尺寸的端到端测试覆盖；真实素材的 QuickTime 打开、长视频音画同步、取消和访达操作仍需人工验收。
- 交叉叠化目前以相邻剪辑的透明度渐变实现；同轨真实重叠式交叉叠化、逐剪辑调色和 LUT 像素渲染尚未完成，不能将选择器状态视为已验证的画面输出。
- 多轨、多选、代理和恢复快照已有自动化回归覆盖；20/100/500 剪辑、4K HEVC、30 分钟项目和真实长音乐的性能测量，以及完整 GUI 操作，仍需以授权素材人工验收。
- 没有随仓库分发视频测试素材；提交前请使用可再分发的 H.264、HEVC 与音频样本进行手工验收。

## 文档

- [开发计划](BEATWEAVE_MAC_PLAN.md)
- [实施状态](plan.md)
- [架构说明](docs/architecture.md)
- [变更记录](CHANGELOG.md)

## 许可证

本项目采用 [MIT License](LICENSE)。
