# SwiftUIIntelligence ![](https://img.shields.io/badge/A%20FRAD%20PRODUCT-WIP-yellow)

[![Twitter Follow](https://img.shields.io/twitter/follow/FradSer?style=social)](https://twitter.com/FradSer)
[![Swift](https://img.shields.io/badge/Swift-6.2-F05138)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20iPadOS%20%7C%20macOS-lightgrey)](https://developer.apple.com)

**English** | [简体中文](README.zh-CN.md)

A SwiftUI package that turns a conversation into a native document.

The user writes a request. A model drafts the content. The package turns the draft into constrained
document JSON, validates the JSON, and renders it with precompiled native SwiftUI components.
Later messages revise the document.

The repository is private. No license file or public release is supplied.

## How it works

1. The host collects the conversation.
2. A provider drafts the document content.
3. The package validates the JSON against a strict contract.
4. The package renders the document with the component library.

The library does not generate Swift code, evaluate expressions, or run dynamic code.
Each component is precompiled. The model chooses the layout, the component kinds, and the content.
The package is business-neutral: it has no weather, finance, or task templates.

## Features

- **Chat to document.** `DocumentChatSession` keeps the messages, selects a provider, and commits a
  document only after complete validation. A failure keeps the previous valid document.
- **Strict contract.** A Draft 2020-12 JSON Schema and the same checks at decode time. The checks
  cover unknown fields, unknown component kinds, the action allowlist, unique IDs, size, depth, and
  table shape.
- **Native rendering.** 18 component kinds, a semantic SF Symbols allowlist, and native Swift Charts.
  No generated SwiftUI code.
- **Typed state.** Native controls edit a typed `DocumentState`. User edits that stay
  schema-compatible survive a reload and navigation.
- **Host actions.** A button calls a host closure only when the host registers its exact ID. The
  callback receives a unique event ID and a typed state snapshot.
- **Three providers.** Apple on-device models, an existing chatbot pipeline, or a host-owned HTTPS
  backend. All providers receive the same final validation.

## Requirements

- iOS/iPadOS 26 or later, or macOS 26 or later.
- Swift 6.2 or later.
- Xcode 27.0 (27A266a) for the current verification round.

## Products

| Product | Purpose |
|---|---|
| `SwiftUIIntelligence` | Document model, JSON Schema and prompt contract, provider protocols, chat session, strict validation, native renderer, Liquid Glass surfaces, host action registry |
| `SwiftUIIntelligenceFoundationModels` | Optional Apple on-device adapter. No API key. Uses `@Generable` content and intent generation and `GenerationSchema` document generation |
| `SwiftUIIntelligenceWeatherDemo` | Recorded weather reference replay, the original dashboard, and a typed conversion to generic nodes |
| `SwiftUIIntelligenceModelProbe` | macOS acceptance tool for real model runs. It uses only the synthetic chat content in the source |

## Installation

Add this directory as a local Swift Package in Xcode, then select the `SwiftUIIntelligence` product.
Add `SwiftUIIntelligenceFoundationModels` for Apple on-device generation.

Another package can refer to the checkout by path:

```swift
.package(name: "SwiftUIIntelligence", path: "../SwiftUIIntelligence")
```

The independent [MinimalHost](Example/MinimalHost/Package.swift) compiles with exported APIs only.
No remote package URL or version tag is supplied.

## Quick start

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
          // The typed state reaches this closure only when the user taps the button.
          "Received \(event.state.count) fields."
        }
      ]))
    }
  }
}
```

`OnDeviceGeneratedView` supplies the library composer. The host owns the `NavigationStack`; the
embedded view does not create a second root. The package checks model availability at run time.
When Apple Intelligence is unavailable, the view reports an error and does not fall back to a cloud
service.

## Chat session

Use `DocumentChatSession` when the host already has a composer.

```swift
let chat = DocumentChatSession(
  provider: FoundationModelsDocumentProvider(),
  registeredActions: ["acknowledge"],
  timeout: .seconds(300)
)
await chat.send("Create a short handover document for an invented notes app.")
// Render chat.document with SwiftUIIntelligenceView(document:actions:state:) when the phase is ready.
await chat.send("Add a section describing the pending export verification.")
```

The session exposes four phases: `idle`, `generating`, `ready`, and `failed`. A failure names its
kind: `input`, `provider`, or `invalidDocument`.

- `retry()` repeats the same request and does not append the user message again.
- `reset()` clears the history and discards late results.
- `cancel()` cancels the owned task and invalidates late results.
- `timeout` defaults to 300 seconds. Use `timeout: nil` to disable it. A timeout invalidates a late
  result, but it cannot stop a provider that ignores cancellation.
- `StreamingDocumentGenerationProvider` supplies cumulative snapshots. The session reports the
  snapshot count and size, and commits only the final validated document.

Keep one `DocumentState` per document. `load(document, preservingEdits: false)` resets the defaults.
Local edits do not enter the prompt or the trace log. The host owns side effects, sensitive data,
permission checks, and idempotency.

Existing documents do not need a session:

```swift
SwiftUIIntelligenceView(data: jsonData, actions: registry)   // decode and render existing JSON
SwiftUIIntelligenceView(document: document, actions: registry, embedded: true)
```

Set `embedded: true` when the host owns the surrounding scroll view. A top-level non-embedded view
shows the floating actions and the callback result.

## Document contract

`DocumentGenerationContract.schemaJSON(registeredActions:)` returns the Draft 2020-12 Schema.
`DocumentGenerationContract.instructions` returns the model constraints. The Foundation Models
adapter converts the same schema to `DynamicGenerationSchema` and `GenerationSchema`.

| Limit | Value |
|---|---|
| JSON size | 64 KiB |
| Nodes | 128 |
| Depth | 12 levels |
| Children per layout | 32 |
| Layout spacing | 0-48 points |
| Text per node | 4000 characters |
| List | 1-32 items, 1000 characters each |
| Table | 1-6 columns, 1-32 rectangular rows |
| State fields | 32 |
| Floating buttons | 3 |
| Conversation | 24 messages, 48 KiB |

A node ID is 1-64 ASCII letters, digits, `.`, `_`, or `-`, and it is unique in the document.
Plan for a new session when the conversation reaches a limit; the package does not truncate the
context.

## Components and data

The authoritative list is `ComponentCatalog.components` (`UINode.Kind.allCases`):
`vstack`, `hstack`, `grid`, `text`, `button`, `section`, `list`, `table`, `callout`, `metric`,
`iconList`, `badge`, `progress`, `chart`, `form`, `control`, `navigationLink`, `timeline`.

- **Charts.** Multi-series line, area, bar, donut, and radar. At most 32 points, 4 series, and one
  unique label per series. A donut uses one non-negative series with a positive sum. A radar uses one
  series with 3-8 axes and values from 0 to 100. A line, area, or bar chart selects an x value; a
  donut shows a value legend; a radar gives a complete VoiceOver value.
- **Controls.** `textField`, `textEditor`, `toggle`, `picker`, `slider`, `stepper`, and
  `datePicker`. A control declares a typed binding. A choice control carries its options. A date
  value is an ISO 8601 instant.
- **Navigation.** A `navigationLink` points to an existing section ID. The host supplies the
  `NavigationStack`. A native generation request is bounded to one first-level route.
- **Symbols.** `SymbolCatalog.keys` holds 64 semantic keys for information and status, tasks and
  calendars, people, devices and security, commerce, nature, and weather. The JSON uses a semantic key
  such as `people` or `rain`; it never names an arbitrary SF Symbol. An unknown but well-formed key
  renders as `questionmark.circle`. A malformed key or a URL is rejected.

Example document:

```json
{"version":1,"root":{"id":"count","type":"metric","label":"Volunteers","value":"12 people","detail":"Registered","icon":"people"},"floatingActions":[]}
```

Text is plain. The renderer does not run HTML, Markdown, or expressions. A table scrolls
horizontally. A narrow `hstack` can fall back to a vertical stack.

## Providers

**Apple on-device.** `FoundationModelsDocumentProvider` uses the official `SystemLanguageModel.default`
API. It needs no API key. The adapter plans content groups first, then generates each group with its
own constrained session, and merges the model nodes into a generic container without rewriting them.
It is not a single model response. A generation failure returns an error and keeps the previous valid
document. Token budgets are 2600 for content planning, 1100 for legacy grouped components, and 2400
for general direct generation, inside the model 4096-token context.

**Existing chatbot.** Adapt the current pipeline and do not call a second model.

```swift
let provider = ChatResponseProvider { request in
  // Send request.instructions, request.schemaJSON and request.messages to the current pipeline.
  // Return the assistant document JSON.
  try await existingChatbot.generateDocument(request)
}
let chat = DocumentChatSession(provider: provider, registeredActions: ["acknowledge"])
```

`existingChatbot` is a placeholder for the host interface, not a hidden service in this library.

**Host-owned HTTPS backend.** `HTTPDocumentProvider(endpoint:)` posts
`{messages, instructions, schema}` and expects the complete document as `application/json`.
The endpoint must use HTTPS and must not carry embedded credentials. The provider reads at most
64 KiB and uses a 45-second timeout. Model credentials stay on the server.

The example prefers Apple generation. It does not configure or call a third-party service.
Never put a model key in the client or in the source.

Generate and render with the same action allowlist:

```swift
let registry = ActionRegistry(["acknowledge": { "Acknowledged by host" }])
let chat = DocumentChatSession(provider: provider, registeredActions: registry.names)
// In a SwiftUI body, when chat.document exists:
// SwiftUIIntelligenceView(document: document, actions: registry)
```

## Native appearance

Native controls, `Form`, `Section`, and navigation keep the automatic SwiftUI appearance. Custom
content cards use regular Liquid Glass through `SwiftUIIntelligenceSurface`, grouped by a default
`GlassEffectContainer`. The package adds no glass tint, wallpaper, extra border or shadow, rim, or
decorative lining.

The card shape is `ConcentricRectangle(corners: .concentric(minimum: .fixed(20)))`. This public OS 26
API calculates the corners relative to the containing shape. **20 points is the SwiftUIIntelligence
minimum fallback for a standalone card, not an Apple-wide default corner radius**; Apple publishes no
universal card radius. The default `glassEffect()` shape is a Capsule. A Capsule is unsuitable for a
tall content panel, so a card uses the rectangular concentric shape. See
[ConcentricRectangle](https://developer.apple.com/documentation/swiftui/concentricrectangle) and
[Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views).

When Reduce Transparency is enabled, custom cards use an opaque system background in the same shape.
The package reads the public system environment and uses no private Apple API. Fonts remain system
text presets.

## Example app

Open `Example/SwiftUIIntelligenceDemo.xcodeproj` and run the `SwiftUIIntelligenceDemo` scheme. The app
starts in chat with the Apple on-device provider and shows the real availability. A generation failure
or invalid JSON does not replace the previous valid document. The app labels every non-model source
as `Synthetic provider · not AI generation` or `Recorded Apple model output · generated on Mac`.

| Argument | Effect |
|---|---|
| `--chat-fixture slow\|provider\|malformed\|unknown` | Synthetic state and error tests |
| `--chat-real-outputs` | Three recorded canonical JSON documents from a Mac. The simulator runs no model |
| `--chat-rich-output` | A recorded rich-component document with byte-identical resources |
| `--weather-demo` | The complete legacy weather replay with staged playback and six host interactions |
| `--generic-weather` | The same weather data through typed generic nodes, not through SDK weather types |
| `--model-dashboard` | A recorded generic weather document from a real Mac model run |
| `--model-service` | The same generic path with service metrics, tasks, charts, and progress |
| `--show-complete` | Show the complete recorded document at once |
| `--sdk-demo` | Generic nodes and host actions |
| `--expanded-case settings\|study\|schedule\|analysis\|comparison\|navigation` | Recorded editable-form scenes |
| `--fixture bad-json\|unknown-component\|unknown-action` | Synthetic error documents for the failure interface |
| `--appearance light\|dark` | App appearance only. It does not change a system setting |
| `--test-reduce-transparency` | UI test only. Simulates Reduce Transparency through an SPI environment value |

The package does not enable Apple Intelligence, download a model, or change a system setting.

## Verification

```sh
./scripts/test-package.sh   # All package tests. No arguments.
./scripts/validate-chat.sh  # Package tests and the phone/iPad chat and SDK UI tests.
./scripts/validate.sh       # Package tests and the full phone/iPad UI suite. Writes evidence/final.
./scripts/run-simulator.sh  # Build, install, and launch the demo on a booted simulator.
swift run --scratch-path /tmp/swiftuiintelligence-model-probe --disable-sandbox \
  SwiftUIIntelligenceModelProbe evidence/chat-final/real-model
```

`validate-chat.sh` and `validate.sh` accept an optional phone or iPad simulator ID. The default is an
existing device on this Mac. `run-simulator.sh` accepts an optional simulator ID, reuses a booted
device, and erases no device data. `SWIFTUIINTELLIGENCE_CHAT_EVIDENCE_DIR` and
`SWIFTUIINTELLIGENCE_EVIDENCE_DIR` select the evidence directory.

The model probe calls the real Apple model on this Mac and saves the request, the content draft, the
raw response, the canonical JSON, and the state. Its semantic assertions are acceptance-tool checks,
not SDK business rules.

The `evidence/` directory is about 4 GB and stays on this Mac. It is not in the private repository,
so the evidence paths exist only in the local workspace. See
`evidence/expanded-final/VALIDATION.md` for the current round.

## Not supported

- No OpenUI Lang, generated Swift, dynamic code execution, or keyword routing to a business template.
- No arbitrary SwiftUI API, expression, selector, reflection, path, URL action, or custom drawing.
- No images, `AsyncImage`, maps, media, file access, calendar, contacts, notifications, or payments.
- No generated permission request, cloud resource, or entitlement.
- No background task, database, or persisted private chat.
- No business rule in the SDK. The host supplies domain validation when it needs it.

A structurally valid document is not a factually correct document. The strict checks cover the shape
and the references, not the truth of the content.

## Related documents

- @CAPABILITIES.md - the capability table, the SDK scope, and the Apple source for each family.
- @CONTEXT.md - the current state, the rename record, and the last verified result.
- @DESIGN.md - the design decisions for the chat and document surfaces.
- @PRODUCT.md - the product scope, the boundaries, and the acceptance limits.
- @THIRD_PARTY_NOTICES.md - the OpenUI GIF provenance and the MIT notice. The GIF appears only in the legacy weather example.

## Author

- **Frad Lee** - [@FradSer](https://twitter.com/FradSer)

## License

No license is supplied. The repository is private and grants no rights.
