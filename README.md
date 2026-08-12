# BeatWeave for macOS

BeatWeave 是一款原生 macOS 视频编辑器，专注于本地音乐节拍分析、可编辑的节拍切点和自动卡点剪辑。项目不修改原始媒体，也不依赖云端账户或 AI 服务。

当前处于 Phase 1：除版本化 `.beatweave` 项目包外，已支持 Finder 拖入或文件选择器导入媒体、读取基础元数据、生成内存缩略图、检查/重新链接丢失源文件，并用 AVPlayer 预览单个媒体。时间线、波形、节拍分析与导出尚未实现。

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

除 `project.json` 外的目录均为可再生缓存或恢复空间；当前基础版本只创建目录，不写入媒体或缓存。

## 已知限制

- 缩略图当前只保留在内存中，持久化缓存随波形阶段一起加入。
- 媒体预览是单个源文件预览，尚不是项目时间线播放。
- 没有随仓库分发视频测试素材；提交前请使用可再分发的 H.264、HEVC 与音频样本进行手工验收。

## 文档

- [开发计划](BEATWEAVE_MAC_PLAN.md)
- [实施状态](plan.md)
- [架构说明](docs/architecture.md)
- [变更记录](CHANGELOG.md)

## 许可证

本项目采用 [MIT License](LICENSE)。
