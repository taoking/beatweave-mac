# BeatWeave for macOS

BeatWeave 是一款原生 macOS 视频编辑器，专注于本地音乐节拍分析、可编辑的节拍切点和自动卡点剪辑。项目不修改原始媒体，也不依赖云端账户或 AI 服务。

当前处于 Phase 6，BeatWeave MVP 已完成：可将可编辑时间线本地导出为 H.264 或 HEVC MP4，支持分辨率、帧率、质量、原始音频与音乐混音、后台进度、取消和访达定位。导出基于同一份持久化时间线模型，最终文件仅在完整导出成功后写入。

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

除 `project.json` 外的目录均为可再生缓存或恢复空间；`waveforms/` 当前保存独立波形缓存，删除后可以由源媒体重新生成。

## 已知限制

- 缩略图当前只保留在内存中。
- 媒体预览是单个源文件预览，尚不是项目时间线播放。
- 节拍算法已由合成点击音频和信号处理单元测试覆盖；不同音乐风格、长音频滚动和真实素材的 GUI 验收仍需要授权测试素材。
- 时间线操作与撤销/重做由领域测试覆盖；真实素材上的拖放手势、完整手工蒙太奇和项目时间线播放仍需人工验收。
- AutoCut 计划、固定随机、异常素材与一次性撤销由单元测试覆盖；真实音乐与视频素材的完整 AutoCut→预览→撤销 GUI 流程仍需人工验收。
- 导出管线由临时 H.264/HEVC 视频、音乐音频轨、时间线时长和输出尺寸的端到端测试覆盖；真实素材的 QuickTime 打开、长视频音画同步、取消和访达操作仍需人工验收。
- 没有随仓库分发视频测试素材；提交前请使用可再分发的 H.264、HEVC 与音频样本进行手工验收。

## 文档

- [开发计划](BEATWEAVE_MAC_PLAN.md)
- [实施状态](plan.md)
- [架构说明](docs/architecture.md)
- [变更记录](CHANGELOG.md)

## 许可证

本项目采用 [MIT License](LICENSE)。
