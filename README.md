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

## Minimal integration

```swift
import AgentChatKit

let store = AgentConversationStore(snapshot: .empty(conversationID: "demo"))
let session = AgentChatSession(
    adapter: MyRuntimeAdapter(),
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

The Demo contains all 18 normative scenario entries and never performs model, network, shell, or
filesystem work. Its scripted runtime supports local submit, approval, and interrupt interactions.

## License

Apache-2.0. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
