import AgentChatCore
import UIKit

/// A host-injected, concurrency-safe provider for referenced images.
public protocol AgentImageProviding: Sendable {
    /// Resolves an image without allowing Core models to own UIKit objects or network behavior.
    func image(
        for reference: AgentResourceReference,
        targetSize: CGSize,
        scale: CGFloat
    ) async throws -> UIImage
}
