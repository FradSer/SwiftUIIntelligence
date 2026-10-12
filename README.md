# SwiftUIIntelligence

An open-source framework for intelligent interfaces, built on SwiftUI.

The package, modules, examples, and public branded types use `SwiftUIIntelligence`. Existing consumers must update their imports and type names. Historical evidence retains the names used during those runs. The workspace directory is `SwiftUIIntelligence`. For the latest build and test results, see [current project state](CONTEXT.md).

业务无关的 Swift Package：chatbot 消息与上下文 → AI 内容起草 → 受 Schema 约束的文档 JSON → 严格校验 → 预编译原生 SwiftUI Liquid Glass 文档。没有 OpenUI Lang、生成 Swift、动态代码执行或天气关键词路由。支持 iOS/iPadOS、macOS 26+，Swift 6.2+。

## 产品与边界

- `SwiftUIIntelligence`：通用文档、JSON Schema/prompt 契约、provider 协议、聊天状态、严格验证、原生内容渲染、玻璃控件和宿主动作注册。
- `SwiftUIIntelligenceFoundationModels`：可选 Apple 本机模型适配，不需要 API key。使用官方 `@Generable` 内容/意图生成和 `GenerationSchema` 文档生成。公开 API 为 `SystemLanguageModel.default`，不声称其未公开模型编号。
- `SwiftUIIntelligenceWeatherDemo`：完整 GIF 天气参考回放、原仪表盘和类型化通用节点转换；确定性回放与 AI 生成明确区分。
- `SwiftUIIntelligenceModelProbe`：同机 macOS 的真实模型验收工具，仅使用源码中公开的合成聊天内容。

支持节点：`vstack`、`hstack`、`grid`、`text`、`button`、`section`、`list`、`table`、`callout`、`metric`、`iconList`、`badge`、`progress`、`chart`。这不是任意 SwiftUI 代码解释器。布局、类型和内容由 AI 选择；组件实现和玻璃材质由库预编译提供。图表支持多序列折线、面积、柱状、环形和雷达；不接受表达式、任意颜色、图片 URL、生成代码或自定义绘图执行。

Apple 适配器先由模型规划通用内容分组，再用独立受约束会话生成各组与标题、状态 JSON，最后将未经改写的模型子树合并到通用容器。它不是一次单一模型响应；生成失败会返回错误，保留上一份有效文档。显式请求的图表样式与分组覆盖经过检查，独立规划重试避免累积超出模型上下文。

生成 Schema 与运行时验证职责不同：Apple guided generation 约束形状；严格解码仍检查未知字段/组件、动作白名单、唯一 ID、大小、深度和表格一致性。结构合法不保证生成内容事实正确，宿主仍可进行领域校验。正文是普通文本，不执行 HTML/Markdown/表达式。表格横向滚动；窄屏 hstack 可回退竖排。

## 聊天示例

打开 `Example/SwiftUIIntelligenceDemo.xcodeproj`，运行 `SwiftUIIntelligenceDemo`。默认进入聊天，使用 Apple 本机 provider；界面显示实际可用性。输入内容生成文档，继续聊天更新；生成失败或无效 JSON 不覆盖上一份有效文档。Retry 重试相同请求；New chat 清空会话并丢弃迟到结果。JSON 可查看/复制；动作只调用宿主注册闭包。

模型不可用时不会悄悄替换成 mock，可显式选择 `Try synthetic demo`，全程标注 `Synthetic provider · not AI generation`。测试参数：

- `--chat-fixture slow|provider|malformed|unknown`：明确合成的状态/错误测试。
- `--chat-real-outputs`：依次展示真实 Mac 生成的三份未改写规范 JSON，标注 `Recorded Apple model output · generated on Mac`；此模式不在模拟器调用模型。
- `--appearance light|dark`：只改变 App 外观，不改系统设置。
- `--weather-demo`：完整旧天气回放，明确未接模型；保留分阶段、自动滚动、暂停、复制、展开及宿主回调。
- `--generic-weather`：同一完整天气数据与阶段经 `GenericWeatherReference` 类型化转换，再由通用 `SwiftUIIntelligenceView` 渲染。复用同一宿主六项交互，不把天气类型加入 SDK。
- `--chat-rich-output`：展示本机模型真实生成的新组件文档；资源与生成结果逐字节一致，模拟器不推理。
- `--model-dashboard`：展示真实 Mac Apple 模型生成的完整天气通用节点，支持分阶段回放、自动滚动、暂停、复制、展开与宿主动作反馈。
- `--model-service`：同一通用路径展示真实模型生成的服务指标、任务、图表和进度，验证组件不依赖天气业务。
- `--show-complete`：录制展示模式直接显示完整文档。
- `--sdk-demo`：原通用节点与宿主动作样例。

不要把模型密钥放入客户端或源码。Apple provider 本机生成；可用状态不足时报告原因，不自动开关 Apple Intelligence、下载模型或改变系统配置。

## 集成

通过 SPM Add Local 选择项目目录；添加 `SwiftUIIntelligence` 和可选的 `SwiftUIIntelligenceFoundationModels` product。最小聊天调用：

```swift
import SwiftUIIntelligence
import SwiftUIIntelligenceFoundationModels

@MainActor func generateDocument() async {
    let chat = DocumentChatSession(provider: FoundationModelsDocumentProvider())
    await chat.send("Create a short handover document for an invented notes app.")
    // On ready, render chat.document with SwiftUIIntelligenceView(document:actions:).
    // chat.documentJSON is normalized JSON; messages retain validated context.
    await chat.send("Add a section describing the pending export verification.")
}
```

已有 chatbot 可直接适配，不重复调用第二个模型：

```swift
let provider = ChatResponseProvider { request in
    // Pass request.instructions, request.schemaJSON and request.messages
    // to your existing chatbot model pipeline; return assistant document JSON.
    try await existingChatbot.generateDocument(request)
}
let chat = DocumentChatSession(provider: provider, registeredActions: ["acknowledge"])
```

`existingChatbot` 是宿主自己的接口占位，不是本库隐藏服务。`HTTPDocumentProvider(endpoint:)` 为可选宿主 HTTPS 后端适配：POST `{messages,instructions,schema}`，后端使用自己的结构化模型 API，响应为完整 `application/json` 文档；模型凭证保留在后端。当前示例首选 Apple，并未配置或调用第三方服务。

生成和渲染应使用同一个动作白名单：

```swift
let registry = ActionRegistry(["acknowledge": { "Acknowledged by host" }])
let chat = DocumentChatSession(provider: provider, registeredActions: registry.names)
// In a SwiftUI body, once chat.document exists:
// SwiftUIIntelligenceView(document: document, actions: registry)
```

已有 JSON 仍可用 `SwiftUIIntelligenceView(data:actions:)`。被嵌入宿主滚动文档时使用 `embedded: true`；宿主负责显示回调结果。顶层非嵌入视图显示浮动动作与回调反馈。

## 契约、状态与限制

`DocumentGenerationContract.schemaJSON(registeredActions:)` 提供 Draft 2020-12 Schema；`instructions` 提供模型约束；Foundation Models 适配从同一 Schema 转换官方 `DynamicGenerationSchema`/`GenerationSchema`。表格使用 1–6 列固定宽度分支，避免不同长度的行。内容模型同时选择所需组件，Apple 文档阶段只使用选中的组件及基础布局，以降低上下文负担；选择由模型完成，不按业务关键词路由。内容规划预算 2600 tokens、旧丰富组件分组 1100 tokens、新通用直接生成 2400 tokens；超限或内容不完整仍报告失败，不伪造输出。Apple API 不支持的字符串/全局约束由 SDK 严格验证，而非假称模型完全保证。

最多 64 KiB JSON、128 节点、12 层、每布局 32 子节点；文本 4000 字符；列表 1–32 非空项、单项 1000 字符；表格 1–6 列/1–32 行；最多三个浮动按钮。会话最多 24 条消息、48 KiB 内容；超限可开启新会话，不悄悄截断上下文。Apple 模型自身上下文限制也可能更早拒绝，由 provider 错误界面显示。

`DocumentChatSession` 有 idle/generating/ready/failed 状态，区分 input/provider/invalidDocument 失败。只有完整验证成功后原子更新文档和 revision；失败保留之前文档；重试不重复追加用户消息，非法响应不进入历史。reset 使用请求身份丢弃迟到结果。没有后台任务、数据库或持久化私人聊天。

## 验证

```sh
./scripts/test-package.sh
./scripts/validate-chat.sh # Package + original phone/iPad chat/SDK UI; new evidence directory
swift run --scratch-path /tmp/swiftuiintelligence-model-probe --disable-sandbox \
  SwiftUIIntelligenceModelProbe evidence/chat-final/real-model
```

模型工具实际调用 Mac 本机 Apple 模型并保存请求、内容草稿、原始响应、规范 JSON和状态；测试程序对合成班次、跟进修改及跨领域交接执行明确语义断言。这些断言属于验收工具，不是 SDK 的业务规则。

本轮扩展验证见 `evidence/expanded-final/VALIDATION.md`；上一轮真实天气/服务最终证据见 `evidence/visual-model-final/VALIDATION.md`。此前丰富组件和聊天链路结果分别保留在 `evidence/rich-final`、`evidence/chat-final`；先前天气玻璃验证保留在 `evidence/glass-final`。历史验证证据与 `evidence/chat-before` 均保留。OpenUI GIF 只用于旧天气示例，来源/MIT 说明见 `THIRD_PARTY_NOTICES.md`。

## 图标与丰富组件契约

`SymbolCatalog.keys` 提供 64 个有限语义图标键（以代码目录为准），映射预编译 SF Symbols，覆盖信息/状态、任务/书籍/日历、人物、设备/网络/安全、商业、自然与天气。JSON 使用 `people`、`task`、`rain` 等语义键，不直接执行任意 SF Symbol 名称。生成 Schema 引用同一有限目录。手工或既有 chatbot 输出的未知但格式合法键保留在 JSON，渲染为 `questionmark.circle`；非法长度/字符或 URL 拒绝。图标伴随可读标签，不承担唯一的信息表达。

`text/section/button/callout/badge` 可选 `icon`；`metric` 与 `progress` 要求 `icon`；`iconList.iconItems` 每项包含 `text/icon`。指标包含 `label/value/detail`，单位在 value 中；进度包含 `completed/total`（0 ≤ completed ≤ total，total > 0）；状态标签包含 text/tone；网格 columnCount 1–6，按可用宽度回退，竖排至少 8pt 间距。

`chart` 包含 title/chartStyle/points，每点为 label/value/series。最多 32 点、4 序列、每序列标签唯一、有限数值 |value| ≤1e9。环形单序列非负且总和 >0；雷达单序列 3–8 轴、0–100 值。原生 Charts 自动坐标与颜色；线/面积/柱状可选中横轴查看值，环形显示数值图例，雷达提供完整 VoiceOver 值。没有天气专用单位或隐藏的数据修复。

```json
{"version":1,"root":{"id":"count","type":"metric","label":"Volunteers","value":"12 people","detail":"Registered","icon":"people"},"floatingActions":[]}
```

真实丰富组件验收（只使用合成 workshop 数据）：

```sh
swift run --scratch-path /tmp/swiftuiintelligence-model-probe --disable-sandbox \
  SwiftUIIntelligenceModelProbe evidence/your-new-model-run --rich
```

GIF 模块清单完整保留；原生 SwiftUI Liquid Glass 与 GIF 的网页黑色卡片、字体、动画时长及手机自适应布局不同，不宣称像素级一致。通用节点模式保留全部数据/图形类别，但布局与原专用仪表盘不同，差异及六项交互证据见最终验证记录。

## Text → native UI (expanded public API)

Add this directory as a local Swift Package in Xcode, select `SwiftUIIntelligence` and `SwiftUIIntelligenceFoundationModels`, or use `.package(name: "SwiftUIIntelligence", path: "../SwiftUIIntelligence")` in another package. The independent [MinimalHost](Example/MinimalHost/Package.swift) compiles using only exported APIs. No remote package URL or version tag is supplied.

```swift
import SwiftUIIntelligence
import SwiftUIIntelligenceFoundationModels
import SwiftUI

struct HostView: View {
  var body: some View {
    NavigationStack {
      OnDeviceGeneratedView(actions: ActionRegistry(async: [
        "submit": { event in
          // This registration authorizes one host capability.
          // Typed state is sent to this callback only when the user taps.
          return "Received \(event.state.count) fields."
        }
      ]))
    }
  }
}
```

Users enter text in the library composer. `FoundationModelsDocumentProvider` chooses native presentation from the conversation; forms and routes use original source text in bounded guided generation. The host owns NavigationStack; embedded SwiftUIIntelligence does not create another root. Model availability is checked at runtime; unavailable Apple Intelligence produces an explicit error and no silent cloud fallback.

For integrations with existing chat/composers, create `DocumentChatSession(provider:registeredActions:requirements:semanticValidation:timeout:)`, call `await session.send(text)`, and render `SwiftUIIntelligenceView(document:actions:state:)` when `session.document` exists. `DocumentRequirements` can require component/control kinds, an optional state field count and exact displayed strings; the optional Sendable semantic closure verifies associations, state defaults, chart facts, etc. These checks run in the public session for every provider; Apple retry attempts also run them. Arbitrary prose without host constraints only receives structural/binding validation, not a guarantee that every intended fact is preserved.

Keep one `DocumentState` instance per document/session. Native controls edit it locally; schema-compatible user edits survive reload and navigation; untouched defaults follow new document revisions. `load(document,preservingEdits:false)` resets defaults. State values are Swift `text`, `number`, or `boolean`; choice and date declarations constrain their string values. Local edits are not automatically included in prompts or trace logs. Host callbacks receive an `ActionEvent` with a unique ID and typed state snapshot; host side effects, sensitive data, permission checks and idempotency stay in the host.

`session.cancel()` cancels the owned task and invalidates late completions; `reset()` also clears history. Failures keep the previous valid document and support `retry()`. The default 300-second deadline can be changed or disabled with `timeout:nil`; it invalidates late results but cannot forcibly terminate a provider ignoring cancellation. `StreamingDocumentGenerationProvider` supplies cumulative snapshots; the session exposes snapshot counts/sizes and commits only the final validated document. Rich legacy grouped generation reports traces but does not yet stream public progress. The six-step weather playback is explicit saved-JSON replay, not live model streaming.

See [capability coverage](CAPABILITIES.md) and [this round's validation](evidence/expanded-final/VALIDATION.md). The model uses a smaller capability-specific grammar to fit its 4096-token context. With one field per selected control type it generates a native typed state object; only its container shape is adapted into the public state array, preserving each declaration and root unchanged. Multiple fields of one control type use the broader state-array grammar and have not been model-tested. Native generation currently bounds a request to one first-level navigation route. It may still reject facts/bindings after bounded retries; failure records are retained. This package is a bounded OpenUI-style text-to-native-UI SDK, not support for all SwiftUI APIs.


## Native controls and rounded Liquid Glass cards

Native controls, Form/Section and navigation retain SwiftUI automatic appearance. Custom content cards use default regular Liquid Glass through `SwiftUIIntelligenceSurface`, grouped by a default `GlassEffectContainer`. No glass tint, wallpaper, extra border/shadow, rim or inner decorative lining is added.

The card shape is `ConcentricRectangle(corners: .concentric(minimum: .fixed(20)))`. This public OS26 API calculates corners relative to the containing shape. **20pt is SwiftUIIntelligence's minimum fallback for standalone cards, not an Apple-wide default corner radius**; Apple does not publish one universal card radius. ConcentricRectangle's per-corner/default uniformity behavior is retained. The default `glassEffect()` shape itself is Capsule; a capsule is unsuitable for tall content panels, so cards explicitly use the rectangular concentric shape. See [Apple's concentric rectangle documentation](https://developer.apple.com/documentation/swiftui/concentricrectangle) and [custom Liquid Glass guidance](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views).

When Reduce Transparency is enabled, custom cards use opaque system background in the same shape. The existing test-preview SPI remains SwiftUIIntelligence-owned; production reads the public system environment. No system setting or private Apple API is used. Fonts remain system text presets; chart/status colors and responsive geometry retain semantic meaning. Model/schema/JSON/state/provider/host actions are unchanged. The current correction and focused acceptance are in `evidence/rounded-glass-final/VALIDATION.md`; full prior system-default verification is preserved in `evidence/swiftui-default-final`.
