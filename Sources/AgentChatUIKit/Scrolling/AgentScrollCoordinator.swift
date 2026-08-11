import AgentChatCore
import UIKit

@MainActor
final class AgentScrollCoordinator {
    private weak var collectionView: UICollectionView?
    private let followingThreshold: CGFloat
    private let itemIdentifier: (IndexPath) -> AgentBlockID?
    private let indexPath: (AgentBlockID) -> IndexPath?
    private let orderedBlockIDs: () -> [AgentBlockID]
    private var fallbackCandidates: [AgentBlockID] = []
    private var isStreaming = false
    private var isUserInteracting = false
    private var userInteractionCooldownUntil: Date?

    private(set) var mode: AgentScrollMode = .followingLatest
    private(set) var unreadCount = 0
    var didChangeUnreadCount: ((Int) -> Void)?

    init(
        collectionView: UICollectionView,
        followingThreshold: CGFloat,
        itemIdentifier: @escaping (IndexPath) -> AgentBlockID?,
        indexPath: @escaping (AgentBlockID) -> IndexPath?,
        orderedBlockIDs: @escaping () -> [AgentBlockID]
    ) {
        self.collectionView = collectionView
        self.followingThreshold = followingThreshold
        self.itemIdentifier = itemIdentifier
        self.indexPath = indexPath
        self.orderedBlockIDs = orderedBlockIDs
    }

    var isFollowingLatest: Bool {
        if case .followingLatest = mode { return true }
        return false
    }

    var shouldAutomaticallyFollowLatest: Bool {
        canAutomaticallyFollowLatest(at: Date())
    }

    func canAutomaticallyFollowLatest(at date: Date) -> Bool {
        isFollowingLatest
            && !AgentScrollPolicy.isAutomaticFollowPaused(
                isUserInteracting: isUserInteracting,
                cooldownUntil: userInteractionCooldownUntil,
                now: date
            )
    }

    func setStreaming(_ isStreaming: Bool) {
        self.isStreaming = isStreaming
    }

    func userWillBeginDragging() {
        isUserInteracting = true
        userInteractionCooldownUntil = nil
        mode = .userInteracting
    }

    func userDidScroll() {
        guard let collectionView, collectionView.isDragging || collectionView.isDecelerating else {
            return
        }
        if isNearBottom(in: collectionView) {
            mode = .followingLatest
            clearUnread()
        } else if collectionView.isDragging {
            mode = .userInteracting
        }
    }

    func userDidEndInteraction(now: Date = Date()) {
        guard let collectionView else { return }
        isUserInteracting = false
        userInteractionCooldownUntil = AgentScrollPolicy.cooldownDeadline(after: now)
        if isNearBottom(in: collectionView) {
            mode = .followingLatest
            clearUnread()
        } else {
            mode = .readingHistory(anchor: captureAnchor(edge: .top))
        }
    }

    func captureAnchor(edge: AgentLayoutAnchor.Edge) -> AgentLayoutAnchor? {
        guard let collectionView else { return nil }
        collectionView.layoutIfNeeded()
        let visible = collectionView.indexPathsForVisibleItems.sorted { lhs, rhs in
            guard let left = collectionView.layoutAttributesForItem(at: lhs),
                let right = collectionView.layoutAttributesForItem(at: rhs)
            else {
                return lhs.section == rhs.section ? lhs.item < rhs.item : lhs.section < rhs.section
            }
            return left.frame.minY < right.frame.minY
        }
        let selected = edge == .top ? visible.first : visible.last
        guard let selected,
            let blockID = itemIdentifier(selected),
            let attributes = collectionView.layoutAttributesForItem(at: selected)
        else { return nil }

        let viewportOffset: CGFloat
        switch edge {
        case .top:
            let viewportTop =
                collectionView.contentOffset.y
                + collectionView.adjustedContentInset.top
            viewportOffset = attributes.frame.minY - viewportTop
        case .bottom:
            let viewportBottom =
                collectionView.contentOffset.y + collectionView.bounds.height
                - collectionView.adjustedContentInset.bottom
            viewportOffset = attributes.frame.maxY - viewportBottom
        }
        rememberFallbacks(around: blockID)
        return AgentLayoutAnchor(
            blockID: blockID,
            edge: edge,
            viewportOffset: viewportOffset
        )
    }

    func beginHistoryPrepend() -> AgentLayoutAnchor? {
        guard let anchor = captureAnchor(edge: .top) else { return nil }
        mode = .restoringAfterHistoryPrepend(anchor)
        return anchor
    }

    func restore(_ anchor: AgentLayoutAnchor) {
        guard let collectionView else { return }
        collectionView.layoutIfNeeded()
        let resolvedID = ([anchor.blockID] + fallbackCandidates).first { indexPath($0) != nil }
        guard let resolvedID,
            let path = indexPath(resolvedID),
            let attributes = collectionView.layoutAttributesForItem(at: path)
        else {
            mode = .readingHistory(anchor: nil)
            return
        }

        let desiredY: CGFloat
        switch anchor.edge {
        case .top:
            desiredY =
                attributes.frame.minY - anchor.viewportOffset
                - collectionView.adjustedContentInset.top
        case .bottom:
            desiredY =
                attributes.frame.maxY - anchor.viewportOffset - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        }
        collectionView.setContentOffset(
            CGPoint(
                x: collectionView.contentOffset.x, y: clampedOffset(desiredY, in: collectionView)),
            animated: false
        )
        mode = .readingHistory(anchor: captureAnchor(edge: anchor.edge))
    }

    func receivedNewContent(count: Int = 1) {
        guard !isFollowingLatest else { return }
        unreadCount += max(0, count)
        didChangeUnreadCount?(unreadCount)
    }

    func scrollToLatest() {
        guard let collectionView else { return }
        isUserInteracting = false
        userInteractionCooldownUntil = nil
        mode = .followingLatest
        clearUnread()
        collectionView.layoutIfNeeded()
        let target = latestOffset(in: collectionView)
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: target),
            animated: false
        )
    }

    private func isNearBottom(in collectionView: UICollectionView) -> Bool {
        AgentScrollPolicy.isNearBottom(
            distanceFromBottom: distanceToBottom(in: collectionView),
            followingThreshold: followingThreshold,
            isStreaming: isStreaming
        )
    }

    private func rememberFallbacks(around blockID: AgentBlockID) {
        let ids = orderedBlockIDs()
        guard let position = ids.firstIndex(of: blockID) else {
            fallbackCandidates = []
            return
        }
        var candidates: [AgentBlockID] = []
        for distance in 1...max(ids.count, 1) {
            if position + distance < ids.count { candidates.append(ids[position + distance]) }
            if position >= distance { candidates.append(ids[position - distance]) }
            if candidates.count >= 16 { break }
        }
        fallbackCandidates = candidates
    }

    private func distanceToBottom(in collectionView: UICollectionView) -> CGFloat {
        let visibleBottom =
            collectionView.contentOffset.y + collectionView.bounds.height
            - collectionView.adjustedContentInset.bottom
        return max(0, collectionView.contentSize.height - visibleBottom)
    }

    private func clampedOffset(_ y: CGFloat, in collectionView: UICollectionView) -> CGFloat {
        let minimum = -collectionView.adjustedContentInset.top
        let maximum = max(
            minimum,
            collectionView.contentSize.height - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
        return min(maximum, max(minimum, y))
    }

    private func latestOffset(in collectionView: UICollectionView) -> CGFloat {
        max(
            -collectionView.adjustedContentInset.top,
            collectionView.contentSize.height - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
    }

    private func clearUnread() {
        guard unreadCount != 0 else { return }
        unreadCount = 0
        didChangeUnreadCount?(0)
    }
}
