# Reference Review

This document records product and validation references used by AgentChatKit. References inform
behavior and acceptance criteria; their application-specific architecture is not copied into the SDK.

## OpenMinis

Local read-only reference: `doc/refrence/OpenMinis/` (ignored from this repository).

Adopted lessons:

- a debug replay surface is an acceptance tool, not a decorative sample;
- launch arguments select deterministic scenarios and instant/streaming modes;
- real session JSON can be redacted and replayed;
- scrolling must be measured for content-size jumps and visible jitter;
- long, tool-heavy, Markdown, CJK, and high-message-count scenarios need first-class fixtures.

AgentChatKit application:

- versioned `AgentScenarioDocument` JSON;
- live playback state plus resume, pause, step, replay, paused reset, and rate control in the Demo
  Test Lab;
- a diagnostics overlay with FPS, event count, and scrolling content-size jumps;
- direct scenario launch for XCUITest;
- one fixture format shared by Demo and `AgentChatTesting`.

## Hermex

Repository: <https://github.com/uzairansaruzi/hermex>

Audited commit: `83127a485ec34ff6b41bbf51235267531a71f364` (2026-08-10).

Adopted lessons:

- a complete chat page—not a cell gallery—is the primary integration artifact;
- transcript rendering, pagination, stream orchestration, and scroll policy need separate ownership;
- follow-latest intent must pause for direct manipulation and resume only through explicit bottom
  proximity or Jump to Latest;
- history prepend must preserve a stable visible item instead of restoring a raw content offset;
- the composer is a stateful subsystem rather than a text field plus Send button;
- attachment upload/error state, paste handling, focus restoration, keyboard commands, optional
  selectors, and runtime state require independent tests;
- compatibility assumptions should be explicit and machine-verifiable;
- a runnable setup path and troubleshooting map are part of product quality;
- live streaming/reconnect smoke tests complement mocked unit tests.

AgentChatKit application:

- the Demo launches directly into a complete conversation; renderer matrices remain in Test Lab;
- `AgentConversationViewController` owns the page composition while the host owns sessions,
  persistence, runtime selection, and navigation around it;
- a pure `AgentScrollPolicy` and stable-ID `AgentScrollCoordinator` encode streaming tolerance,
  interaction cooldown, unread state, explicit Jump to Latest, and history-prepend anchoring;
- cursor-addressed history pages are part of deterministic `AgentScenario` fixtures, so UI and
  integration tests exercise the same `loadEarlier` command path as a real adapter;
- a runtime-neutral rich composer with attachment strip, progress/failure/retry, non-text paste
  routing, status text, context text, and host-defined accessory controls;
- a complete CI-built QuickStart adapter instead of an undefined placeholder;
- strict event-tape validation for IDs, sequence, conversation, inserts, and revisions;
- DocC tutorials for setup, runtime adapters, composer integration, and deterministic scenarios.

Not copied:

- Hermex server endpoints, authentication, models, profiles, workspace rules, or persistence;
- app-specific view models and service coupling;
- Hermex's conversation-list and cache policy, which remain host-application concerns;
- OpenMinis product models or production chat layout.

AgentChatKit remains runtime-neutral. Hosts opt into model, reasoning, workspace, profile, voice, or
other controls through capabilities and stable custom accessory identifiers.
