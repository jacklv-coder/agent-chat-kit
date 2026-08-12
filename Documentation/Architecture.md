# Architecture

```text
Runtime-specific event
        ↓ adapter
AgentRuntimeEvent
        ↓
AgentConversationReducer actor
        ↓ AgentReductionResult
AgentConversationStore @MainActor
        ↓ stable-ID presentation patches
AgentTableConversationViewController (recommended)
or AgentConversationViewController
```

`AgentChatCore` owns immutable state and deterministic reduction. It imports Foundation only and
does not know UIKit, transport, models, tools, or persistence. `AgentChatMarkdown` converts parser
ASTs into a package-owned Sendable render document. `AgentChatUIKit` maps one turn to one table or
collection section and one block to one row or item. Renderers emit actions; they never invoke a
runtime connection.

The recommended timeline uses a native `UITableView`; a single-column
`UICollectionViewCompositionalLayout` implementation remains available for hosts that need custom
collection layouts. Package-owned scroll controllers anchor by block ID and relative offset across
history prepends, streaming height changes, keyboard changes, and size transitions. No third-party
layout type is exposed or required.

Presentation patches are classified internally:

- structural patches reconcile section/item IDs from the latest Store snapshot;
- size-affecting patches reconfigure only target items inside a stable-ID anchor transaction;
- content-only patches avoid unnecessary layout work.

`AgentUpdateScheduler` coalesces high-frequency patches in a bounded 33–80ms window.
`AgentScrollCoordinator` owns semantic modes (`followingLatest`, reading history, restoring prepend,
programmatic navigation, and user interaction). `AgentItemSizeCache` is only an optimization; UIKit
self-sizing remains authoritative.
