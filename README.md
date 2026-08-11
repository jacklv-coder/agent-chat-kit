# AgentChatKit

A native AI agent conversation UI foundation for iOS and iPadOS.

Streaming Markdown · Tool Calls · Shell Commands · File Changes · Unified Diffs · Approvals ·
Artifacts · Custom Runtime Adapters

> Bring your own agent runtime. AgentChatKit does not implement or constrain your agent loop.

## Status

The repository is under active development from the normative engineering specification in
[`doc/AgentChatKit_iOS_iPadOS_v1_1_Engineering_Spec.md`](doc/AgentChatKit_iOS_iPadOS_v1_1_Engineering_Spec.md).
See [`IMPLEMENTATION_STATUS.md`](IMPLEMENTATION_STATUS.md) for completed and pending work. It is
not yet a `1.0.0` release.

## Requirements

- iOS/iPadOS 17+
- Swift 6
- Xcode 16 or later

## Package products

- `AgentChatCore`: platform-independent models, Runtime SPI, reducer, store, and session.
- `AgentChatMarkdown`: platform-independent Markdown render document and unified diff parser.
- `AgentChatUIKit`: native conversation UI and renderer registry.
- `AgentChatTesting`: scripted offline mock runtime and fixtures.
- `AgentChatKit`: umbrella module for application integration.

## Start with a runnable integration

[`Examples/QuickStart`](Examples/QuickStart) is a complete, CI-built host app. It includes the full
[`ReferenceRuntimeAdapter`](Examples/QuickStart/App/ReferenceRuntimeAdapter.swift), so no placeholder
types or hidden backend are required:

```sh
cd Examples/QuickStart
xcodegen generate
xcodebuild -project AgentChatQuickStart.xcodeproj -scheme AgentChatQuickStart \
  -destination 'generic/platform=iOS Simulator' build
```

The scene wiring is intentionally small:

```swift
import AgentChatKit

let store = AgentConversationStore(snapshot: .empty(conversationID: "demo"))
let session = AgentChatSession(
    adapter: ReferenceRuntimeAdapter(), // Complete implementation in Examples/QuickStart
    configuration: .init(conversationID: "demo"),
    reducerConfiguration: .init(),
    store: store
)
let controller = AgentConversationViewController(store: store)
controller.actionHandler = { action in
    if case .runtime(let command) = action {
        try await session.send(command)
    }
}
Task { try await session.start() }
```

The runtime owns model requests, tools, permissions, transport, and persistence. AgentChatKit only
reduces structured events, renders state, and routes user actions.

## Development

```sh
swift package resolve
xcodebuild -scheme AgentChatKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

The UIKit timeline uses a native single-column compositional layout, `AgentUpdateScheduler`, and
stable-ID `AgentScrollCoordinator` anchoring. The demo project is generated from
`Examples/AgentChatDemo/project.yml` with `xcodegen generate`.

## Offline demo

```sh
cd Examples/AgentChatDemo
xcodegen generate
xcodebuild -project AgentChatDemo.xcodeproj -scheme AgentChatDemo \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

The Demo contains all normative scenario entries, a complete cell showcase that combines every
built-in block, and a current-conversation replay for checking realistic Chinese Markdown, tables,
trees, long-message layout, and sanitized tool-activity cells for commands, image inspection, file
edits, skills, and host integrations. Tool activity uses compact icon-and-summary rows with
whole-row expandable details and animated height changes. Expanded image activity resolves a
thumbnail through the injected `AgentImageProviding`; tapping it opens the Demo's full-screen
pan-and-zoom preview. Markdown tables use a native, accessible grid with horizontal scrolling when
needed. Submitting composer text produces an offline sequence of thinking, file search, command,
file-read, and streaming Markdown events. The Demo never performs model, network, shell, or
filesystem work. Its Test Lab menu can play, pause, single-step, reset, change replay speed, and copy
a versioned scenario JSON fixture. The same fixture format is consumed by `AgentChatTesting`.

## Integration documentation

- [Getting started](Sources/AgentChatKit/AgentChatKit.docc/GettingStarted.md)
- [Runtime adapter contract](Sources/AgentChatKit/AgentChatKit.docc/RuntimeAdapter.md)
- [Composer integration](Sources/AgentChatKit/AgentChatKit.docc/ComposerIntegration.md)
- [Deterministic testing scenarios](Sources/AgentChatKit/AgentChatKit.docc/TestingScenarios.md)
- [OpenMinis and Hermex reference review](doc/REFERENCE_REVIEW.md)

## License

Apache-2.0. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
