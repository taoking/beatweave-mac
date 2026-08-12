# 架构

BeatWeave 将持久化项目状态、编辑引擎和 SwiftUI 界面严格分开。当前 Phase 0 落地了该边界，后续阶段在不改变项目格式权威性的前提下扩展媒体和时间线功能。

```text
SwiftUI App / DocumentGroup
        │ Binding<BeatWeaveDocument>
        ▼
Domain ProjectFile ◄──── MediaLibraryEditor
        │                 ▲
        │                 │ MediaReference + metadata
        ▼                 │
Document / ProjectPackage │
        │                 │
        ▼                 │
project.json       MediaImportService / ThumbnailService / PlaybackService
```

## 持久化原则

- `ProjectFile` 是唯一的可编辑项目状态；其 `projectFormatVersion` 从第一个版本起即写入文件。
- `TimelineTime` 使用整数值和 timescale 编码，避免以 `Double` 作为持久化时间源。
- `project.json` 存储项目模型，而不是 SwiftUI、`AVMutableComposition` 或缓存对象。
- 项目文件是 macOS package。缩略图、波形、分析、代理与自动保存目录可删除和重建，不能成为唯一数据源。
- 外部媒体将仅保存引用和（在后续导入阶段）安全作用域书签，绝不移动或改写源文件。

## 并发与扩展边界

`MediaImportService`、`MediaSourceResolver`、`ThumbnailService` 与 `WaveformService` 是 actor，因而不会在 SwiftUI 主路径解析媒体或生成图像。`WaveformService` 使用 `AVAssetReader` 以单声道 Float PCM 生成 512、2,048 和 8,192 桶的峰值/RMS 缓存。`PlaybackService` 则是 MainActor 隔离的 AVPlayer 所有者，只管理播放界面状态。缩略图故障被记录在 `ThumbnailStore`，但不会阻断媒体的导入和预览。SwiftUI view 只发起意图并渲染状态；`AVMutableComposition` 将由规范化的时间线模型生成，不能反向充当持久化模型。

## 当前限制

当前媒体阶段使用内存缩略图；波形缓存存放在项目包的 `waveforms/` 目录、读取错误只会记录并跳过该缓存，绝不会阻止项目打开。节拍分析、时间线和渲染服务会在对应阶段以可测试实现加入，而不是提前放入未调用的占位代码。
