# Complete Conversation Experience

Ship a complete message-list page while keeping runtime and product policy in the host application.

## Use the page, not individual cells

``AgentConversationViewController`` composes the native collection timeline, connection banner,
Jump to Latest control, history progress, keyboard-safe composer, and renderer registry. A host
usually presents one controller for the selected conversation:

```swift
let store = AgentConversationStore(
    snapshot: .empty(conversationID: selectedConversationID)
)
let session = AgentChatSession(
    adapter: runtimeAdapter,
    configuration: .init(conversationID: selectedConversationID),
    store: store
)
let page = AgentConversationViewController(
    store: store,
    configuration: .init(
        runtimeCapabilities: runtimeCapabilities,
        composerAccessories: hostAccessories
    )
)
page.actionHandler = { action in
    switch action {
    case .runtime(let command):
        try await session.send(command)
    case .host(let action):
        hostRouter.handle(action)
    }
}
Task { try await session.start() }
```

The SDK page begins at the conversation boundary. The host still owns its sidebar or conversation
list, selection and deep links, persistence, authentication, runtime construction, attachment bytes,
URL policy, and image or artifact destinations.

## Honor the scroll contract

The timeline follows new and height-changing streaming content while the reader remains near the
latest message. Direct manipulation pauses automatic following for a short cooldown. Once the reader
moves away, new content increments the Jump to Latest affordance instead of moving the viewport.
Tapping it establishes follow intent immediately, including when a streaming height update interrupts
the UIKit scroll animation.

Do not reach into the collection view to manage offsets from the host. The controller preserves a
stable block identifier and viewport-relative offset when older turns are prepended, and falls back to
a nearby surviving block if the original anchor is deleted.

## Return cursor-addressed history

Set `hasEarlierHistory` and `earlierHistoryCursor` on the current
``AgentConversationSnapshot``. When a user drags at the top, the page sends
`AgentRuntimeCommand.loadEarlier` once for that gesture and shows progress. Resolve the cursor in the
runtime, then emit an `AgentRuntimeEventPayload.historyPage` even when the page is empty:

```swift
case .loadEarlier(let request):
    let result = try await historyStore.page(before: request.cursor)
    emit(
        .historyPage(
            AgentHistoryPage(
                turns: result.turns,
                earlierCursor: result.previousCursor,
                hasEarlierHistory: result.hasMore
            )
        )
    )
```

Turn and block identifiers must remain stable across snapshots and pages. Return pages in ascending
conversation order; the reducer prepends them ahead of the current turns.

## Validate the whole experience

Run `Examples/AgentChatDemo` without launch arguments to inspect Complete Conversation. It exercises
initial history, two cursor pages, manual reading during a streamed reply, Jump to Latest, tool
disclosure, Markdown tables, image preview, and the rich composer without network, shell, model, or
filesystem side effects. Test Lab adds deterministic offline and reconnect transitions.

Use Test Lab for isolated states and <doc:TestingScenarios> to add a fixture. A production adapter
should pass reducer and integration tests for snapshot recovery, empty and non-empty history pages,
interruption, reconnect, and a user who remains scrolled away throughout a stream.
