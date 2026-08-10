import AgentChatCore
import UIKit

struct AgentItemSizeCacheKey: Hashable {
    let blockID: AgentBlockID
    let revision: Int64
    let widthBucket: Int
    let contentSizeCategory: UIContentSizeCategory
    let themeVersion: Int

    init(
        blockID: AgentBlockID,
        revision: Int64,
        width: CGFloat,
        contentSizeCategory: UIContentSizeCategory,
        themeVersion: Int
    ) {
        self.blockID = blockID
        self.revision = revision
        self.widthBucket = Int((width / 8).rounded())
        self.contentSizeCategory = contentSizeCategory
        self.themeVersion = themeVersion
    }
}

@MainActor
final class AgentItemSizeCache {
    private let capacity: Int
    private var values: [AgentItemSizeCacheKey: CGFloat] = [:]
    private var order: [AgentItemSizeCacheKey] = []

    init(capacity: Int = 1_024) { self.capacity = max(1, capacity) }

    func height(for key: AgentItemSizeCacheKey) -> CGFloat? {
        guard let value = values[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return value
    }

    func insert(height: CGFloat, for key: AgentItemSizeCacheKey) {
        guard height > 0 else { return }
        values[key] = height
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity {
            values.removeValue(forKey: order.removeFirst())
        }
    }

    func invalidate(blockID: AgentBlockID) {
        order.removeAll { key in
            guard key.blockID == blockID else { return false }
            values.removeValue(forKey: key)
            return true
        }
    }

    func invalidateAppearance() { removeAll() }

    func removeAll() {
        values.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
    }
}
