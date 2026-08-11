# Runtime Adapter

Translate a host runtime into one ordered event stream and one structured command channel.

## Implement the two boundaries

An ``AgentRuntimeAdapter`` creates independent ``AgentRuntimeConnection`` values. A connection must:

1. expose only capabilities the runtime actually supports;
2. allow exactly one event-stream consumer;
3. serialize event sequence numbers for that connection;
4. accept structured ``AgentRuntimeCommand`` values;
5. make `close()` idempotent and cancel producer work.

The host owns authentication, retries, transport framing, persistence, tool execution, and user
authorization. Convert transport payloads into ``AgentRuntimeEventPayload`` only after decoding and
validating them.

## Establish a baseline

Emit an authoritative ``AgentConversationSnapshot`` when a conversation is created, resumed, or
reconnected. Continue with inserts, replacements, and revisioned deltas. If a sequence gap cannot be
recovered, honor `AgentRuntimeCommand.requestSnapshot(_:)` with another authoritative snapshot.

## Stream content safely

Create a Markdown block once, then append chunks with ``AgentBlockDelta`` and strictly increasing
revisions. Finish by replacing the content with `isFinal: true`, setting the block state, and
completing the containing turn. Apply the same lifecycle discipline to command output and tool
blocks.

## Route commands explicitly

At minimum, most integrations handle:

- `AgentRuntimeCommand.submit(_:)`
- `AgentRuntimeCommand.interrupt(_:)` when the interrupt capability is present
- `AgentRuntimeCommand.retry(_:)` when retry is present
- approval and rejection commands when approvals are present
- snapshot and earlier-history requests when those capabilities are present

Never infer a host-side tool execution from rendered block content. The runtime executes tools; the
SDK reflects their state.

## Verify the adapter

Use the `AgentChatTesting` product to replay captured, redacted event fixtures before connecting a
live server. See <doc:TestingScenarios> and the complete
`Examples/QuickStart/App/ReferenceRuntimeAdapter.swift` implementation.
