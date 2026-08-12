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
        let visible = (tableView.indexPathsForVisibleRows ?? []).sorted {
            tableView.rectForRow(at: $0).minY < tableView.rectForRow(at: $1).minY
        }
        guard let selected = edge == .top ? visible.first : visible.last,
            let blockID = rowIdentifier(selected)
        else { return nil }

        let rowFrame = tableView.rectForRow(at: selected)
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
        rememberFallbacks(around: blockID)
        return AgentLayoutAnchor(
            blockID: blockID,
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

    func scrollToLatest() {
        guard let tableView else { return }
        isUserInteracting = false
        userInteractionCooldownUntil = nil
        mode = .followingLatest
        clearUnread()
        tableView.layoutIfNeeded()
        tableView.setContentOffset(
            CGPoint(x: tableView.contentOffset.x, y: latestOffset(in: tableView)),
            animated: false
        )
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
