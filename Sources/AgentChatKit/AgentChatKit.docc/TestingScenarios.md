# Testing Scenarios

Use one versioned fixture for human review, integration tests, UI tests, and performance checks.

## Build a portable fixture

The `AgentChatTesting` product provides `AgentScenario`, `AgentScenarioDocument`,
`AgentScenarioPlaybackController`, and `MockAgentRuntime`:

```swift
import AgentChatTesting

let document = AgentScenarioDocument(
    id: "disconnect-during-stream",
    title: "Disconnect During Stream",
    tags: ["streaming", "reconnect"],
    scenario: AgentScenario(
        events: events,
        historyPages: [
            "before-page-2": AgentHistoryPage(
                turns: olderTurns,
                earlierCursor: "before-page-1",
                hasEarlierHistory: true
            )
        ]
    )
)
let json = try document.encodedJSON()
let replay = try AgentScenarioDocument.decodeJSON(json)
```

Scenario JSON uses a schema version and sorted keys, making redacted real-session fixtures reviewable
in source control. Do not record prompts, file paths, command output, credentials, or user data
without an explicit redaction pass.

Before replay, run `AgentRuntimeEventTapeValidator.validate` over captured events. The strict report
detects duplicate event IDs, cross-conversation envelopes, non-monotonic connection sequences,
duplicate block inserts, stale replacements, and invalid delta revisions.

## Control playback

Share one `AgentScenarioPlaybackController` with `MockAgentRuntime`. Set its rate to zero for instant
tests, pause it for visual inspection, or release one event with `step()`. When the conversation
sends `loadEarlier`, the mock resolves its cursor from `historyPages` and emits the same
`historyPage` payload required from a production adapter. The Demo's Test Lab reports Playing,
Paused, or Completed state and exposes Resume, Pause, Step, Replay Scenario, Reset Paused, speed
selection, and Copy Scenario JSON. Complete Conversation also provides Run Sample Response for a
one-tap thinking, tool, and streaming Markdown walkthrough.

## Launch the Demo deterministically

Normal launch opens `complete-conversation`. UI tests can bypass that page and select any scenario:

```text
launch argument: --agentchat-uitest
AGENTCHAT_SCENARIO=complete-cell-showcase
AGENTCHAT_PLAYBACK_MODE=instant | stream | paused
AGENTCHAT_PLAYBACK_RATE=0.5 | 1 | 2
```

Every built-in block should have fixtures for queued, running or streaming, succeeded, failed, and
cancelled states where applicable. Add iPhone/iPad, Light/Dark, accessibility text, expansion,
history prepend, explicit Jump to Latest, reconnect, and user-scrolled-away streaming variants
before declaring a conversation experience complete.

For bottom-follow regressions, cover both structural insertion and a parsed Markdown result whose
final self-sizing height differs from its estimate. Assert a zero bottom distance after layout and
verify that the same reconciliation becomes a no-op as soon as direct manipulation begins.

For disclosure regressions, assert that a visible tool row reconfigures without layer animations, keeps
the tapped header at the same viewport position, updates accessibility state, and resolves the expanded
or collapsed self-sizing height within one serialized transaction. Also enqueue a structural insertion
during rapid disclosure changes to verify that collection batches never overlap.

Run the same controller-level cases against ``AgentTableConversationViewController``. Assert the
turn-to-section and block-to-row mapping, a bottom insertion followed by parsed Markdown height growth,
rapid disclosure during a structural insertion, and viewport preservation after history sections are
prepended.
