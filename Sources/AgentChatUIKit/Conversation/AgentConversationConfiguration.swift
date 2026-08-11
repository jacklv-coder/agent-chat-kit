import AgentChatCore
import UIKit

/// Host actions that AgentChatKit never performs automatically.
public enum AgentHostAction: Hashable, Sendable {
    /// Open a referenced artifact.
    case openArtifact(AgentArtifactID)
    /// Open a referenced file or resource.
    case openResource(AgentResourceReference)
    /// Present a referenced image in a host-owned preview experience.
    case previewImage(reference: AgentResourceReference, alternativeText: String)
    /// Evaluate and possibly open a URL.
    case openURL(URL)
    /// Handle a namespaced action.
    case custom(kind: String, payload: JSONValue)
}

/// A routed action from the conversation UI.
public enum AgentConversationAction: Hashable, Sendable {
    /// A command for the runtime adapter.
    case runtime(AgentRuntimeCommand)
    /// An action requiring host policy or navigation.
    case host(AgentHostAction)
}

/// Handles routed conversation actions asynchronously.
public typealias AgentActionHandler =
    @MainActor @Sendable (AgentConversationAction) async throws
    -> Void

/// Conversation presentation and input policy.
@MainActor
public struct AgentConversationConfiguration {
    /// Runtime capabilities used to expose supported controls.
    public var runtimeCapabilities: AgentRuntimeCapabilities
    /// Whether hardware keyboard commands are enabled.
    public var enablesKeyboardCommands: Bool
    /// Distance from the bottom considered following latest.
    public var followingThreshold: CGFloat
    /// Maximum composer height.
    public var maximumComposerHeight: CGFloat
    /// Host-defined controls displayed in the default composer toolbar.
    public var composerAccessories: [AgentComposerAccessory]
    /// Optional compact context or runtime description shown in the composer.
    public var composerContextDescription: String?
    /// Whether drafts can be submitted while the store reports an offline state.
    public var allowsSendingWhileOffline: Bool
    /// Host-owned image resolver used by expanded image blocks.
    public var imageProvider: (any AgentImageProviding)?

    /// Creates presentation policy.
    public init(
        runtimeCapabilities: AgentRuntimeCapabilities = [],
        enablesKeyboardCommands: Bool = true,
        followingThreshold: CGFloat = 80,
        maximumComposerHeight: CGFloat = 180,
        composerAccessories: [AgentComposerAccessory] = [],
        composerContextDescription: String? = nil,
        allowsSendingWhileOffline: Bool = false,
        imageProvider: (any AgentImageProviding)? = nil
    ) {
        self.runtimeCapabilities = runtimeCapabilities
        self.enablesKeyboardCommands = enablesKeyboardCommands
        self.followingThreshold = followingThreshold
        self.maximumComposerHeight = maximumComposerHeight
        self.composerAccessories = composerAccessories
        self.composerContextDescription = composerContextDescription
        self.allowsSendingWhileOffline = allowsSendingWhileOffline
        self.imageProvider = imageProvider
    }
}

/// Host callbacks that are not runtime commands.
@MainActor
public protocol AgentConversationViewControllerDelegate: AnyObject {
    /// Requests host-provided attachment picking.
    func conversationViewControllerDidRequestAttachments(
        _ controller: AgentConversationViewController,
        sourceView: UIView
    )

    /// Requests host import of non-text item providers pasted into the composer.
    func conversationViewController(
        _ controller: AgentConversationViewController,
        didPaste itemProviders: [NSItemProvider],
        sourceView: UIView
    )

    /// Requests another preparation attempt for a failed attachment.
    func conversationViewController(
        _ controller: AgentConversationViewController,
        didRequestRetryFor attachmentID: AgentAttachmentID
    )

    /// Reports the latest draft attachments after composer-owned removal or submission.
    func conversationViewController(
        _ controller: AgentConversationViewController,
        didUpdateDraftAttachments attachments: [AgentAttachment]
    )
}

/// Default no-op implementations for optional delegate adoption.
extension AgentConversationViewControllerDelegate {
    /// Performs no attachment action.
    public func conversationViewControllerDidRequestAttachments(
        _ controller: AgentConversationViewController,
        sourceView: UIView
    ) {}

    /// Performs no pasted-item import.
    public func conversationViewController(
        _ controller: AgentConversationViewController,
        didPaste itemProviders: [NSItemProvider],
        sourceView: UIView
    ) {}

    /// Performs no attachment retry.
    public func conversationViewController(
        _ controller: AgentConversationViewController,
        didRequestRetryFor attachmentID: AgentAttachmentID
    ) {}

    /// Performs no draft attachment synchronization.
    public func conversationViewController(
        _ controller: AgentConversationViewController,
        didUpdateDraftAttachments attachments: [AgentAttachment]
    ) {}
}
