# Getting Started

Embed a complete agent conversation without coupling the UI to a particular model provider or
transport.

## Run the complete QuickStart

The repository's `Examples/QuickStart` project is the smallest supported integration. Its
`ReferenceRuntimeAdapter` is intentionally implemented in full: it creates one connection, emits an
initial snapshot, accepts commands, streams blocks, supports interruption, and closes idempotently.

```sh
cd Examples/QuickStart
xcodegen generate
xcodebuild -project AgentChatQuickStart.xcodeproj \
  -scheme AgentChatQuickStart \
  -destination 'generic/platform=iOS Simulator' build
```

The QuickStart is built in CI so its setup cannot silently drift away from the public API.

For a product-shaped reference, run `Examples/AgentChatDemo`. It launches directly into Complete
Conversation: a full timeline, cursor-backed history, streaming tool activity, Markdown, connection
state, Jump to Latest, and the default rich composer. Open Test Lab from the navigation menu when
you need isolated renderer and lifecycle fixtures. See <doc:ConversationExperience> for the page
contract.

## Add the package

Add this repository as a Swift Package and link the `AgentChatKit` product. Create one store and one
session per scene or conversation:

```swift
import AgentChatKit

let conversationID: AgentConversationID = "support"
let store = AgentConversationStore(
    snapshot: .empty(conversationID: conversationID)
)
let session = AgentChatSession(
    adapter: ReferenceRuntimeAdapter(),
    configuration: .init(conversationID: conversationID),
    store: store
)
let conversation = AgentConversationViewController(store: store)
conversation.actionHandler = { action in
    guard case .runtime(let command) = action else { return }
    try await session.send(command)
}
Task { try await session.start() }
```

Embed `conversation` as an ordinary child or navigation destination. Keep your conversation list,
account state, runtime choice, persistence, and deep-link routing outside the SDK; pass only the
selected conversation's store, session, capabilities, and host actions into this page.

Both the recommended table timeline and the optional collection timeline accept a host-provided
``AgentComposerProviding`` through `composer:` while keeping the original initializer and default
``AgentComposerView`` behavior. Adopt ``AgentComposerInteracting`` for a fully interactive composer
with live draft and hardware-keyboard integration. See <doc:ComposerIntegration> for a complete
implementation, import routing, and accessibility responsibilities.

`ReferenceRuntimeAdapter` is the complete implementation in `Examples/QuickStart`. Copy it first,
then replace only its offline response logic with your SSE, WebSocket, or local-agent transport.
The runtime-specific contract is described in <doc:RuntimeAdapter>.

## Keep host policy in the host

Handle ``AgentHostAction`` values for URL policy, file navigation, artifacts, image preview, and
custom composer controls. Do not execute a command merely because the UI rendered a command block;
blocks describe runtime state and are not executable instructions.
