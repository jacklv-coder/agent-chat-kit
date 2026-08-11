import AgentChatCore
import UIKit
import XCTest

@testable import AgentChatUIKit

@MainActor
final class AgentTimelineTests: XCTestCase {
    func testComposerAcceptsTextAndEmitsSubmitAction() async {
        let composer = AgentComposerView()
        let textView =
            composer.allSubviews.first {
                $0.accessibilityIdentifier == "AgentComposerTextView"
            } as? UITextView
        let actionTask = Task {
            var iterator = composer.actionStream.makeAsyncIterator()
            return await iterator.next()
        }

        textView?.text = "Run the interactive demo"
        if let textView { composer.textViewDidChange(textView) }
        composer.submitCurrentInput()

        let action = await actionTask.value
        XCTAssertEqual(action, .send(text: "Run the interactive demo", attachments: []))
    }

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

    func testCommandAndSkillToolUseCompactIconRows() {
        var output = AgentTextBuffer()
        output.append("ok\n")
        let command = AgentBlock(
            id: "command",
            kind: .command,
            content: .command(
                .init(command: "swift test", output: output, exitCode: 0)
            ),
            state: .succeeded,
            createdAt: .distantPast
        )
        let skill = AgentBlock(
            id: "skill",
            kind: .tool,
            content: .tool(
                .init(
                    toolName: "skill.read",
                    title: "Read Computer Use skill"
                )
            ),
            state: .succeeded,
            createdAt: .distantPast
        )
        let turn = AgentTurn(
            id: "turn",
            role: .assistant,
            blocks: [command, skill],
            state: .completed,
            createdAt: .distantPast
        )
        let renderer = AgentDefaultBlockRenderer(supportedKinds: [.command, .tool])
        let collectionView = UICollectionView(
            frame: .init(x: 0, y: 0, width: 320, height: 480),
            collectionViewLayout: fixedHeightLayout()
        )
        renderer.register(in: collectionView)

        let commandCell = renderer.dequeueConfiguredCell(
            from: collectionView,
            at: .init(item: 0, section: 0),
            context: renderContext(turn: turn, block: command)
        )
        let skillCell = renderer.dequeueConfiguredCell(
            from: collectionView,
            at: .init(item: 1, section: 0),
            context: renderContext(turn: turn, block: skill)
        )

        for cell in [commandCell, skillCell] {
            XCTAssertNotNil(
                cell.contentView.allSubviews.first {
                    $0.accessibilityIdentifier == "AgentActivityEventIcon"
                } as? UIImageView
            )
            XCTAssertNotNil(
                cell.contentView.allSubviews.first {
                    $0.accessibilityIdentifier == "AgentActivityEventTitle"
                } as? UILabel
            )
        }
        let commandDetails = commandCell.contentView.allSubviews.first {
            $0.accessibilityIdentifier == "AgentActivityEventDetails"
        }
        XCTAssertEqual(commandDetails?.isHidden, true)
        XCTAssertNotNil(
            commandCell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventDisclosure"
            } as? UIImageView
        )
        XCTAssertNotNil(
            commandCell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventHeader"
            } as? UIControl
        )
    }

    func testCompactEventHeaderRoutesExpansionFromEntireRow() {
        var output = AgentTextBuffer()
        output.append("ok\n")
        let block = AgentBlock(
            id: "command",
            kind: .command,
            content: .command(.init(command: "swift test", output: output, exitCode: 0)),
            state: .succeeded,
            createdAt: .distantPast
        )
        let turn = AgentTurn(
            id: "turn",
            role: .assistant,
            blocks: [block],
            state: .completed,
            createdAt: .distantPast
        )
        var receivedAction: AgentBlockUIAction?
        let renderer = AgentDefaultBlockRenderer(supportedKinds: [.command])
        let collectionView = UICollectionView(
            frame: .init(x: 0, y: 0, width: 320, height: 480),
            collectionViewLayout: fixedHeightLayout()
        )
        renderer.register(in: collectionView)
        let cell = renderer.dequeueConfiguredCell(
            from: collectionView,
            at: .init(item: 0, section: 0),
            context: renderContext(
                turn: turn,
                block: block,
                actionSink: .init { receivedAction = $0 }
            )
        )
        let header =
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventHeader"
            } as? UIControl

        header?.sendActions(for: .touchUpInside)

        XCTAssertEqual(receivedAction, .toggleExpanded(block.id))
    }

    func testMarkdownTableUsesNativeScrollableGrid() async {
        let block = AgentBlock(
            id: "markdown-table",
            kind: .markdown,
            content: .markdown(
                .init(
                    markdown: """
                        | A | B | C | D |
                        | --- | --- | --- | --- |
                        | 1 | 2 | 3 | 4 |
                        | 5 | 6 | 7 | 8 |
                        """,
                    isFinal: true
                )
            ),
            state: .succeeded,
            createdAt: .distantPast
        )
        let turn = AgentTurn(
            id: "turn",
            role: .assistant,
            blocks: [block],
            state: .completed,
            createdAt: .distantPast
        )
        let renderer = AgentDefaultBlockRenderer(supportedKinds: [.markdown])
        let collectionView = UICollectionView(
            frame: .init(x: 0, y: 0, width: 320, height: 480),
            collectionViewLayout: fixedHeightLayout()
        )
        renderer.register(in: collectionView)
        let cell = renderer.dequeueConfiguredCell(
            from: collectionView,
            at: .init(item: 0, section: 0),
            context: renderContext(turn: turn, block: block)
        )

        await (cell as? AgentBlockCell)?.waitForPendingRendering()

        let table =
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentMarkdownTable"
            } as? UIScrollView
        let cells = cell.contentView.allSubviews.filter {
            $0.accessibilityIdentifier == "AgentMarkdownTableCell"
        }
        XCTAssertNotNil(table)
        XCTAssertEqual(cells.count, 12)
        XCTAssertEqual(table?.alwaysBounceHorizontal, true)
        XCTAssertGreaterThan(table?.intrinsicContentSize.height ?? 0, 44)
    }

    func testExpandedImageLoadsProviderPreview() async {
        let image = UIGraphicsImageRenderer(size: .init(width: 20, height: 12)).image { context in
            UIColor.systemPurple.setFill()
            context.fill(.init(x: 0, y: 0, width: 20, height: 12))
        }
        let provider = StubImageProvider(result: image)
        let block = AgentBlock(
            id: "image",
            kind: .image,
            content: .image(
                .init(
                    reference: .localIdentifier("preview"),
                    alternativeText: "Viewed 1 image"
                )
            ),
            state: .succeeded,
            createdAt: .distantPast
        )
        let turn = AgentTurn(
            id: "turn",
            role: .assistant,
            blocks: [block],
            state: .completed,
            createdAt: .distantPast
        )
        let renderer = AgentDefaultBlockRenderer(supportedKinds: [.image])
        let collectionView = UICollectionView(
            frame: .init(x: 0, y: 0, width: 320, height: 480),
            collectionViewLayout: fixedHeightLayout()
        )
        renderer.register(in: collectionView)
        var receivedAction: AgentBlockUIAction?
        let cell = renderer.dequeueConfiguredCell(
            from: collectionView,
            at: .init(item: 0, section: 0),
            context: renderContext(
                turn: turn,
                block: block,
                expandedBlockIDs: [block.id],
                imageProvider: provider,
                actionSink: .init { receivedAction = $0 }
            )
        )
        let preview =
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentInlineImagePreview"
            } as? AgentInlineImagePreviewView
        let imageView =
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentInlineImagePreviewImage"
            } as? UIImageView

        XCTAssertNotNil(preview)
        await (cell as? AgentBlockCell)?.waitForPendingRendering()
        XCTAssertNotNil(imageView?.image)
        XCTAssertEqual(preview?.accessibilityActivate(), true)
        XCTAssertEqual(
            receivedAction,
            .previewImage(reference: .localIdentifier("preview"), alternativeText: "Viewed 1 image")
        )
    }

    func testExpandedImageShowsSafeFailureFallback() async {
        let block = AgentBlock(
            id: "image-failure",
            kind: .image,
            content: .image(
                .init(
                    reference: .localIdentifier("missing"),
                    alternativeText: "Missing image"
                )
            ),
            state: .succeeded,
            createdAt: .distantPast
        )
        let turn = AgentTurn(
            id: "turn",
            role: .assistant,
            blocks: [block],
            state: .completed,
            createdAt: .distantPast
        )
        let renderer = AgentDefaultBlockRenderer(supportedKinds: [.image])
        let collectionView = UICollectionView(
            frame: .init(x: 0, y: 0, width: 320, height: 480),
            collectionViewLayout: fixedHeightLayout()
        )
        renderer.register(in: collectionView)
        let cell = renderer.dequeueConfiguredCell(
            from: collectionView,
            at: .init(item: 0, section: 0),
            context: renderContext(
                turn: turn,
                block: block,
                expandedBlockIDs: [block.id],
                imageProvider: FailingImageProvider()
            )
        )
        let messageLabel =
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentInlineImagePreviewMessage"
            } as? UILabel

        await (cell as? AgentBlockCell)?.waitForPendingRendering()
        XCTAssertEqual(messageLabel?.text, AgentStrings.imageUnavailable)
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

    private func renderContext(
        turn: AgentTurn,
        block: AgentBlock,
        expandedBlockIDs: Set<AgentBlockID> = [],
        imageProvider: (any AgentImageProviding)? = nil,
        actionSink: AgentBlockActionSink = .init { _ in }
    ) -> AgentBlockRenderContext {
        AgentBlockRenderContext(
            conversationID: "conversation",
            turn: turn,
            block: block,
            availableWidth: 320,
            theme: .system,
            environment: .init(
                contentSizeCategory: UIContentSizeCategory.large.rawValue,
                reduceMotionEnabled: false,
                expandedBlockIDs: expandedBlockIDs
            ),
            imageProvider: imageProvider,
            actionSink: actionSink
        )
    }
}

private final class StubImageProvider: AgentImageProviding, @unchecked Sendable {
    private let result: UIImage

    init(result: UIImage) {
        self.result = result
    }

    func image(
        for reference: AgentResourceReference,
        targetSize: CGSize,
        scale: CGFloat
    ) async throws -> UIImage {
        result
    }
}

private struct FailingImageProvider: AgentImageProviding {
    struct Failure: Error {}

    func image(
        for reference: AgentResourceReference,
        targetSize: CGSize,
        scale: CGFloat
    ) async throws -> UIImage {
        throw Failure()
    }
}

extension UIView {
    fileprivate var allSubviews: [UIView] { subviews + subviews.flatMap(\.allSubviews) }
}
