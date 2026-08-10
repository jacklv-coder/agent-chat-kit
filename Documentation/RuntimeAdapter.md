# Runtime Adapter

Each connection exposes capabilities, a single-consumer event stream, command sending, and an
idempotent close operation. Event IDs must be unique for the conversation lifecycle; sequence
numbers must increase within a connection. If the native runtime has neither, the adapter must
synthesize them. Runtime timestamps—not UI arrival time—populate event envelopes.

Adapters must not own view controllers or update UIKit. Reconnect by emitting a complete snapshot,
which establishes a new reducer baseline.

`AgentChatTesting.MockAgentRuntime` keeps its event stream open until `close()`, rejects a second
consumer, records commands, and can synthesize offline submit, approval-resolution, and interrupt
events. Demo and integration tests use the same scripted scenario type.
