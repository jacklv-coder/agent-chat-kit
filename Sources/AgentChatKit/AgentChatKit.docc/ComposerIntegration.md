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

For a fully custom input surface, implement ``AgentComposerProviding``. The conversation controller
installs `composer.view`, applies ``AgentComposerState`` whenever draft or runtime state changes, and
consumes the composer's single ``AgentComposerProviding/actionStream``. The following implementation
shows the complete semantic bridge; a production host can replace its visual setup with an existing
design system:

```swift
import AgentChatKit
import UIKit

@MainActor
final class ProductComposer: UIView, AgentComposerProviding, AgentComposerImportRouting {
    private let editor = UITextView()
    private var state = AgentComposerState()
    private let continuation: AsyncStream<AgentComposerAction>.Continuation

    let actionStream: AsyncStream<AgentComposerAction>
    var view: UIView { self }
    var importHandler: (([NSItemProvider], UIView) -> Void)?

    var currentState: AgentComposerState {
        var current = state
        current.text = editor.text // Always return the live, not last-applied, draft.
        return current
    }

    override init(frame: CGRect) {
        let pair = AsyncStream<AgentComposerAction>.makeStream(
            bufferingPolicy: .bufferingNewest(32)
        )
        actionStream = pair.stream
        continuation = pair.continuation
        super.init(frame: frame)

        // Add the editor, attachment controls, accessories, and Send/Stop control here.
        // Each control emits the matching AgentComposerAction through continuation.
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit { continuation.finish() }

    func apply(_ state: AgentComposerState) {
        self.state = state
        if editor.text != state.text { editor.text = state.text }
        // Render state.attachments, attachmentStatuses, accessories, statusMessage,
        // contextDescription, isRunning, canSend, and canPickAttachments here.
    }

    @discardableResult
    func focus() -> Bool { editor.becomeFirstResponder() }

    func performPrimaryAction() {
        let current = currentState
        if current.isRunning {
            continuation.yield(.stop)
            return
        }
        let text = current.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard current.canSend, !text.isEmpty || !current.attachments.isEmpty else { return }
        continuation.yield(.send(text: text, attachments: current.attachments))
    }

    func pickAttachments() { continuation.yield(.pickAttachments) }
    func removeAttachment(_ id: AgentAttachmentID) {
        continuation.yield(.removeAttachment(id))
    }
    func retryAttachment(_ id: AgentAttachmentID) {
        continuation.yield(.retryAttachment(id))
    }
    func selectAccessory(_ id: String) {
        continuation.yield(.selectAccessory(id))
    }
}

let composer = ProductComposer()
let page = AgentTableConversationViewController(
    store: store,
    configuration: configuration,
    composer: composer
)
```

Use the same `composer:` initializer on ``AgentConversationViewController`` for the collection-view
timeline. Passing `nil`, or using the original initializer without `composer:`, retains the default
``AgentComposerView`` and its existing layout and behavior.

`currentState` must always merge the text currently visible in the editor with the last applied
state. This preserves in-progress input when connection, attachment, accessory, or run state changes.
Return one stable action stream and finish its continuation when the composer is released.

Adopt ``AgentComposerImportRouting`` only when the replacement accepts pasted or dropped
`NSItemProvider` values. The controller installs the host import callback without assuming the
composer's concrete type. Implementations that do not support import can omit this protocol.

The replacement owns Dynamic Type, VoiceOver labels and traits, CJK marked-text editing, RTL layout,
keyboard-safe sizing, and minimum 44-point interaction targets. AgentChatKit supplies semantic state
and routes semantic actions; it does not implement the host's model selection, upload, runtime,
permission, persistence, or other business logic.
