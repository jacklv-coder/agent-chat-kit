# Integration

Implement `AgentRuntimeAdapter` and `AgentRuntimeConnection`, translate native runtime events to
stable, sequenced `AgentRuntimeEvent` values, then create one Store and Session per scene. Never
share a connection globally. The host remains responsible for navigation, URLs, files, artifacts,
attachments, tools, permissions, and persistence.

Start the Session after presenting the view controller, forward `.runtime` actions to
`AgentChatSession.send`, and route `.host` actions through the app's own policy layer.
