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

The UIKit timeline uses a native single-column compositional layout, a traditional
`UICollectionViewDataSource`, explicit non-animated batch updates, and stable-ID history anchoring.
The demo project is generated from
`Examples/AgentChatDemo/project.yml` with `xcodegen generate`.

## Offline demo

```sh
cd Examples/AgentChatDemo
xcodegen generate
xcodebuild -project AgentChatDemo.xcodeproj -scheme AgentChatDemo \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

The Demo opens on **Complete Conversation**, a production-shaped message-list page with recent
history, cursor pagination, user and assistant turns, tool activity, Markdown, a working composer,
and a deterministic streamed response. The Test Lab remains available from the navigation menu and
contains all normative scenarios, including a complete cell showcase and a current-conversation
replay for checking realistic Chinese Markdown, tables, trees, long-message layout, and sanitized
tool activity for commands, image inspection, file edits, skills, and host integrations. Tool
activity uses compact icon-and-summary rows with
whole-row expandable details and immediate self-sizing height updates. Expanded image activity resolves a
thumbnail through the injected `AgentImageProviding`; tapping it opens the Demo's full-screen
pan-and-zoom preview. Markdown tables use a native, accessible grid with horizontal scrolling when
needed. The timeline follows streaming output only while the reader owns the latest position,
preserves a stable visible anchor when older history is prepended, and exposes Jump to Latest after
manual reading. Submitting composer text produces an offline sequence of thinking, file search,
command, file-read, and streaming Markdown events. The Demo never performs model, network, shell,
or filesystem work. Complete Conversation includes a one-tap sample response. Test Lab reports live
playback state, resumes or single-steps paused fixtures, replays from the beginning, resets into a
paused state, changes replay speed, and copies a versioned scenario JSON fixture. The same fixture
format is consumed by `AgentChatTesting`.

## Integration documentation

- [Getting started](Sources/AgentChatKit/AgentChatKit.docc/GettingStarted.md)
- [Complete conversation experience](Sources/AgentChatKit/AgentChatKit.docc/ConversationExperience.md)
- [Runtime adapter contract](Sources/AgentChatKit/AgentChatKit.docc/RuntimeAdapter.md)
- [Composer integration](Sources/AgentChatKit/AgentChatKit.docc/ComposerIntegration.md)
- [Deterministic testing scenarios](Sources/AgentChatKit/AgentChatKit.docc/TestingScenarios.md)
- [OpenMinis and Hermex reference review](doc/REFERENCE_REVIEW.md)

## License

Apache-2.0. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
