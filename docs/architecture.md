# 架构

BeatWeave 将持久化项目状态、编辑引擎和 SwiftUI 界面严格分开。当前 Phase 0 落地了该边界，后续阶段在不改变项目格式权威性的前提下扩展媒体和时间线功能。

```text
SwiftUI App / DocumentGroup
        │ Binding<BeatWeaveDocument>
        ▼
Document / ProjectPackage
        │ JSON encode/decode
        ▼
Domain ProjectFile ─────► 未来的 Timeline / Beat / Export engines
```

## 持久化原则

- `ProjectFile` 是唯一的可编辑项目状态；其 `projectFormatVersion` 从第一个版本起即写入文件。
- `TimelineTime` 使用整数值和 timescale 编码，避免以 `Double` 作为持久化时间源。
- `project.json` 存储项目模型，而不是 SwiftUI、`AVMutableComposition` 或缓存对象。
- 项目文件是 macOS package。缩略图、波形、分析、代理与自动保存目录可删除和重建，不能成为唯一数据源。
- 外部媒体将仅保存引用和（在后续导入阶段）安全作用域书签，绝不移动或改写源文件。

## 并发与扩展边界

后续 `Services`（媒体解析、缩略图、波形和节拍分析）将在 actor 或受限任务组中进行昂贵 I/O 与解码。SwiftUI view 只发起意图并渲染状态；`AVMutableComposition` 将由规范化的时间线模型生成，不能反向充当持久化模型。

## 当前限制

Phase 0 不处理媒体、缓存写入、播放或渲染，因此没有预先加入未调用的服务单例或 AVFoundation 编辑逻辑。随着相应阶段开始，这些模块会以可测试的实现加入。
