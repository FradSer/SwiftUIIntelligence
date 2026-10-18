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
| `SwiftUIIntelligence` | 文档模型、JSON Schema 与 prompt 契约、provider 协议、聊天会话、严格校验、原生渲染器、Liquid Glass 阅读卡片、宿主动作注册 |
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

`DocumentChatSession`、`ActionRegistry`、`DocumentState` 和 `SwiftUIIntelligenceView` 都是 `@MainActor`。
请在 SwiftUI body 或 `@MainActor` 函数中调用。

会话有四个状态：`idle`、`generating`、`ready`、`failed`。失败会给出类型：`input`、`provider` 或 `invalidDocument`。

- `retry()` 重试同一个请求，不重复追加用户消息。
- `reset()` 清空历史，并丢弃迟到结果。
- `cancel()` 取消所属 Task，并使迟到结果失效。
- `timeout` 默认 300 秒。用 `timeout: nil` 关闭。超时使迟到结果失效，但无法终止忽略取消的 provider。
- `StreamingDocumentGenerationProvider` 提供累积快照，只用于进度；不要直接渲染这些字节。
- `ProgressiveDocumentGenerationProvider` 提供独立、需要等待完成的 `onPreviewEvent` 通道：先开始新尝试，再按递增顺序发送完整组件文档。
  会话校验声明、引用和计算结果后才暴露 `previewComponents`。每次请求最多 32 个尝试、32 个进入校验的帧和 64 KiB；被拒绝的已进入校验帧也消耗预算。
  `DocumentPreviewView` 使用隔离状态和拒绝执行的动作，禁用控件与导航，保留滚动。预览组件列表不是最终容器树，不更新历史或版本。
  取消、超时、失败和最终接受均清除预览；旧回调不能恢复预览。

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
  // 闭包返回助手消息文本，因此把文档 JSON 作为 String 返回。
  // 把 request.instructions、request.schemaJSON 和 request.messages 传给当前管线。
  let json: String = try await existingChatbot.generateDocumentJSON(request)
  return json
}
let chat = DocumentChatSession(provider: provider, registeredActions: ["acknowledge"])
```

`existingChatbot` 是宿主自己接口的占位，不是本库的隐藏服务。
`generateDocumentJSON(_:)` 是返回助手文本的宿主函数，返回 String。
`ChatResponseProvider(response:)` 把该文本转换为会话校验所用的 JSON 字节。

**宿主自有 HTTPS 后端。** `HTTPDocumentProvider(endpoint:)` 发送 `{messages, instructions, schema}`，
并期望后端返回完整文档，类型为 `application/json`。端点必须使用 HTTPS，且不能内嵌凭证。
该 provider 最多读取 64 KiB，超时 45 秒。模型凭证保留在服务端。

**OpenAI 兼容端点。** `OpenAICompatibleDocumentProvider(endpoint:apiKey:model:)` 向 chat-completions
端点发送 `{model, messages, response_format}`，并读取 `choices[0].message.content` 作为文档 JSON。
它使用 `URLSession` 与临时配置，发送 Bearer 头，最多读取 64 KiB。端点必须使用 HTTPS；
唯一的例外是本机回环 HTTP，用于本地模型服务。OpenAI 兼容端点无法表达 guided-generation schema，
因此该 provider 把 instructions 和 schema 文本放入 system 消息。返回结果经过与其他 provider 相同的严格校验。

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
所有自定义卡片通过 `SwiftUIIntelligenceSurface` 使用 regular Liquid Glass，不添加额外阴影。
「降低透明度」启用时，使用同形状的系统背景回退。
布局容器不再额外包裹卡片。卡片使用同心圆角，20pt 是库自身的最小回退值。
Package 使用公开 SwiftUI API，不修改系统设置。
Demo 的「Details」入口包含模型来源、文档编号以及可选择和复制的 JSON。

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

该工具也接受远程 OpenAI 兼容端点：

```sh
SWIFTUIINTELLIGENCE_API_KEY=<key> swift run --disable-sandbox SwiftUIIntelligenceModelProbe <folder> \
  --openai-compatible https://<host>/v1/chat/completions <model>
```

该模式通过网络运行相同的三轮验收，并把 scheme、host 和 model 写入 `transport.txt`。

`evidence/` 目录约 4 GB，只保留在本机，不在私有仓库中，因此上述证据路径只在本地工作区存在。
本轮结果见 `evidence/expanded-final/VALIDATION.md`。

## 响应式示例接入

示例模块 `SwiftUIIntelligenceExamples` 注册通用比较、备餐和精确分账计算；核心 SDK 不包含场景页面。
参见 `Example/SharedInteractions/README.md`，了解签名、启动方式和当前限制。
源记录、可编辑表格，以及文本、图表、列表、表格和时间线绑定使用同一套校验后的状态协议。
只有计算和显示约束全部通过，编辑结果才会提交。
计算签名可用 `recordReferences` 声明输入集合之间的引用。字段值仍是字符串，但执行宿主回调前必须对应目标集合的实际行 ID。
原生生成先编写目标集合，再生成引用；库不按显示名称推断关联，也不补写值。
可选的 `inputNumberConstraints` 声明宿主授权的数值输入域，例如：
```swift
inputNumberConstraints: ["count": .init(minimum: 1, maximum: 10_000, integer: true, step: 1)]
```
键必须对应数值标量输入。范围必须有限、有序，并处于状态模型的数值范围内；模型声明可使用更窄范围。
整数域在宿主回调前拒绝小数，失败编辑保留旧状态。可选 step 约束声明元数据，不定义运行时步长格点。
省略字典保持旧行为，不提供源值、ID 或默认值。

可选的 `recordInputDescriptions` 为原生集合生成提供宿主编写的参数用途说明。
键必须对应已声明的输入，说明不得为空，且每项最多 500 个 Unicode 标量。
provider 原样传递说明，不把它们解释为页面模板或计算映射。
`DocumentGenerationRequest` 与 `DocumentChatSession` 可选的 `sourceInputValidation` 回调接收能力 ID、输入参数名和集合。
原生引用阶段在集合成为依赖目标前调用它；最终验收会再次检查已绑定的源输入，其他 provider 也不能绕过该检查。
回调可能重复运行，必须是无副作用的纯验证。跨输入规则仍需完整源数据和最终验证；库不修复被拒绝的集合。
没有记录引用时，回调在绑定完成后、布局生成前运行，并非早于所有模型调用。
省略回调会保留仅注册能力 ID、没有签名元数据的旧请求；显式启用时必须提供匹配的签名。
`GeneratedDocumentView(provider:...)` 与 `OnDeviceGeneratedView` 都可传入 requirements 和全部分阶段验证回调。
需要在错误源数据进入依赖生成前拒绝时，应配置这些选项，而不是只依赖最终验证。
宿主显式选择不同验收策略时，可调用 `session.send(text, validation: policy)`，传入不可变的 `DocumentValidationPolicy`。
它仅为该请求替换会话基线要求与回调；重试保留同一策略。普通 `send(text)` 仍使用会话基线。
其中 `finalValidation` 在文档和计算检查后、提交前于主线程执行，可用于宿主交互验收；它不传给 provider，也不用于临时预览。
`DocumentChatSession.originalSources` 独立于模型消息及生成结果，按顺序精确保留有效提交的原文。
生成失败保留该段，重试不重复追加，无效或被忽略的发送不追加，reset 清空原文。
每次原始提交包括空白在内最多 48,000 UTF-8 字节；历史最多保留 24 段、合计 1,152,000 UTF-8 字节，直到 reset 清空。超限发送在调用 provider 前拒绝，不静默截断已接受原文。
公开输入视图提供可选择的原文、显式来源／版本／完整可复制 JSON 的 Details，以及 New chat；宽屏在结果旁保留原文。

端到端验收尚未完成。最小 Apple 数值计算已保留输入 2 并计算输出 4；完整备餐仍超出上下文。
结构测试和合成原生交互不代表实时模型的完整性或泛化能力。
独立的已校验只读组件预览已接通，不能与累积 JSON 快照混用。
合成 iPhone／iPad 测试验证了交互禁用、多组件滚动、取消／失败后的旧状态保留，以及仅最终接受后启用交互；最小真实 Apple 请求已发出预览事件。
渐进机制已通过文档所述的合成原生测试和最小实时范围验收。三个完整实时示例和未预设输入泛化仍未完成。

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

## Liquid Glass 卡片颜色

可选字段 `cardColor` 支持 `neutral`、`blue`、`orange`、`green`、`purple`。
节点和时间线事件使用相同的有限色板；未知颜色会被拒绝。
未指定时保留无染色玻璃，旧 JSON 编码不会新增颜色字段。
事件颜色覆盖独立时间线的颜色；分组内仍共用一张玻璃卡片。
颜色由数据明确提供，不根据标题猜测类别。降低透明度时使用系统背景回退。
