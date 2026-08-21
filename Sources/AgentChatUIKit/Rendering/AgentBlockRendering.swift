import AgentChatCore
import UIKit

/// Environment properties that affect block rendering and accessibility.
public struct AgentRenderEnvironment: Sendable {
    /// The preferred content-size category identifier.
    public var contentSizeCategory: String
    /// Whether Reduce Motion is enabled.
    public var reduceMotionEnabled: Bool
    /// Approval requests currently awaiting runtime confirmation.
    public var resolvingApprovalIDs: Set<AgentApprovalID>
    /// Blocks expanded in local presentation state.
    public var expandedBlockIDs: Set<AgentBlockID>
    /// Whether the connected runtime accepts retry commands.
    public var canRetry: Bool
    /// The configured compact-tool visual treatment.
    public var toolPresentationStyle: AgentToolPresentationStyle
    /// Creates a render environment.
    public init(
        contentSizeCategory: String,
        reduceMotionEnabled: Bool,
        resolvingApprovalIDs: Set<AgentApprovalID> = [],
        expandedBlockIDs: Set<AgentBlockID> = [],
        canRetry: Bool = false,
        toolPresentationStyle: AgentToolPresentationStyle = .inline
    ) {
        self.contentSizeCategory = contentSizeCategory
        self.reduceMotionEnabled = reduceMotionEnabled
        self.resolvingApprovalIDs = resolvingApprovalIDs
        self.expandedBlockIDs = expandedBlockIDs
        self.canRetry = canRetry
        self.toolPresentationStyle = toolPresentationStyle
    }
}

/// UI-only actions emitted by block renderers.
public enum AgentBlockUIAction: Hashable, Sendable {
    /// Toggles local expansion state.
    case toggleExpanded(AgentBlockID)
    /// Copies safe displayed content.
    case copy(AgentBlockID)
    /// Requests host navigation to an artifact.
    case openArtifact(AgentArtifactID)
    /// Requests host navigation to a resource.
    case openFile(AgentResourceReference)
    /// Requests a host-owned full-screen image preview.
    case previewImage(reference: AgentResourceReference, alternativeText: String)
    /// Offers a URL candidate to the host.
    case openLink(URL)
    /// Retries a failed block.
    case retry(AgentBlockID)
    /// Accepts an approval choice.
    case approve(AgentApprovalResponse)
    /// Rejects an approval choice.
    case reject(AgentApprovalResponse)
    /// Emits a namespaced custom action.
    case custom(kind: String, payload: JSONValue)
}

/// Receives renderer actions without exposing a runtime connection to cells.
public struct AgentBlockActionSink: Sendable {
    private let handler: @MainActor @Sendable (AgentBlockUIAction) -> Void
    /// Creates an action sink.
    public init(_ handler: @escaping @MainActor @Sendable (AgentBlockUIAction) -> Void) {
        self.handler = handler
    }
    /// Emits an action on the main actor.
    @MainActor public func send(_ action: AgentBlockUIAction) { handler(action) }
}

/// Immutable context supplied while configuring one block item.
@MainActor
public struct AgentBlockRenderContext {
    /// The conversation identifier.
    public let conversationID: AgentConversationID
    /// The containing turn.
    public let turn: AgentTurn
    /// The target block.
    public let block: AgentBlock
    /// The available content width.
    public let availableWidth: CGFloat
    /// The active theme.
    public let theme: AgentChatTheme
    /// Accessibility and content-size environment.
    public let environment: AgentRenderEnvironment
    /// Optional host-owned image resolver.
    public let imageProvider: (any AgentImageProviding)?
    /// The renderer's UI-only action sink.
    public let actionSink: AgentBlockActionSink

    /// Creates render context.
    public init(
        conversationID: AgentConversationID,
        turn: AgentTurn,
        block: AgentBlock,
        availableWidth: CGFloat,
        theme: AgentChatTheme,
        environment: AgentRenderEnvironment,
        imageProvider: (any AgentImageProviding)? = nil,
        actionSink: AgentBlockActionSink
    ) {
        self.conversationID = conversationID
        self.turn = turn
        self.block = block
        self.availableWidth = availableWidth
        self.theme = theme
        self.environment = environment
        self.imageProvider = imageProvider
        self.actionSink = actionSink
    }
}

/// Configures collection cells for one or more block kinds.
@MainActor
public protocol AgentBlockRenderer: AnyObject {
    /// Supported namespaced kinds.
    var supportedKinds: Set<AgentBlockKind> { get }
    /// Registers reusable views.
    func register(in collectionView: UICollectionView)
    /// Dequeues and configures one block cell.
    func dequeueConfiguredCell(
        from collectionView: UICollectionView,
        at indexPath: IndexPath,
        context: AgentBlockRenderContext
    ) -> UICollectionViewCell
}

/// Optional TableView support for a block renderer.
///
/// Existing collection renderers remain source compatible. Adopt this protocol when the same custom
/// block should also appear in ``AgentTableConversationViewController``.
@MainActor
public protocol AgentTableBlockRenderer: AgentBlockRenderer {
    /// Registers reusable table cells.
    func register(in tableView: UITableView)
    /// Dequeues and configures one block table cell.
    func dequeueConfiguredCell(
        from tableView: UITableView,
        at indexPath: IndexPath,
        context: AgentBlockRenderContext
    ) -> UITableViewCell
}

/// Internal sizing hook used by the table timeline to calculate and cache a row before display.
/// Custom renderers that do not adopt it continue to use UITableView self-sizing.
@MainActor
protocol AgentTableBlockLayoutProviding: AnyObject {
    func tableRowHeight(for context: AgentBlockRenderContext) -> CGFloat
}

@MainActor
protocol AgentBlockRendererCacheManaging: AnyObject {
    func removeCachedData()
}

/// A scene-local registry that falls back safely for unknown and mismatched blocks.
@MainActor
public final class AgentBlockRendererRegistry {
    private var renderers: [AgentBlockKind: any AgentBlockRenderer] = [:]
    private let fallbackRenderer: any AgentBlockRenderer
    private let defaultTableFallbackRenderer = AgentDefaultBlockRenderer(supportedKinds: [])

    /// A fresh registry containing the in-package renderers.
    public static var `default`: AgentBlockRendererRegistry {
        let fallback = AgentDefaultBlockRenderer(supportedKinds: [])
        let registry = AgentBlockRendererRegistry(fallbackRenderer: fallback)
        registry.register(
            AgentDefaultBlockRenderer(
                supportedKinds: [
                    .userText, .markdown, .activity, .tool, .command, .fileSearch,
                    .fileOperation, .diff, .approval, .artifact, .image, .error,
                ]
            )
        )
        return registry
    }

    /// Creates a registry with an optional custom fallback.
    public init(fallbackRenderer: (any AgentBlockRenderer)? = nil) {
        self.fallbackRenderer = fallbackRenderer ?? AgentDefaultBlockRenderer(supportedKinds: [])
    }

    /// Registers or replaces renderers for the receiver's supported kinds.
    public func register(_ renderer: any AgentBlockRenderer) {
        for kind in renderer.supportedKinds { renderers[kind] = renderer }
    }

    /// Returns a renderer or the generic fallback.
    public func renderer(for kind: AgentBlockKind) -> any AgentBlockRenderer {
        renderers[kind] ?? fallbackRenderer
    }

    func renderer(for block: AgentBlock) -> any AgentBlockRenderer {
        guard block.hasCompatibleKindAndContent else { return fallbackRenderer }
        return renderer(for: block.kind)
    }

    func registerAll(in collectionView: UICollectionView) {
        fallbackRenderer.register(in: collectionView)
        var registered = Set<ObjectIdentifier>()
        for renderer in renderers.values {
            let identifier = ObjectIdentifier(renderer)
            if registered.insert(identifier).inserted { renderer.register(in: collectionView) }
        }
    }

    func tableRenderer(for block: AgentBlock) -> any AgentTableBlockRenderer {
        guard block.hasCompatibleKindAndContent,
            let renderer = renderers[block.kind] as? any AgentTableBlockRenderer
        else {
            return fallbackRenderer as? any AgentTableBlockRenderer
                ?? defaultTableFallbackRenderer
        }
        return renderer
    }

    func registerAll(in tableView: UITableView) {
        defaultTableFallbackRenderer.register(in: tableView)
        var registered = Set<ObjectIdentifier>()
        if let fallback = fallbackRenderer as? any AgentTableBlockRenderer {
            fallback.register(in: tableView)
            registered.insert(ObjectIdentifier(fallback))
        }
        for renderer in renderers.values {
            guard let tableRenderer = renderer as? any AgentTableBlockRenderer else { continue }
            let identifier = ObjectIdentifier(renderer)
            if registered.insert(identifier).inserted { tableRenderer.register(in: tableView) }
        }
    }

    func removeCachedData() {
        var cleared = Set<ObjectIdentifier>()
        let candidates: [any AgentBlockRenderer] = [fallbackRenderer] + Array(renderers.values)
        for renderer in candidates {
            let identifier = ObjectIdentifier(renderer)
            guard cleared.insert(identifier).inserted,
                let cacheManaging = renderer as? any AgentBlockRendererCacheManaging
            else { continue }
            cacheManaging.removeCachedData()
        }
        defaultTableFallbackRenderer.removeCachedData()
    }
}
