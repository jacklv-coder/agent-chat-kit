# Composer Integration

Use the default rich composer or replace it while preserving runtime-neutral actions.

## Configure supported controls

The default composer automatically exposes attachments and Stop only when the corresponding runtime
capabilities are present. Supply ``AgentComposerAccessory`` values for host concepts such as model,
reasoning level, workspace, or profile:

```swift
let configuration = AgentConversationConfiguration(
    runtimeCapabilities: [.streamingText, .attachments, .interrupt],
    composerAccessories: [
        .init(id: "model", title: "GPT-5", systemImageName: "cpu"),
        .init(id: "reasoning", title: "Medium", systemImageName: "brain"),
    ],
    composerContextDescription: "32k context"
)
```

Accessory selection is routed as the host action `agentchat.composer.accessory`; the payload contains
the stable accessory identifier. The SDK never assumes how a model or workspace is loaded.

## Own attachment bytes

Implement ``AgentConversationViewControllerDelegate`` to present a picker and handle pasted non-text
item providers. Pass portable ``AgentAttachment`` metadata to `setComposerAttachments(_:)`. Use
`setComposerAttachmentStatus(_:for:)` while preparing or uploading an item. The default attachment
strip provides remove, progress, failure, and retry affordances without retaining file permissions or
bytes. Keep host-side draft state synchronized through
`conversationViewController(_:didUpdateDraftAttachments:)`; it is called after the user removes an
item and when submission optimistically clears the draft. If submission fails, the SDK restores the
draft and reports the restored attachments again.

## Replace the composer

For a fully custom input surface, implement ``AgentComposerProviding`` and preserve the semantic
actions in ``AgentComposerAction``. Keep touch targets, Dynamic Type, VoiceOver, CJK marked-text
editing, RTL layout, hardware keyboard commands, and keyboard-safe-area behavior in the replacement.
