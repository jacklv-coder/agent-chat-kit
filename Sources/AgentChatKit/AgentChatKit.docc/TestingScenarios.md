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
    scenario: AgentScenario(events: events)
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
tests, pause it for visual inspection, or release one event with `step()`. The Demo's Test Lab menu
exposes Play, Pause, Step, Reset, speed selection, and Copy Scenario JSON.

## Launch the Demo deterministically

UI tests can bypass the scenario list:

```text
launch argument: --agentchat-uitest
AGENTCHAT_SCENARIO=complete-cell-showcase
AGENTCHAT_PLAYBACK_MODE=instant | stream | paused
AGENTCHAT_PLAYBACK_RATE=0.5 | 1 | 2
```

Every built-in block should have fixtures for queued, running or streaming, succeeded, failed, and
cancelled states where applicable. Add iPhone/iPad, Light/Dark, accessibility text, expansion,
history prepend, and user-scrolled-away variants before declaring a renderer complete.
