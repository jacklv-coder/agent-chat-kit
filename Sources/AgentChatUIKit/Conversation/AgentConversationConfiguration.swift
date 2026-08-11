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
    /// Host-owned image resolver used by expanded image blocks.
    public var imageProvider: (any AgentImageProviding)?

    /// Creates presentation policy.
    public init(
        runtimeCapabilities: AgentRuntimeCapabilities = [],
        enablesKeyboardCommands: Bool = true,
        followingThreshold: CGFloat = 80,
        maximumComposerHeight: CGFloat = 180,
        imageProvider: (any AgentImageProviding)? = nil
    ) {
        self.runtimeCapabilities = runtimeCapabilities
        self.enablesKeyboardCommands = enablesKeyboardCommands
        self.followingThreshold = followingThreshold
        self.maximumComposerHeight = maximumComposerHeight
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
}

/// Default no-op implementations for optional delegate adoption.
extension AgentConversationViewControllerDelegate {
    /// Performs no attachment action.
    public func conversationViewControllerDidRequestAttachments(
        _ controller: AgentConversationViewController,
        sourceView: UIView
    ) {}
}
