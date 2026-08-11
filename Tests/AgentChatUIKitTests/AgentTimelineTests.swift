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

    func testComposerRendersAndRemovesIndividualAttachment() async throws {
        let attachment = AgentAttachment(
            id: "image",
            name: "architecture.png",
            mediaType: "image/png",
            byteCount: 42,
            reference: .localIdentifier("image")
        )
        let composer = AgentComposerView()
        composer.apply(.init(attachments: [attachment]))
        let actionTask = Task {
            var iterator = composer.actionStream.makeAsyncIterator()
            return await iterator.next()
        }
        let chip = try XCTUnwrap(
            composer.allSubviews.first {
                $0.accessibilityIdentifier == "AgentComposerAttachment.image"
            }
        )
        let remove = try XCTUnwrap(chip.allSubviews.compactMap { $0 as? UIButton }.last)

        remove.sendActions(for: .touchUpInside)

        let action = await actionTask.value
        XCTAssertEqual(action, .removeAttachment("image"))
        XCTAssertTrue(composer.currentState.attachments.isEmpty)
        XCTAssertTrue(
            composer.allSubviews.allSatisfy {
                $0.accessibilityIdentifier != "AgentComposerAttachment.image"
            }
        )
    }

    func testComposerRoutesHostDefinedAccessory() async throws {
        let composer = AgentComposerView()
        composer.apply(
            .init(
                accessories: [
                    .init(id: "model", title: "GPT-5", systemImageName: "cpu")
                ]
            )
        )
        let actionTask = Task {
            var iterator = composer.actionStream.makeAsyncIterator()
            return await iterator.next()
        }
        let button = try XCTUnwrap(
            composer.allSubviews.first {
                $0.accessibilityIdentifier == "AgentComposerAccessory.model"
            } as? UIButton
        )

        button.sendActions(for: .touchUpInside)

        let action = await actionTask.value
        XCTAssertEqual(action, .selectAccessory("model"))
    }

    func testComposerDoesNotRebuildControlsForIdenticalRuntimeState() throws {
        let composer = AgentComposerView()
        let state = AgentComposerState(
            accessories: [
                .init(id: "model", title: "GPT-5", systemImageName: "cpu")
            ],
            statusMessage: "Running",
            isRunning: true,
            canSend: false
        )
        composer.apply(state)
        let original = try XCTUnwrap(
            composer.allSubviews.first {
                $0.accessibilityIdentifier == "AgentComposerAccessory.model"
            } as? UIButton
        )

        composer.apply(state)

        let current = try XCTUnwrap(
            composer.allSubviews.first {
                $0.accessibilityIdentifier == "AgentComposerAccessory.model"
            } as? UIButton
        )
        XCTAssertTrue(original === current)
    }

    func testComposerRebuildsContextWhenOnlyDescriptionChanges() throws {
        let composer = AgentComposerView()
        composer.apply(.init(contextDescription: "32k"))
        let label = try XCTUnwrap(
            composer.allSubviews.first {
                $0.accessibilityIdentifier == "AgentComposerContext"
            } as? UILabel
        )
        XCTAssertEqual(label.text, "32k")
        XCTAssertNotNil(label.superview)

        composer.apply(.init(contextDescription: "18k"))

        XCTAssertEqual(label.text, "18k")
        XCTAssertNotNil(label.superview)
    }

    func testComposerBlocksSubmissionForFailedAttachment() throws {
        let composer = AgentComposerView()
        composer.apply(
            .init(
                attachments: [
                    .init(
                        id: "failed",
                        name: "failed.pdf",
                        reference: .localIdentifier("failed")
                    )
                ],
                attachmentStatuses: ["failed": .failed(message: "Upload failed")]
            )
        )
        let sendButton = try XCTUnwrap(
            composer.allSubviews.first {
                $0.accessibilityIdentifier == "AgentComposerSendButton"
            } as? UIButton
        )

        XCTAssertFalse(sendButton.isEnabled)
    }

    func testOfflineConversationDisablesComposerSubmission() throws {
        let store = AgentConversationStore(
            snapshot: .init(
                id: "offline",
                state: .offline(message: "Reconnect to send")
            )
        )
        let controller = AgentConversationViewController(store: store)
        controller.loadViewIfNeeded()
        let textView = try XCTUnwrap(
            controller.view.allSubviews.first {
                $0.accessibilityIdentifier == "AgentComposerTextView"
            } as? UITextView
        )
        let sendButton = try XCTUnwrap(
            controller.view.allSubviews.first {
                $0.accessibilityIdentifier == "AgentComposerSendButton"
            } as? UIButton
        )

        textView.text = "Should remain a draft"
        textView.delegate?.textViewDidChange?(textView)

        XCTAssertFalse(sendButton.isEnabled)
        let statusLabel =
            controller.view.allSubviews.first {
                $0.accessibilityIdentifier == "AgentComposerStatus"
            } as? UILabel
        XCTAssertEqual(statusLabel?.text, "Reconnect to send")
    }

    func testConversationReportsComposerOwnedAttachmentRemoval() async throws {
        let store = AgentConversationStore(
            snapshot: .init(id: "attachments", state: .connected)
        )
        let controller = AgentConversationViewController(
            store: store,
            configuration: .init(runtimeCapabilities: [.attachments])
        )
        let delegate = ComposerDelegateSpy()
        let update = expectation(description: "draft attachment synchronization")
        delegate.onAttachmentsChanged = { attachments in
            XCTAssertTrue(attachments.isEmpty)
            update.fulfill()
        }
        controller.delegate = delegate
        controller.loadViewIfNeeded()
        controller.setComposerAttachments([
            .init(
                id: "draft",
                name: "draft.txt",
                mediaType: "text/plain",
                reference: .localIdentifier("draft")
            )
        ])
        let chip = try XCTUnwrap(
            controller.view.allSubviews.first {
                $0.accessibilityIdentifier == "AgentComposerAttachment.draft"
            }
        )
        let remove = try XCTUnwrap(chip.allSubviews.compactMap { $0 as? UIButton }.last)

        remove.sendActions(for: .touchUpInside)

        await fulfillment(of: [update], timeout: 1)
    }

    func testEveryBuiltInBlockRendersAcrossLifecycleStateMatrix() {
        let failure = AgentFailure(code: "matrix.failure", message: "Expected failure")
        let contents: [(AgentBlockKind, AgentBlockContent)] = [
            (.userText, .userText(.init(text: "User input"))),
            (
                .markdown,
                .markdown(.init(markdown: "| A | B |\n| - | - |\n| 1 | 2 |", isFinal: true))
            ),
            (.activity, .activity(.init(title: "Thinking", detail: "Safe summary"))),
            (
                .tool,
                .tool(
                    .init(
                        toolName: "demo.tool",
                        title: "Use demo tool",
                        input: .object(["input": .string("value")]),
                        output: .object(["output": .bool(true)])
                    )
                )
            ),
            (.command, .command(.init(command: "swift test", exitCode: 0))),
            (
                .fileSearch,
                .fileSearch(
                    .init(
                        query: "AgentChatKit",
                        root: "Sources",
                        matches: [.init(path: "README.md", line: 1)],
                        totalCount: 1
                    )
                )
            ),
            (
                .fileOperation,
                .fileOperation(.init(operation: .update, path: "README.md", summary: "Updated"))
            ),
            (
                .diff,
                .diff(
                    .init(
                        title: "Change",
                        rawUnifiedDiff: "@@ -1 +1 @@\n-old\n+new"
                    )
                )
            ),
            (
                .approval,
                .approval(
                    .init(
                        approvalID: "approval",
                        title: "Continue?",
                        risk: .medium,
                        choices: [
                            .init(id: "allow", title: "Allow", role: .approve),
                            .init(id: "reject", title: "Reject", role: .reject),
                        ]
                    )
                )
            ),
            (
                .artifact,
                .artifact(
                    .init(
                        id: "artifact",
                        title: "Report",
                        reference: .runtimeURI("artifact://report")
                    )
                )
            ),
            (
                .image,
                .image(
                    .init(reference: .localIdentifier("image"), alternativeText: "Preview")
                )
            ),
            (.error, .error(.init(failure: failure))),
            (
                "company.custom",
                .custom(
                    .init(
                        kind: "company.custom",
                        payload: .object(["safe": .bool(true)]),
                        fallbackTitle: "Custom"
                    )
                )
            ),
        ]
        let states: [AgentBlockState] = [
            .queued,
            .streaming,
            .running(progress: nil),
            .running(progress: 0.5),
            .waitingForApproval,
            .succeeded,
            .failed(failure),
            .cancelled,
        ]
        let collectionView = UICollectionView(
            frame: .init(x: 0, y: 0, width: 390, height: 844),
            collectionViewLayout: fixedHeightLayout()
        )
        let registry = AgentBlockRendererRegistry.default
        registry.registerAll(in: collectionView)

        for (contentIndex, pair) in contents.enumerated() {
            for (stateIndex, state) in states.enumerated() {
                let block = AgentBlock(
                    id: .init(rawValue: "matrix-\(contentIndex)-\(stateIndex)"),
                    kind: pair.0,
                    content: pair.1,
                    state: state,
                    createdAt: .distantPast
                )
                let turn = AgentTurn(
                    id: .init(rawValue: "turn-\(contentIndex)-\(stateIndex)"),
                    role: pair.0 == .userText ? .user : .assistant,
                    blocks: [block],
                    state: .completed,
                    createdAt: .distantPast
                )

                let cell = registry.renderer(for: block).dequeueConfiguredCell(
                    from: collectionView,
                    at: .init(item: 0, section: 0),
                    context: renderContext(turn: turn, block: block)
                )

                XCTAssertFalse(
                    cell.contentView.subviews.isEmpty,
                    "Missing renderer for \(pair.0.rawValue) in state \(state)"
                )
            }
        }
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

    func testControllerPinsBottomAfterStructuralAndParsedMarkdownHeightChanges() async throws {
        let date = Date(timeIntervalSince1970: 0)
        let initialTurns = (0..<18).map { index in
            AgentTurn(
                id: .init(rawValue: "initial-turn-\(index)"),
                role: .assistant,
                blocks: [
                    .init(
                        id: .init(rawValue: "initial-block-\(index)"),
                        kind: .activity,
                        content: .activity(.init(title: "Finished step \(index)")),
                        state: .succeeded,
                        createdAt: date
                    )
                ],
                state: .completed,
                createdAt: date
            )
        }
        let store = AgentConversationStore(
            snapshot: .init(id: "bottom-pin", turns: initialTurns)
        )
        let controller = AgentConversationViewController(store: store)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let collectionView = try XCTUnwrap(
            controller.view.allSubviews.compactMap { $0 as? UICollectionView }.first
        )
        collectionView.layoutIfNeeded()
        XCTAssertEqual(distanceToBottom(in: collectionView), 0, accuracy: 0.5)

        let markdownID = AgentBlockID(rawValue: "parsed-markdown")
        let markdownTurn = AgentTurn(
            id: "markdown-turn",
            role: .assistant,
            blocks: [
                .init(
                    id: markdownID,
                    kind: .markdown,
                    content: .markdown(
                        .init(
                            markdown: """
                                ## Result

                                | Stage | Result |
                                | --- | --- |
                                | Thinking | Complete |
                                | Search | 12 matches |
                                | Tests | Passed |

                                The rendered table is intentionally taller than its estimate.
                                """,
                            isFinal: true
                        )
                    ),
                    state: .succeeded,
                    createdAt: date
                )
            ],
            state: .completed,
            createdAt: date
        )
        var updatedSnapshot = store.snapshot
        updatedSnapshot.turns.append(markdownTurn)
        store.apply(
            .init(
                snapshot: updatedSnapshot,
                patches: [.insertTurn(markdownTurn.id, index: initialTurns.count)]
            )
        )
        let applied = expectation(description: "coalesced structural update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { applied.fulfill() }
        await fulfillment(of: [applied], timeout: 1)
        controller.view.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        for cell in collectionView.visibleCells.compactMap({ $0 as? AgentBlockCell }) {
            await cell.waitForPendingRendering()
        }
        controller.view.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        XCTAssertEqual(distanceToBottom(in: collectionView), 0, accuracy: 0.5)
        XCTAssertNotNil(collectionView.cellForItem(at: .init(item: 0, section: 18)))
    }

    func testControllerReconfiguresToolExpansionWithoutAnimations() async throws {
        let date = Date(timeIntervalSince1970: 0)
        let activityBlocks = (0..<18).map { index in
            AgentBlock(
                id: .init(rawValue: "expansion-activity-\(index)"),
                kind: .activity,
                content: .activity(.init(title: "Finished step \(index)")),
                state: .succeeded,
                createdAt: date
            )
        }
        var output = AgentTextBuffer()
        output.append((0..<12).map { "test output \($0)" }.joined(separator: "\n"))
        let command = AgentBlock(
            id: "expansion-command",
            kind: .command,
            content: .command(
                .init(
                    command: "swift test --filter AgentTimelineTests", output: output, exitCode: 0)
            ),
            state: .succeeded,
            createdAt: date
        )
        let trailingBlocks = (0..<7).map { index in
            AgentBlock(
                id: .init(rawValue: "expansion-trailing-\(index)"),
                kind: .activity,
                content: .activity(.init(title: "Following result \(index)")),
                state: .succeeded,
                createdAt: date
            )
        }
        let turn = AgentTurn(
            id: "expansion-turn",
            role: .assistant,
            blocks: activityBlocks + [command] + trailingBlocks,
            state: .completed,
            createdAt: date
        )
        let store = AgentConversationStore(
            snapshot: .init(id: "expansion-animation", turns: [turn])
        )
        let controller = AgentConversationViewController(store: store)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let collectionView = try XCTUnwrap(
            controller.view.allSubviews.compactMap { $0 as? UICollectionView }.first
        )
        collectionView.layoutIfNeeded()
        let path = IndexPath(item: activityBlocks.count, section: 0)
        let cell = try XCTUnwrap(collectionView.cellForItem(at: path) as? AgentBlockCell)
        let header = try XCTUnwrap(
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventHeader"
            } as? UIControl
        )
        let collapsedHeight = cell.frame.height
        let headerY = header.convert(header.bounds, to: window).minY

        header.sendActions(for: .touchUpInside)
        let expanded = expectation(description: "expanded reconfiguration")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expanded.fulfill() }
        await fulfillment(of: [expanded], timeout: 1)
        controller.view.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let expandedCell = try XCTUnwrap(collectionView.cellForItem(at: path) as? AgentBlockCell)
        let expandedHeader = try XCTUnwrap(
            expandedCell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventHeader"
            } as? UIControl
        )
        let details = try XCTUnwrap(
            expandedCell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventDetails"
            }
        )
        XCTAssertFalse(details.isHidden)
        XCTAssertGreaterThan(expandedCell.frame.height, collapsedHeight + 20)
        XCTAssertEqual(
            expandedHeader.convert(expandedHeader.bounds, to: window).minY,
            headerY,
            accuracy: 1
        )
        XCTAssertNil(collectionView.layer.animationKeys())
        XCTAssertNil(expandedCell.layer.animationKeys())

        expandedHeader.sendActions(for: .touchUpInside)
        let collapsed = expectation(description: "collapsed reconfiguration")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { collapsed.fulfill() }
        await fulfillment(of: [collapsed], timeout: 1)
        controller.view.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let collapsedCell = try XCTUnwrap(collectionView.cellForItem(at: path) as? AgentBlockCell)
        XCTAssertEqual(collapsedCell.frame.height, collapsedHeight, accuracy: 1)
        XCTAssertNil(collectionView.layer.animationKeys())
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

    func testScrollPolicyUsesStreamingToleranceAndInteractionCooldown() {
        XCTAssertTrue(
            AgentScrollPolicy.isNearBottom(
                distanceFromBottom: 120,
                followingThreshold: 80,
                isStreaming: true
            )
        )
        XCTAssertFalse(
            AgentScrollPolicy.isNearBottom(
                distanceFromBottom: 120,
                followingThreshold: 80,
                isStreaming: false
            )
        )

        let now = Date(timeIntervalSince1970: 100)
        let deadline = AgentScrollPolicy.cooldownDeadline(after: now)
        XCTAssertTrue(
            AgentScrollPolicy.isAutomaticFollowPaused(
                isUserInteracting: false,
                cooldownUntil: deadline,
                now: now.addingTimeInterval(0.1)
            )
        )
        XCTAssertFalse(
            AgentScrollPolicy.isAutomaticFollowPaused(
                isUserInteracting: false,
                cooldownUntil: deadline,
                now: now.addingTimeInterval(0.3)
            )
        )
    }

    func testScrollCoordinatorPausesFollowBrieflyAfterManualInteraction() {
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 180),
            collectionViewLayout: fixedHeightLayout()
        )
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        let dataSource = BlockCollectionDataSource(
            ids: (0..<12).map { .init(rawValue: "cooldown-block-\($0)") }
        )
        collectionView.dataSource = dataSource
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        collectionView.contentOffset.y = max(
            0,
            collectionView.contentSize.height - collectionView.bounds.height
        )

        let coordinator = AgentScrollCoordinator(
            collectionView: collectionView,
            followingThreshold: 80,
            itemIdentifier: { dataSource.itemIdentifier(for: $0) },
            indexPath: { dataSource.indexPath(for: $0) },
            orderedBlockIDs: { dataSource.ids }
        )
        let now = Date(timeIntervalSince1970: 100)
        coordinator.userWillBeginDragging()
        coordinator.userDidEndInteraction(now: now)

        XCTAssertTrue(coordinator.isFollowingLatest)
        XCTAssertFalse(coordinator.canAutomaticallyFollowLatest(at: now.addingTimeInterval(0.1)))
        XCTAssertTrue(coordinator.canAutomaticallyFollowLatest(at: now.addingTimeInterval(0.3)))
    }

    func testJumpToLatestImmediatelyOwnsFollowIntentDuringStreamingGrowth() {
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 180),
            collectionViewLayout: fixedHeightLayout()
        )
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        let dataSource = BlockCollectionDataSource(
            ids: (0..<12).map { .init(rawValue: "jump-block-\($0)") }
        )
        collectionView.dataSource = dataSource
        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        let coordinator = AgentScrollCoordinator(
            collectionView: collectionView,
            followingThreshold: 80,
            itemIdentifier: { dataSource.itemIdentifier(for: $0) },
            indexPath: { dataSource.indexPath(for: $0) },
            orderedBlockIDs: { dataSource.ids }
        )
        collectionView.contentOffset.y = 0
        coordinator.userWillBeginDragging()
        coordinator.userDidEndInteraction()
        coordinator.receivedNewContent(count: 2)
        XCTAssertEqual(coordinator.unreadCount, 2)

        coordinator.scrollToLatest()

        XCTAssertTrue(coordinator.isFollowingLatest)
        XCTAssertTrue(coordinator.shouldAutomaticallyFollowLatest)
        XCTAssertEqual(coordinator.unreadCount, 0)
    }

    func testScrollAnchorSurvivesPrependAndDeletedTargetFallsBack() {
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 180),
            collectionViewLayout: fixedHeightLayout()
        )
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        let dataSource = BlockCollectionDataSource(
            ids: (0..<12).map { .init(rawValue: "block-\($0)") }
        )
        collectionView.dataSource = dataSource
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        collectionView.contentOffset.y = 160

        let coordinator = AgentScrollCoordinator(
            collectionView: collectionView,
            followingThreshold: 80,
            itemIdentifier: { dataSource.itemIdentifier(for: $0) },
            indexPath: { dataSource.indexPath(for: $0) },
            orderedBlockIDs: { dataSource.ids }
        )
        let anchor = coordinator.captureAnchor(edge: .top)
        XCTAssertNotNil(anchor)

        dataSource.ids.insert("prepended", at: 0)
        collectionView.performBatchUpdates {
            collectionView.insertItems(at: [IndexPath(item: 0, section: 0)])
        }
        collectionView.layoutIfNeeded()
        if let anchor { coordinator.restore(anchor) }
        let restored = coordinator.captureAnchor(edge: .top)
        XCTAssertEqual(restored?.blockID, anchor?.blockID)
        XCTAssertEqual(restored?.viewportOffset ?? 100, anchor?.viewportOffset ?? 0, accuracy: 0.5)

        if let target = anchor?.blockID,
            let deletedIndexPath = dataSource.indexPath(for: target)
        {
            dataSource.ids.remove(at: deletedIndexPath.item)
            collectionView.performBatchUpdates {
                collectionView.deleteItems(at: [deletedIndexPath])
            }
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

    private func distanceToBottom(in collectionView: UICollectionView) -> CGFloat {
        let visibleBottom =
            collectionView.contentOffset.y + collectionView.bounds.height
            - collectionView.adjustedContentInset.bottom
        return max(0, collectionView.contentSize.height - visibleBottom)
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

@MainActor
private final class BlockCollectionDataSource: NSObject, UICollectionViewDataSource {
    var ids: [AgentBlockID]

    init(ids: [AgentBlockID]) {
        self.ids = ids
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        ids.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
    }

    func itemIdentifier(for indexPath: IndexPath) -> AgentBlockID? {
        guard indexPath.section == 0, ids.indices.contains(indexPath.item) else { return nil }
        return ids[indexPath.item]
    }

    func indexPath(for id: AgentBlockID) -> IndexPath? {
        ids.firstIndex(of: id).map { IndexPath(item: $0, section: 0) }
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

@MainActor
private final class ComposerDelegateSpy: AgentConversationViewControllerDelegate {
    var onAttachmentsChanged: (([AgentAttachment]) -> Void)?

    func conversationViewController(
        _ controller: AgentConversationViewController,
        didUpdateDraftAttachments attachments: [AgentAttachment]
    ) {
        onAttachmentsChanged?(attachments)
    }
}

extension UIView {
    fileprivate var allSubviews: [UIView] { subviews + subviews.flatMap(\.allSubviews) }
}
