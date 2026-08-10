import AgentChatCore
import UIKit

struct AgentLayoutAnchor: Hashable {
    enum Edge: Hashable { case top, bottom }
    let blockID: AgentBlockID
    let edge: Edge
    let viewportOffset: CGFloat
}

enum AgentScrollMode: Hashable {
    case followingLatest
    case readingHistory(anchor: AgentLayoutAnchor?)
    case restoringAfterHistoryPrepend(AgentLayoutAnchor)
    case programmaticNavigation(target: AgentBlockID)
    case userInteracting
}
