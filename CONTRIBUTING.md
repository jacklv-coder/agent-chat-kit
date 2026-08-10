# Contributing

Use Swift 6 strict concurrency, document every public API, and keep `AgentChatCore` independent of
UIKit and concrete runtimes. Every behavior change requires tests and an update to
`IMPLEMENTATION_STATUS.md` and `CHANGELOG.md`.

Before opening a pull request, run the package build and all relevant simulator tests. Do not add
real API keys, model calls, shell execution, filesystem operations, analytics, or telemetry.
