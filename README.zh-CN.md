# SwiftUIIntelligence ![](https://img.shields.io/badge/A%20FRAD%20PRODUCT-WIP-yellow)

[![Twitter Follow](https://img.shields.io/twitter/follow/FradSer?style=social)](https://twitter.com/FradSer)
[![Swift](https://img.shields.io/badge/Swift-6.2-F05138)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20iPadOS%20%7C%20macOS-lightgrey)](https://developer.apple.com)

[English](README.md) | **简体中文**

一个把对话变成原生文档的 SwiftUI Package。

用户提出请求。模型起草内容。Package 把草稿转换为受约束的文档 JSON，校验 JSON，再用预编译的原生
SwiftUI 组件渲染。后续消息修订同一份文档。

仓库为私有，未提供 license 文件，也未公开发布。

## 工作原理

1. 宿主收集对话。
2. Provider 起草文档内容。
3. Package 按严格契约校验 JSON。
4. Package 用组件库渲染文档。

本库不生成 Swift 代码，不求值表达式，不执行动态代码。每个组件都是预编译的。模型只选择布局、组件类型和内容。
Package 与业务无关：没有天气、金融或任务模板。

## 功能

- **对话到文档。** `DocumentChatSession` 保存消息、选择 provider，并且只在完整校验通过后提交文档。
  生成失败时保留上一份有效文档。
- **严格契约。** 一份 Draft 2020-12 JSON Schema，加上解码时的同一组检查。检查覆盖未知字段、未知组件类型、
  动作白名单、唯一 ID、大小、深度和表格形状。
- **原生渲染。** 18 种组件类型、语义化 SF Symbols 白名单，以及原生 Swift Charts。不生成 SwiftUI 代码。
- **类型化 state。** 原生控件编辑类型化的 `DocumentState`。与 Schema 兼容的用户编辑在重载和导航后保留。
- **宿主动作。** 只有宿主注册了精确 ID，按钮才会调用宿主闭包。回调收到唯一事件 ID 和类型化 state 快照。
- **三种 provider。** Apple 本机模型、已有 chatbot 管线，或宿主自有的 HTTPS 后端。所有 provider 都经过同一套最终校验。

## 环境要求

- iOS/iPadOS 26 或更高版本，或 macOS 26 或更高版本。
- Swift 6.2 或更高版本。
- 本轮验证使用 Xcode 27.0（27A266a）。

## 产品

| Product | 用途 |
|---|---|
| `SwiftUIIntelligence` | 文档模型、JSON Schema 与 prompt 契约、provider 协议、聊天会话、严格校验、原生渲染器、Liquid Glass 外观、宿主动作注册 |
| `SwiftUIIntelligenceFoundationModels` | 可选的 Apple 本机适配器。不需要 API key。使用 `@Generable` 内容与意图生成，以及 `GenerationSchema` 文档生成 |
| `SwiftUIIntelligenceWeatherDemo` | 天气参考回放、原仪表盘，以及到通用节点的类型化转换 |
| `SwiftUIIntelligenceModelProbe` | 同机 macOS 的真实模型验收工具。只使用源码中的合成聊天内容 |

## 集成

在 Xcode 中把本目录添加为本地 Swift Package，然后选择 `SwiftUIIntelligence` product。
需要 Apple 本机生成时，再添加 `SwiftUIIntelligenceFoundationModels`。

其他 Package 可以用路径引用本仓库：

```swift
.package(name: "SwiftUIIntelligence", path: "../SwiftUIIntelligence")
```

独立的 [MinimalHost](Example/MinimalHost/Package.swift) 只使用导出的 API 编译。
未提供远程 Package URL 或版本 tag。

## 快速开始

```swift
import SwiftUIIntelligence
import SwiftUIIntelligenceFoundationModels
import SwiftUI

struct HostView: View {
  var body: some View {
    NavigationStack {
      OnDeviceGeneratedView(actions: ActionRegistry(async: [
        "submit": { event in
          // 这次注册只授权一项宿主能力。
          // 只有用户点击按钮时，类型化 state 才会进入这个闭包。
          "Received \(event.state.count) fields."
        }
      ]))
    }
  }
}
```

`OnDeviceGeneratedView` 自带库内输入框。`NavigationStack` 由宿主拥有；嵌入视图不会创建第二个根视图。
Package 在运行时检查模型可用性。Apple Intelligence 不可用时，视图报告错误，不静默回退到云端服务。

## 聊天会话

宿主已有输入框时使用 `DocumentChatSession`。

```swift
let chat = DocumentChatSession(
  provider: FoundationModelsDocumentProvider(),
  registeredActions: ["acknowledge"],
  timeout: .seconds(300)
)
await chat.send("为虚构的笔记 App 写一份简短交接文档。")
// 状态为 ready 时，用 SwiftUIIntelligenceView(document:actions:state:) 渲染 chat.document。
await chat.send("添加一节，描述待完成的导出验证。")
```

会话有四个状态：`idle`、`generating`、`ready`、`failed`。失败会给出类型：`input`、`provider` 或 `invalidDocument`。

- `retry()` 重试同一个请求，不重复追加用户消息。
- `reset()` 清空历史，并丢弃迟到结果。
- `cancel()` 取消所属 Task，并使迟到结果失效。
- `timeout` 默认 300 秒。用 `timeout: nil` 关闭。超时使迟到结果失效，但无法终止忽略取消的 provider。
- `StreamingDocumentGenerationProvider` 提供累积快照。会话报告快照数量和大小，并且只提交最终通过校验的文档。

每份文档保留一个 `DocumentState`。`load(document, preservingEdits: false)` 重置默认值。
本地编辑不进入 prompt，也不进入 trace 日志。副作用、敏感数据、权限检查和幂等性由宿主负责。

已有 JSON 不需要会话：

```swift
SwiftUIIntelligenceView(data: jsonData, actions: registry)   // 解码并渲染已有 JSON
SwiftUIIntelligenceView(document: document, actions: registry, embedded: true)
```

宿主拥有外层滚动视图时设置 `embedded: true`。顶层非嵌入视图显示浮动动作和回调结果。

## 文档契约

`DocumentGenerationContract.schemaJSON(registeredActions:)` 返回 Draft 2020-12 Schema。
`DocumentGenerationContract.instructions` 返回模型约束。Foundation Models 适配器把同一份 Schema 转换为
`DynamicGenerationSchema` 和 `GenerationSchema`。

| 限制 | 数值 |
|---|---|
| JSON 大小 | 64 KiB |
| 节点数 | 128 |
| 深度 | 12 层 |
| 单个布局的子节点 | 32 |
| 布局间距 | 0-48 points |
| 单节点文本 | 4000 字符 |
| 列表 | 1-32 项，每项 1000 字符 |
| 表格 | 1-6 列，1-32 行矩形数据 |
| state 字段 | 32 |
| 浮动按钮 | 3 |
| 会话 | 24 条消息，48 KiB |

节点 ID 为 1-64 个 ASCII 字母、数字、`.`、`_` 或 `-`，并且在文档中唯一。
会话达到限制时请开启新会话；Package 不截断上下文。

## 组件与数据

权威列表是 `ComponentCatalog.components`（`UINode.Kind.allCases`）：
`vstack`、`hstack`、`grid`、`text`、`button`、`section`、`list`、`table`、`callout`、`metric`、
`iconList`、`badge`、`progress`、`chart`、`form`、`control`、`navigationLink`、`timeline`。

- **图表。** 支持多序列折线、面积、柱状、环形和雷达。最多 32 个点、4 个序列，每个序列标签唯一。
  环形使用单个非负序列，总和大于 0。雷达使用单个序列，3-8 个轴，取值 0 到 100。
  折线、面积和柱状可选中横轴查看值；环形显示数值图例；雷达提供完整的 VoiceOver 值。
- **控件。** `textField`、`textEditor`、`toggle`、`picker`、`slider`、`stepper` 和 `datePicker`。
  控件声明类型化绑定。choice 控件带有选项。日期值为 ISO 8601 时刻。
- **导航。** `navigationLink` 指向已存在的 section ID。`NavigationStack` 由宿主提供。
  一次原生生成请求限定为一条一级路由。
- **图标。** `SymbolCatalog.keys` 提供 64 个语义键，覆盖信息与状态、任务与日历、人物、设备与安全、
  商业、自然与天气。JSON 使用 `people` 或 `rain` 这类语义键，从不直接写任意 SF Symbol 名称。
  未知但格式合法的键渲染为 `questionmark.circle`。非法键或 URL 被拒绝。

示例文档：

```json
{"version":1,"root":{"id":"count","type":"metric","label":"Volunteers","value":"12 people","detail":"Registered","icon":"people"},"floatingActions":[]}
```

正文是普通文本。渲染器不执行 HTML、Markdown 或表达式。表格横向滚动；窄屏 `hstack` 可回退竖排。

## Provider

**Apple 本机。** `FoundationModelsDocumentProvider` 使用官方 `SystemLanguageModel.default` API，不需要
API key。适配器先规划内容分组，再用各自受约束的会话生成每个分组，并把模型节点不改写地合并到通用容器中。
它不是一次模型响应。生成失败返回错误并保留上一份有效文档。Token 预算为：内容规划 2600、旧丰富组件分组 1100、
通用直接生成 2400，位于模型 4096 token 上下文内。

**已有 chatbot。** 适配当前管线，不要调用第二个模型。

```swift
let provider = ChatResponseProvider { request in
  // 把 request.instructions、request.schemaJSON 和 request.messages 传给当前管线。
  // 返回助手文档 JSON。
  try await existingChatbot.generateDocument(request)
}
let chat = DocumentChatSession(provider: provider, registeredActions: ["acknowledge"])
```

`existingChatbot` 是宿主自己接口的占位，不是本库的隐藏服务。

**宿主自有 HTTPS 后端。** `HTTPDocumentProvider(endpoint:)` 发送 `{messages, instructions, schema}`，
并期望后端返回完整文档，类型为 `application/json`。端点必须使用 HTTPS，且不能内嵌凭证。
该 provider 最多读取 64 KiB，超时 45 秒。模型凭证保留在服务端。

示例首选 Apple 生成，没有配置或调用第三方服务。不要把模型密钥放入客户端或源码。

生成和渲染使用同一个动作白名单：

```swift
let registry = ActionRegistry(["acknowledge": { "Acknowledged by host" }])
let chat = DocumentChatSession(provider: provider, registeredActions: registry.names)
// 在 SwiftUI body 中，chat.document 存在后：
// SwiftUIIntelligenceView(document: document, actions: registry)
```

## 原生外观

原生控件、`Form`、`Section` 和导航保留 SwiftUI 自动外观。自定义内容卡片通过
`SwiftUIIntelligenceSurface` 使用默认 regular Liquid Glass，并由默认 `GlassEffectContainer` 分组。
Package 不添加玻璃 tint、壁纸、额外边框或阴影、rim，或内部装饰衬线。

卡片形状为 `ConcentricRectangle(corners: .concentric(minimum: .fixed(20)))`。这一公开 OS 26 API
相对容器形状计算圆角。**20 points 是 SwiftUIIntelligence 对独立卡片的最小回退值，不是 Apple 全局默认圆角半径**；
Apple 未公布统一的卡片圆角。默认 `glassEffect()` 形状是 Capsule。Capsule 不适合高内容面板，
因此卡片显式使用矩形同心形状。见 [ConcentricRectangle](https://developer.apple.com/documentation/swiftui/concentricrectangle)
与 [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)。

启用「降低透明度」时，自定义卡片在同一形状下使用不透明系统背景。Package 只读取公开系统环境，
不使用私有 Apple API。字体保持系统文本预设。

## 示例 App

打开 `Example/SwiftUIIntelligenceDemo.xcodeproj`，运行 `SwiftUIIntelligenceDemo` scheme。App 默认进入聊天，
使用 Apple 本机 provider，并显示实际可用性。生成失败或 JSON 无效时，不覆盖上一份有效文档。
所有非模型来源都标注为 `Synthetic provider · not AI generation` 或 `Recorded Apple model output · generated on Mac`。

| 启动参数 | 作用 |
|---|---|
| `--chat-fixture slow\|provider\|malformed\|unknown` | 明确合成的状态与错误测试 |
| `--chat-real-outputs` | 三份来自 Mac 的已录制规范 JSON。模拟器不调用模型 |
| `--chat-rich-output` | 已录制的丰富组件文档，资源与生成结果逐字节一致 |
| `--weather-demo` | 完整旧天气回放，含分阶段播放与六项宿主交互 |
| `--generic-weather` | 同一天气数据经通用节点渲染，不引入 SDK 天气类型 |
| `--model-dashboard` | 真实 Mac 模型生成的通用天气文档录制 |
| `--model-service` | 同一通用路径展示服务指标、任务、图表和进度 |
| `--show-complete` | 直接显示完整的已录制文档 |
| `--sdk-demo` | 通用节点与宿主动作样例 |
| `--expanded-case settings\|study\|schedule\|analysis\|comparison\|navigation` | 已录制的可编辑表单场景 |
| `--fixture bad-json\|unknown-component\|unknown-action` | 内嵌合成错误文档，用于失败界面 |
| `--appearance light\|dark` | 只改变 App 外观，不改系统设置 |
| `--test-reduce-transparency` | 仅供 UI 测试。用 SPI 环境值模拟「降低透明度」 |

Package 不开启 Apple Intelligence，不下载模型，也不改变系统设置。

## 验证

```sh
./scripts/test-package.sh   # 全部 Package 测试。无参数。
./scripts/validate-chat.sh  # Package 测试 + 手机/iPad 聊天与 SDK UI 测试。
./scripts/validate.sh       # Package 测试 + 完整手机/iPad UI 套件。写入 evidence/final。
./scripts/run-simulator.sh  # 在已启动的模拟器上构建、安装并启动示例。
swift run --scratch-path /tmp/swiftuiintelligence-model-probe --disable-sandbox \
  SwiftUIIntelligenceModelProbe evidence/chat-final/real-model
```

`validate-chat.sh` 和 `validate.sh` 可选传入 phone/iPad 模拟器 ID，默认使用本机现有设备。
`run-simulator.sh` 可选传入模拟器 ID，复用已启动的设备，不擦除设备数据。
`SWIFTUIINTELLIGENCE_CHAT_EVIDENCE_DIR` 和 `SWIFTUIINTELLIGENCE_EVIDENCE_DIR` 指定证据目录。

模型工具调用本机真实 Apple 模型，保存请求、内容草稿、原始响应、规范 JSON 和状态。
其中的语义断言属于验收工具，不是 SDK 业务规则。

`evidence/` 目录约 4 GB，只保留在本机，不在私有仓库中，因此上述证据路径只在本地工作区存在。
本轮结果见 `evidence/expanded-final/VALIDATION.md`。

## 不支持的范围

- 不支持 OpenUI Lang、生成 Swift、动态代码执行，或按业务关键词路由。
- 不支持任意 SwiftUI API、表达式、selector、反射、路径、URL 动作或自定义绘图。
- 不支持图片、`AsyncImage`、地图、媒体、文件访问、日历、通讯录、通知或支付。
- 不生成权限请求、云资源或 entitlement。
- 没有后台任务、数据库或持久化私人聊天。
- SDK 不含业务规则。宿主需要时自行提供领域校验。

结构合法不等于内容真实。严格检查覆盖形状和引用，不保证内容正确。

## 相关文档

- @CAPABILITIES.md：能力覆盖表、SDK 范围，以及每个能力族对应的 Apple 官方来源。
- @CONTEXT.md：当前状态、重命名记录，以及最近一次验证结果。
- @DESIGN.md：聊天与文档界面的设计决策。
- @PRODUCT.md：产品范围、边界和验收限制。
- @THIRD_PARTY_NOTICES.md：OpenUI GIF 来源与 MIT 说明。GIF 只出现在旧天气示例中。

## 作者

- **Frad Lee** - [@FradSer](https://twitter.com/FradSer)

## 许可证

未提供 license。仓库为私有，不授予任何权利。
