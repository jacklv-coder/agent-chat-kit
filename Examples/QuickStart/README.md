# AgentChatKit QuickStart

This project is the smallest complete host integration. It contains a real
`AgentRuntimeAdapter`, a single-consumer connection, structured runtime events, streaming Markdown,
interrupt handling, and a native conversation controller. It performs no network or model work.

```sh
cd Examples/QuickStart
xcodegen generate
xcodebuild -project AgentChatQuickStart.xcodeproj -scheme AgentChatQuickStart \
  -destination 'generic/platform=iOS Simulator' build
```

Start with `QuickStartConversationViewController.swift`, then replace the transport-free
`ReferenceRuntimeAdapter` with an adapter for your own SSE, WebSocket, or local agent runtime.
