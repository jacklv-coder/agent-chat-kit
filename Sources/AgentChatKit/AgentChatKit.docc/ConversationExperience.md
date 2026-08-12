# Complete Conversation Experience

Ship a complete message-list page while keeping runtime and product policy in the host application.

## Use the page, not individual cells

``AgentTableConversationViewController`` is the recommended page. It composes the native table
timeline, connection banner, Jump to Latest control, history progress, keyboard-safe composer, and
renderer registry. A host usually presents one controller for the selected conversation:

```swift
let store = AgentConversationStore(
    snapshot: .empty(conversationID: selectedConversationID)
)
let session = AgentChatSession(
    adapter: runtimeAdapter,
    configuration: .init(conversationID: selectedConversationID),
    store: store
)
let page = AgentTableConversationViewController(
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

``AgentConversationViewController`` provides the same Store, Composer, action routing, cells,
history paging, and scroll policy on a native collection view. Replace the controller type in the
example above only when the host requires a custom compositional layout.

The table timeline keeps one Turn per section for stable data updates, but does not render section
headers. A dedicated metadata cell follows the Turn's final block: its time trails below user bubbles
and leads below assistant or system content. A multi-block assistant reply therefore displays one
time after the complete response region, including when its content uses a host renderer.

The SDK page begins at the conversation boundary. The host still owns its sidebar or conversation
list, selection and deep links, persistence, authentication, runtime construction, attachment bytes,
URL policy, and image or artifact destinations.

## Present tool activity

Choose the compact inline treatment or an expandable capsule when constructing either conversation
controller:

```swift
let page = AgentTableConversationViewController(
    store: store,
    configuration: .init(toolPresentationStyle: .capsule)
)
```

Both styles consume the same ``AgentBlock`` lifecycle. Emit `.queued`, `.running`,
`.waitingForApproval`, `.succeeded`, `.failed`, or `.cancelled` as the runtime changes state, and
increment the block revision for every replacement. Capsule headers add progress, completion, failure,
retry, and disclosure affordances without changing the runtime protocol.

Long-press or secondary-click a block to use its context menu. Built-in menus expose the actions that
are valid for that payload and lifecycle: copy, expand/collapse, open file or artifact, retry, and
approval choices. Pointer highlighting is automatic on iPad, while file/image/text/URL drops in the
composer are forwarded to the host's existing paste/import callback.

Command, search, file, image, and generic tool blocks derive a safe title and subtitle from their
typed payload. An adapter can override those labels without creating a custom renderer by adding
``AgentBlockMetadataKey/displayTitle``, ``AgentBlockMetadataKey/displaySubtitle``, and an optional
``AgentBlockMetadataKey/expandedDetail`` to block metadata. Use
``AgentBlockMetadataKey/activityKind`` with the value `reasoning` for a user-safe Thinking row. This
row intentionally displays only the summary supplied by the runtime, never hidden model reasoning.

```swift
let block = AgentBlock(
    id: "command-42",
    kind: .command,
    content: .command(commandPayload),
    state: .running(progress: nil),
    metadata: [
        AgentBlockMetadataKey.displayTitle: .string("Running package tests"),
        AgentBlockMetadataKey.displaySubtitle: .string("AgentChatKit · 32 tests"),
    ]
)
```

## Honor the scroll contract

The timeline follows new and height-changing streaming content while the reader remains near the
latest message. Direct manipulation pauses automatic following for a short cooldown. Once the reader
moves away, new content increments the Jump to Latest affordance instead of moving the viewport.
Tapping it establishes follow intent and updates the content offset immediately.

The timeline uses a traditional `UICollectionViewDataSource`. Insertions and deletions update the
backing turns first, then commit explicit, non-animated `performBatchUpdates`; content-only changes
reconfigure only their affected items. Model changes, disclosure requests, and parsed Markdown height
changes share one serialized collection transaction. Only readers already following the latest
message are returned to the bottom; the transaction remains closed through UICollectionView's next
self-sizing layout turn so the final target cell is materialized before queued work begins.

Compact tool and activity rows use the same direct update path: change `expandedBlockIDs`, reconfigure
that item without animation, and keep that cell's top at the same viewport position. Rapid disclosure
requests coalesce while a model or height transaction is active. The detail stack simply participates
in layout when expanded and is hidden when collapsed.

The TableView implementation maps each turn to a section and each block to a row. Structural patches
use explicit `performBatchUpdates`. A user-triggered disclosure animates only its affected row. A true
append at the latest edge commits its rows together, then follows the resolved bottom with one smooth
scroll and a short self-sizing correction when needed. History prepends,
off-screen arrivals while reading, block revisions, parsed Markdown height changes, and Reduce Motion
remain non-animated. Model, disclosure, and asynchronous height work still share one serialized update
gate.

Do not reach into the collection view to manage offsets from the host. The controller preserves a
stable block identifier and viewport-relative offset when older turns are prepended, and falls back to
a nearby surviving block if the original anchor is deleted. Both production controllers capture the
same semantic anchor during rotation or Stage Manager resize, invalidate width-sensitive layout, and
restore after the final layout pass.

Raw unified diffs without pre-parsed files are parsed by the Markdown module's actor and cached by
block ID plus revision. The timeline renders the bounded summary; Open Full Diff and Open Full Output
remain host actions, so the SDK never retains or presents unbounded content in the main list.
Fenced-code previews likewise render at most 32,000 characters and 500 lines in the timeline, label
the truncated state, and keep Copy wired to the complete source value.

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

Open Test Lab and choose **Open TableView Version** to run the same scenario, runtime, input, image
preview, and tool interactions on ``AgentTableConversationViewController``.

Use Test Lab for isolated states and <doc:TestingScenarios> to add a fixture. A production adapter
should pass reducer and integration tests for snapshot recovery, empty and non-empty history pages,
interruption, reconnect, and a user who remains scrolled away throughout a stream.
