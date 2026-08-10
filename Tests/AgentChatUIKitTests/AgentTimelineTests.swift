import AgentChatCore
import UIKit
import XCTest

@testable import AgentChatUIKit

@MainActor
final class AgentTimelineTests: XCTestCase {
    func testControllerMapsTurnsToSectionsAndBlocksToItems() {
        let date = Date(timeIntervalSince1970: 0)
        let first = AgentTurn(
            id: "turn-1",
            role: .user,
            blocks: [
                .init(
                    id: "block-1",
                    kind: .userText,
                    content: .userText(.init(text: "Hello")),
                    state: .succeeded,
                    createdAt: date
                )
            ],
            state: .completed,
            createdAt: date
        )
        let second = AgentTurn(
            id: "turn-2",
            role: .assistant,
            blocks: [
                .init(
                    id: "block-2",
                    kind: .markdown,
                    content: .markdown(.init(markdown: "World", isFinal: true)),
                    state: .succeeded,
                    createdAt: date
                ),
                .init(
                    id: "block-3",
                    kind: "company.unknown",
                    content: .custom(
                        .init(
                            kind: "company.unknown",
                            payload: .object(["ok": .bool(true)]),
                            fallbackTitle: "Unknown"
                        )
                    ),
                    state: .running(progress: nil),
                    createdAt: date
                ),
            ],
            state: .completed,
            createdAt: date
        )
        let store = AgentConversationStore(
            snapshot: .init(id: "conversation", turns: [first, second])
        )
        let controller = AgentConversationViewController(store: store)
        controller.loadViewIfNeeded()
        let collectionView = controller.view.allSubviews.compactMap { $0 as? UICollectionView }
            .first
        XCTAssertEqual(collectionView?.numberOfSections, 2)
        XCTAssertEqual(collectionView?.numberOfItems(inSection: 0), 1)
        XCTAssertEqual(collectionView?.numberOfItems(inSection: 1), 2)
    }

    func testControllerDefensivelyFiltersDuplicateStableIdentifiers() {
        let date = Date(timeIntervalSince1970: 0)
        func turn(id: AgentTurnID, blockIDs: [AgentBlockID]) -> AgentTurn {
            AgentTurn(
                id: id,
                role: .assistant,
                blocks: blockIDs.map {
                    AgentBlock(
                        id: $0,
                        kind: .markdown,
                        content: .markdown(.init(markdown: $0.rawValue, isFinal: true)),
                        state: .succeeded,
                        createdAt: date
                    )
                },
                state: .completed,
                createdAt: date
            )
        }
        let store = AgentConversationStore(
            snapshot: .init(
                id: "conversation",
                turns: [
                    turn(id: "turn-1", blockIDs: ["shared"]),
                    turn(id: "turn-1", blockIDs: ["discarded-with-turn"]),
                    turn(id: "turn-2", blockIDs: ["shared", "unique"]),
                ]
            )
        )

        let controller = AgentConversationViewController(store: store)
        controller.loadViewIfNeeded()
        let collectionView = controller.view.allSubviews.compactMap { $0 as? UICollectionView }
            .first

        XCTAssertEqual(collectionView?.numberOfSections, 2)
        XCTAssertEqual(collectionView?.numberOfItems(inSection: 0), 1)
        XCTAssertEqual(collectionView?.numberOfItems(inSection: 1), 1)
    }

    func testRendererRegistryFallsBackForUnknownKind() {
        let renderer = AgentBlockRendererRegistry.default.renderer(for: "company.unknown")
        XCTAssertTrue(renderer.supportedKinds.isEmpty)
    }

    func testItemSizeCacheUsesAppearanceSensitiveKeyAndIsBounded() {
        let cache = AgentItemSizeCache(capacity: 2)
        let one = AgentItemSizeCacheKey(
            blockID: "one",
            revision: 1,
            width: 320,
            contentSizeCategory: .large,
            themeVersion: 1
        )
        let two = AgentItemSizeCacheKey(
            blockID: "two",
            revision: 1,
            width: 320,
            contentSizeCategory: .large,
            themeVersion: 1
        )
        let three = AgentItemSizeCacheKey(
            blockID: "three",
            revision: 1,
            width: 320,
            contentSizeCategory: .large,
            themeVersion: 1
        )
        cache.insert(height: 80, for: one)
        cache.insert(height: 90, for: two)
        cache.insert(height: 100, for: three)
        XCTAssertNil(cache.height(for: one))
        XCTAssertEqual(cache.height(for: three), 100)
        cache.invalidateAppearance()
        XCTAssertNil(cache.height(for: three))
    }

    func testUpdateSchedulerCoalescesBlockRevisions() async {
        let expectation = expectation(description: "flush")
        var received: AgentScheduledUpdate?
        let scheduler = AgentUpdateScheduler(
            coalescingMilliseconds: 33,
            classify: { _ in .sizeAffecting },
            flush: {
                received = $0
                expectation.fulfill()
            }
        )
        scheduler.enqueue(.reconfigureBlock("block"))
        scheduler.enqueue(.reconfigureBlock("block"))
        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(received?.sizeAffectingBlockIDs, ["block"])
        XCTAssertEqual(received?.patches.count, 2)
    }

    func testScrollAnchorSurvivesPrependAndDeletedTargetFallsBack() {
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 180),
            collectionViewLayout: fixedHeightLayout()
        )
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        var dataSource: UICollectionViewDiffableDataSource<Int, AgentBlockID>!
        dataSource = .init(collectionView: collectionView) { collectionView, indexPath, _ in
            collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, AgentBlockID>()
        snapshot.appendSections([0])
        snapshot.appendItems((0..<12).map { .init(rawValue: "block-\($0)") })
        dataSource.apply(snapshot, animatingDifferences: false)
        collectionView.layoutIfNeeded()
        collectionView.contentOffset.y = 160

        let coordinator = AgentScrollCoordinator(
            collectionView: collectionView,
            followingThreshold: 80,
            itemIdentifier: { dataSource.itemIdentifier(for: $0) },
            indexPath: { dataSource.indexPath(for: $0) },
            orderedBlockIDs: { dataSource.snapshot().itemIdentifiers }
        )
        let anchor = coordinator.captureAnchor(edge: .top)
        XCTAssertNotNil(anchor)

        snapshot.insertItems(["prepended"], beforeItem: "block-0")
        dataSource.apply(snapshot, animatingDifferences: false)
        collectionView.layoutIfNeeded()
        if let anchor { coordinator.restore(anchor) }
        let restored = coordinator.captureAnchor(edge: .top)
        XCTAssertEqual(restored?.blockID, anchor?.blockID)
        XCTAssertEqual(restored?.viewportOffset ?? 100, anchor?.viewportOffset ?? 0, accuracy: 0.5)

        if let target = anchor?.blockID {
            snapshot.deleteItems([target])
            dataSource.apply(snapshot, animatingDifferences: false)
            collectionView.layoutIfNeeded()
            coordinator.restore(anchor!)
            if case .readingHistory(let fallback) = coordinator.mode {
                XCTAssertNotNil(fallback)
                XCTAssertNotEqual(fallback?.blockID, target)
            } else {
                XCTFail("Expected reading-history fallback")
            }
        }
    }

    private func fixedHeightLayout() -> UICollectionViewCompositionalLayout {
        let size = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(40)
        )
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
        return UICollectionViewCompositionalLayout(section: .init(group: group))
    }
}

extension UIView {
    fileprivate var allSubviews: [UIView] { subviews + subviews.flatMap(\.allSubviews) }
}
