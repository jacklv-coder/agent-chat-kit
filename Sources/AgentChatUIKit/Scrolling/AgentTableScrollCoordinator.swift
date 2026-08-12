import AgentChatCore
import UIKit

@MainActor
final class AgentTableScrollCoordinator {
    private weak var tableView: UITableView?
    private let followingThreshold: CGFloat
    private let rowIdentifier: (IndexPath) -> AgentBlockID?
    private let indexPath: (AgentBlockID) -> IndexPath?
    private let orderedBlockIDs: () -> [AgentBlockID]
    private var fallbackCandidates: [AgentBlockID] = []
    private var isStreaming = false
    private var isUserInteracting = false
    private var userInteractionCooldownUntil: Date?
    private var latestAnimator: UIViewPropertyAnimator?
    private var latestAnimationCompletion: ((Bool) -> Void)?

    private(set) var mode: AgentScrollMode = .followingLatest
    private(set) var unreadCount = 0
    var didChangeUnreadCount: ((Int) -> Void)?

    init(
        tableView: UITableView,
        followingThreshold: CGFloat,
        rowIdentifier: @escaping (IndexPath) -> AgentBlockID?,
        indexPath: @escaping (AgentBlockID) -> IndexPath?,
        orderedBlockIDs: @escaping () -> [AgentBlockID]
    ) {
        self.tableView = tableView
        self.followingThreshold = followingThreshold
        self.rowIdentifier = rowIdentifier
        self.indexPath = indexPath
        self.orderedBlockIDs = orderedBlockIDs
    }

    var shouldAutomaticallyFollowLatest: Bool {
        isFollowingLatest
            && !AgentScrollPolicy.isAutomaticFollowPaused(
                isUserInteracting: isUserInteracting,
                cooldownUntil: userInteractionCooldownUntil,
                now: Date()
            )
    }

    func setStreaming(_ isStreaming: Bool) {
        self.isStreaming = isStreaming
    }

    func userWillBeginDragging() {
        isUserInteracting = true
        userInteractionCooldownUntil = nil
        mode = .userInteracting
        cancelLatestAnimationPreservingVisualOffset()
    }

    func userDidScroll() {
        guard let tableView, tableView.isDragging || tableView.isDecelerating else { return }
        if isNearBottom(in: tableView) {
            mode = .followingLatest
            clearUnread()
        } else if tableView.isDragging {
            mode = .userInteracting
        }
    }

    func userDidEndInteraction(now: Date = Date()) {
        guard let tableView else { return }
        isUserInteracting = false
        userInteractionCooldownUntil = AgentScrollPolicy.cooldownDeadline(after: now)
        if isNearBottom(in: tableView) {
            mode = .followingLatest
            clearUnread()
        } else {
            mode = .readingHistory(anchor: captureAnchor(edge: .top))
        }
    }

    func beginHistoryPrepend() -> AgentLayoutAnchor? {
        guard let anchor = captureAnchor(edge: .top) else { return nil }
        mode = .restoringAfterHistoryPrepend(anchor)
        return anchor
    }

    func captureAnchor(edge: AgentLayoutAnchor.Edge) -> AgentLayoutAnchor? {
        guard let tableView else { return nil }
        tableView.layoutIfNeeded()
        let visible = (tableView.indexPathsForVisibleRows ?? [])
            .compactMap { path -> (path: IndexPath, blockID: AgentBlockID)? in
                guard let blockID = rowIdentifier(path) else { return nil }
                return (path, blockID)
            }
            .sorted {
                tableView.rectForRow(at: $0.path).minY
                    < tableView.rectForRow(at: $1.path).minY
            }
        guard let selected = edge == .top ? visible.first : visible.last else { return nil }

        let rowFrame = tableView.rectForRow(at: selected.path)
        let viewportOffset: CGFloat
        switch edge {
        case .top:
            let viewportTop = tableView.contentOffset.y + tableView.adjustedContentInset.top
            viewportOffset = rowFrame.minY - viewportTop
        case .bottom:
            let viewportBottom =
                tableView.contentOffset.y + tableView.bounds.height
                - tableView.adjustedContentInset.bottom
            viewportOffset = rowFrame.maxY - viewportBottom
        }
        rememberFallbacks(around: selected.blockID)
        return AgentLayoutAnchor(
            blockID: selected.blockID,
            edge: edge,
            viewportOffset: viewportOffset
        )
    }

    func restore(_ anchor: AgentLayoutAnchor) {
        guard let tableView else { return }
        tableView.layoutIfNeeded()
        let resolvedID = ([anchor.blockID] + fallbackCandidates).first { indexPath($0) != nil }
        guard let resolvedID, let path = indexPath(resolvedID) else {
            mode = .readingHistory(anchor: nil)
            return
        }

        let rowFrame = tableView.rectForRow(at: path)
        let desiredY: CGFloat
        switch anchor.edge {
        case .top:
            desiredY = rowFrame.minY - anchor.viewportOffset - tableView.adjustedContentInset.top
        case .bottom:
            desiredY =
                rowFrame.maxY - anchor.viewportOffset - tableView.bounds.height
                + tableView.adjustedContentInset.bottom
        }
        tableView.setContentOffset(
            CGPoint(x: tableView.contentOffset.x, y: clampedOffset(desiredY, in: tableView)),
            animated: false
        )
        mode = .readingHistory(anchor: captureAnchor(edge: anchor.edge))
    }

    func receivedNewContent(count: Int = 1) {
        guard !isFollowingLatest else { return }
        unreadCount += max(0, count)
        didChangeUnreadCount?(unreadCount)
    }

    func scrollToLatest(animated: Bool = false) {
        guard let tableView else { return }
        isUserInteracting = false
        userInteractionCooldownUntil = nil
        mode = .followingLatest
        clearUnread()
        tableView.layoutIfNeeded()
        tableView.setContentOffset(
            CGPoint(x: tableView.contentOffset.x, y: latestOffset(in: tableView)),
            animated: animated
        )
    }

    func animateToLatest(
        duration: TimeInterval = 0.25,
        completion: @escaping (Bool) -> Void
    ) {
        guard let tableView, shouldAutomaticallyFollowLatest else {
            completion(false)
            return
        }
        clearUnread()
        tableView.layoutIfNeeded()
        let target = CGPoint(x: tableView.contentOffset.x, y: latestOffset(in: tableView))
        let lastPath = orderedBlockIDs().last.flatMap(indexPath)
        guard abs(target.y - tableView.contentOffset.y) > 0.5 else {
            tableView.setContentOffset(target, animated: false)
            completion(true)
            return
        }
        let animator = UIViewPropertyAnimator(duration: duration, curve: .easeOut) {
            if let lastPath {
                tableView.scrollToRow(at: lastPath, at: .bottom, animated: false)
                tableView.layoutIfNeeded()
                tableView.setContentOffset(
                    CGPoint(
                        x: tableView.contentOffset.x,
                        y: self.latestOffset(in: tableView)
                    ),
                    animated: false
                )
            } else {
                tableView.setContentOffset(target, animated: false)
            }
            tableView.layoutIfNeeded()
        }
        animator.isUserInteractionEnabled = true
        animator.addCompletion { [weak self, weak animator] position in
            guard let self, let animator, self.latestAnimator === animator else { return }
            self.latestAnimator = nil
            let completion = self.latestAnimationCompletion
            self.latestAnimationCompletion = nil
            completion?(position == .end)
        }
        latestAnimator = animator
        latestAnimationCompletion = completion
        animator.startAnimation()
    }

    private var isFollowingLatest: Bool {
        if case .followingLatest = mode { return true }
        return false
    }

    private func isNearBottom(in tableView: UITableView) -> Bool {
        let visibleBottom =
            tableView.contentOffset.y + tableView.bounds.height
            - tableView.adjustedContentInset.bottom
        let distance = max(0, tableView.contentSize.height - visibleBottom)
        return AgentScrollPolicy.isNearBottom(
            distanceFromBottom: distance,
            followingThreshold: followingThreshold,
            isStreaming: isStreaming
        )
    }

    private func latestOffset(in tableView: UITableView) -> CGFloat {
        max(
            -tableView.adjustedContentInset.top,
            tableView.contentSize.height - tableView.bounds.height
                + tableView.adjustedContentInset.bottom
        )
    }

    private func clampedOffset(_ y: CGFloat, in tableView: UITableView) -> CGFloat {
        let minimum = -tableView.adjustedContentInset.top
        let maximum = latestOffset(in: tableView)
        return min(maximum, max(minimum, y))
    }

    private func cancelLatestAnimationPreservingVisualOffset() {
        guard let tableView, let animator = latestAnimator else { return }
        let visibleOffset = tableView.layer.presentation()?.bounds.origin
        latestAnimator = nil
        let completion = latestAnimationCompletion
        latestAnimationCompletion = nil
        animator.stopAnimation(true)
        tableView.layer.removeAllAnimations()
        if let visibleOffset {
            tableView.setContentOffset(
                CGPoint(
                    x: tableView.contentOffset.x,
                    y: clampedOffset(visibleOffset.y, in: tableView)
                ),
                animated: false
            )
        }
        tableView.layoutIfNeeded()
        completion?(false)
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

    private func clearUnread() {
        guard unreadCount != 0 else { return }
        unreadCount = 0
        didChangeUnreadCount?(0)
    }
}
