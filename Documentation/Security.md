# Security

AgentChatKit renders structured state and never executes tools, commands, HTML, URLs, or file
operations. URL actions are offered to the host for policy checks. Command output is plain text and
terminal controls are sanitized. Approval actions are one-shot and remain pending until the runtime
confirms a resolution.

Logging is opt-in and payload-free by default. Do not log prompts, outputs, diffs, attachment paths,
tokens, secrets, or file content.
