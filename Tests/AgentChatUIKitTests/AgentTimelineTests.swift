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

    func testComposerRoutesDroppedFilesImagesTextAndURLsToHost() {
        let composer = AgentComposerView()
        let providers = [
            NSItemProvider(
                item: NSURL(string: "file:///tmp/sample.pdf"), typeIdentifier: "public.file-url"),
            NSItemProvider(object: UIImage()),
            NSItemProvider(object: "Dropped text" as NSString),
            NSItemProvider(object: NSURL(string: "https://example.com")!),
        ]
        var imported: [NSItemProvider] = []
        composer.importHandler = { providers, _ in imported = providers }

        XCTAssertTrue(composer.handleDroppedItemProviders(providers))
        XCTAssertEqual(imported.count, providers.count)
        XCTAssertTrue(composer.interactions.contains { $0 is UIDropInteraction })
    }

    func testComposerPlaceholderStaysInsideTextViewInRTL() throws {
        let composer = AgentComposerView()
        composer.semanticContentAttribute = .forceRightToLeft
        composer.frame = .init(x: 0, y: 0, width: 390, height: 180)
        composer.layoutIfNeeded()
        let textView = try XCTUnwrap(
            composer.allSubviews.compactMap { $0 as? UITextView }.first
        )
        let placeholder = try XCTUnwrap(
            textView.allSubviews.compactMap { $0 as? UILabel }.first
        )

        XCTAssertGreaterThanOrEqual(placeholder.frame.minX, 0)
        XCTAssertLessThanOrEqual(placeholder.frame.maxX, textView.bounds.maxX)
    }

    func testBlockContextMenuExposesCopyExpandOpenRetryAndApprovalChoices() throws {
        let failedFile = AgentBlock(
            id: "menu-file",
            kind: .fileOperation,
            content: .fileOperation(.init(operation: .read, path: "Sources/App.swift")),
            state: .failed(.init(code: "read.failed", message: "Failed", isRetryable: true)),
            createdAt: .distantPast
        )
        let turn = AgentTurn(
            id: "turn",
            role: .assistant,
            blocks: [failedFile],
            state: .completed,
            createdAt: .distantPast
        )
        let fileMenu = AgentBlockContextMenu.make(
            for: renderContext(turn: turn, block: failedFile, canRetry: true)
        )
        let identifiers = Set(
            fileMenu.children.compactMap { ($0 as? UIAction)?.identifier.rawValue }
        )
        XCTAssertTrue(identifiers.contains("agentchat.copy"))
        XCTAssertTrue(identifiers.contains("agentchat.expand"))
        XCTAssertTrue(identifiers.contains("agentchat.open-file"))
        XCTAssertTrue(identifiers.contains("agentchat.retry"))

        let approval = AgentBlock(
            id: "menu-approval",
            kind: .approval,
            content: .approval(
                .init(
                    approvalID: "approval",
                    title: "Allow edit?",
                    risk: .medium,
                    choices: [
                        .init(id: "approve", title: "Allow", role: .approve),
                        .init(id: "reject", title: "Reject", role: .reject),
                    ]
                )
            ),
            state: .waitingForApproval,
            createdAt: .distantPast
        )
        let approvalMenu = AgentBlockContextMenu.make(
            for: renderContext(turn: turn, block: approval)
        )
        let choiceMenu = try XCTUnwrap(
            approvalMenu.children.compactMap { $0 as? UIMenu }.first
        )
        XCTAssertEqual(choiceMenu.children.count, 2)
    }

    func testToolCopyTextUsesStableRawJSON() throws {
        let block = AgentBlock(
            id: "copy-tool",
            kind: .tool,
            content: .tool(
                .init(
                    toolName: "repository.inspect",
                    title: "Inspect repository",
                    summary: "Completed",
                    input: .object(["path": .string("Sources")]),
                    output: .object(["matchCount": .number(3)])
                )
            ),
            state: .succeeded,
            createdAt: .distantPast
        )

        let text = AgentBlockCopyText.text(for: block)
        let data = try XCTUnwrap(text.data(using: .utf8))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let input = try XCTUnwrap(object["input"] as? [String: Any])
        let output = try XCTUnwrap(object["output"] as? [String: Any])

        XCTAssertEqual(object["toolName"] as? String, "repository.inspect")
        XCTAssertEqual(input["path"] as? String, "Sources")
        XCTAssertEqual(output["matchCount"] as? Double, 3)
        XCTAssertFalse(text.contains("AgentBlockContent"))
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
        try await Task.sleep(for: .milliseconds(200))
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

    func testControllerSerializesExpansionWithStructuralInsertion() async throws {
        let date = Date(timeIntervalSince1970: 0)
        var output = AgentTextBuffer()
        output.append((0..<6).map { "queued output \($0)" }.joined(separator: "\n"))
        let command = AgentBlock(
            id: "serialized-command",
            kind: .command,
            content: .command(.init(command: "swift test", output: output, exitCode: 0)),
            state: .succeeded,
            createdAt: date
        )
        let initialTurn = AgentTurn(
            id: "serialized-turn",
            role: .assistant,
            blocks: [command],
            state: .completed,
            createdAt: date
        )
        let store = AgentConversationStore(
            snapshot: .init(id: "serialized-expansion", turns: [initialTurn])
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
        let commandPath = IndexPath(item: 0, section: 0)
        let cell = try XCTUnwrap(collectionView.cellForItem(at: commandPath) as? AgentBlockCell)
        let collapsedHeight = cell.frame.height
        let header = try XCTUnwrap(
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventHeader"
            } as? UIControl
        )

        header.sendActions(for: .touchUpInside)
        header.sendActions(for: .touchUpInside)

        let insertedBlock = AgentBlock(
            id: "serialized-result",
            kind: .activity,
            content: .activity(.init(title: "Inserted while disclosure was updating")),
            state: .succeeded,
            createdAt: date
        )
        let insertedTurn = AgentTurn(
            id: "serialized-inserted-turn",
            role: .assistant,
            blocks: [insertedBlock],
            state: .completed,
            createdAt: date
        )
        var updatedSnapshot = store.snapshot
        updatedSnapshot.turns.append(insertedTurn)
        store.apply(
            .init(
                snapshot: updatedSnapshot,
                patches: [.insertTurn(insertedTurn.id, index: 1)]
            )
        )
        let resizeAnchor = try XCTUnwrap(controller.beginViewportResize())
        window.frame.size.width = 430
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        controller.endViewportResize(restoring: resizeAnchor)

        let updateSettled = await waitUntil(timeout: 10) {
            controller.view.layoutIfNeeded()
            collectionView.layoutIfNeeded()
            guard collectionView.numberOfSections == 2,
                collectionView.cellForItem(at: .init(item: 0, section: 1)) != nil,
                let commandCell = collectionView.cellForItem(at: commandPath) as? AgentBlockCell,
                let details = commandCell.contentView.allSubviews.first(where: {
                    $0.accessibilityIdentifier == "AgentActivityEventDetails"
                })
            else { return false }
            return details.isHidden && abs(commandCell.frame.height - collapsedHeight) <= 1
        }

        XCTAssertTrue(updateSettled)
        XCTAssertEqual(collectionView.numberOfSections, 2)
        XCTAssertNotNil(collectionView.cellForItem(at: .init(item: 0, section: 1)))
        let finalCell = try XCTUnwrap(
            collectionView.cellForItem(at: commandPath) as? AgentBlockCell
        )
        let details = try XCTUnwrap(
            finalCell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventDetails"
            }
        )
        XCTAssertTrue(details.isHidden)
        XCTAssertEqual(finalCell.frame.height, collapsedHeight, accuracy: 1)
        XCTAssertNil(collectionView.layer.animationKeys())
    }

    func testControllerPreservesVisibleBlockWhenHistorySectionsArePrepended() async throws {
        let date = Date(timeIntervalSince1970: 0)
        func turn(prefix: String, index: Int) -> AgentTurn {
            AgentTurn(
                id: .init(rawValue: "\(prefix)-turn-\(index)"),
                role: .assistant,
                blocks: [
                    AgentBlock(
                        id: .init(rawValue: "\(prefix)-block-\(index)"),
                        kind: .activity,
                        content: .activity(.init(title: "\(prefix) message \(index)")),
                        state: .succeeded,
                        createdAt: date
                    )
                ],
                state: .completed,
                createdAt: date
            )
        }

        let initialTurns = (0..<24).map { turn(prefix: "current", index: $0) }
        let store = AgentConversationStore(
            snapshot: .init(
                id: "controller-history-anchor",
                turns: initialTurns,
                earlierHistoryCursor: "older",
                hasEarlierHistory: true
            )
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
        collectionView.scrollToItem(
            at: IndexPath(item: 0, section: 9),
            at: .top,
            animated: false
        )
        collectionView.layoutIfNeeded()

        let firstVisiblePath = try XCTUnwrap(
            collectionView.indexPathsForVisibleItems.min { lhs, rhs in
                let leftY = collectionView.layoutAttributesForItem(at: lhs)?.frame.minY ?? 0
                let rightY = collectionView.layoutAttributesForItem(at: rhs)?.frame.minY ?? 0
                return leftY < rightY
            }
        )
        let anchoredBlockID = initialTurns[firstVisiblePath.section].blocks[firstVisiblePath.item]
            .id
        let originalAttributes = try XCTUnwrap(
            collectionView.layoutAttributesForItem(at: firstVisiblePath)
        )
        let originalViewportOffset =
            originalAttributes.frame.minY
            - collectionView.contentOffset.y
            - collectionView.adjustedContentInset.top

        let olderTurns = (0..<5).map { turn(prefix: "older", index: $0) }
        var updatedSnapshot = store.snapshot
        updatedSnapshot.turns.insert(contentsOf: olderTurns, at: 0)
        updatedSnapshot.hasEarlierHistory = false
        updatedSnapshot.earlierHistoryCursor = nil
        store.apply(
            .init(
                snapshot: updatedSnapshot,
                patches: [
                    .prependTurns(olderTurns.map(\.id)),
                    .historyStateChanged,
                ]
            )
        )

        try await Task.sleep(for: .milliseconds(200))
        controller.view.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let anchoredSection = try XCTUnwrap(
            updatedSnapshot.turns.firstIndex { turn in
                turn.blocks.contains { $0.id == anchoredBlockID }
            }
        )
        let restoredPath = IndexPath(item: 0, section: anchoredSection)
        let restoredAttributes = try XCTUnwrap(
            collectionView.layoutAttributesForItem(at: restoredPath)
        )
        let restoredViewportOffset =
            restoredAttributes.frame.minY
            - collectionView.contentOffset.y
            - collectionView.adjustedContentInset.top

        XCTAssertEqual(collectionView.numberOfSections, initialTurns.count + olderTurns.count)
        XCTAssertEqual(restoredViewportOffset, originalViewportOffset, accuracy: 1)
    }

    func testTableControllerMapsTurnsToSectionsAndBlocksToRows() throws {
        let date = Date(timeIntervalSince1970: 0)
        let first = AgentTurn(
            id: "table-first-turn",
            role: .user,
            blocks: [
                AgentBlock(
                    id: "table-user",
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
            id: "table-second-turn",
            role: .assistant,
            blocks: [
                AgentBlock(
                    id: "table-thinking",
                    kind: .activity,
                    content: .activity(.init(title: "Thinking")),
                    state: .running(progress: nil),
                    createdAt: date
                ),
                AgentBlock(
                    id: "table-answer",
                    kind: .markdown,
                    content: .markdown(.init(markdown: "Answer", isFinal: true)),
                    state: .succeeded,
                    createdAt: date
                ),
            ],
            state: .completed,
            createdAt: date
        )
        let store = AgentConversationStore(
            snapshot: .init(id: "table-mapping", turns: [first, second])
        )
        let controller = AgentTableConversationViewController(store: store)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let tableView = try XCTUnwrap(
            controller.view.allSubviews.compactMap { $0 as? UITableView }.first
        )

        XCTAssertEqual(tableView.numberOfSections, 2)
        XCTAssertEqual(tableView.numberOfRows(inSection: 0), 2)
        XCTAssertEqual(tableView.numberOfRows(inSection: 1), 3)
        XCTAssertLessThan(tableView.rectForHeader(inSection: 0).height, 1)

        let userCell = try XCTUnwrap(
            tableView.cellForRow(at: .init(row: 0, section: 0)) as? AgentTableBlockCell
        )
        let userMetadataCell = try XCTUnwrap(
            tableView.cellForRow(at: .init(row: 1, section: 0))
                as? AgentTableTurnMetadataCell
        )
        let answerCell = try XCTUnwrap(
            tableView.cellForRow(at: .init(row: 1, section: 1)) as? AgentTableBlockCell
        )
        let assistantMetadataCell = try XCTUnwrap(
            tableView.cellForRow(at: .init(row: 2, section: 1))
                as? AgentTableTurnMetadataCell
        )
        let userTimestamp = try XCTUnwrap(
            userMetadataCell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentTurnTimestamp"
            } as? UILabel
        )
        let answerTimestamp = try XCTUnwrap(
            assistantMetadataCell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentTurnTimestamp"
            } as? UILabel
        )
        XCTAssertNil(
            userCell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentTurnTimestamp"
            }
        )
        XCTAssertNil(
            answerCell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentTurnTimestamp"
            }
        )
        XCTAssertEqual(
            userTimestamp.text,
            date.formatted(date: .omitted, time: .shortened)
        )
        XCTAssertEqual(answerTimestamp.text, userTimestamp.text)
        XCTAssertGreaterThan(
            userMetadataCell.convert(userTimestamp.bounds, from: userTimestamp).midX,
            userMetadataCell.bounds.midX
        )
        XCTAssertLessThan(
            assistantMetadataCell.convert(answerTimestamp.bounds, from: answerTimestamp).midX,
            assistantMetadataCell.bounds.midX
        )
    }

    func testTableTurnMetadataFollowsAHostRenderedCell() throws {
        let date = Date(timeIntervalSince1970: 0)
        let block = AgentBlock(
            id: "host-table-block",
            kind: "test.table.custom",
            content: .custom(
                .init(
                    kind: "test.table.custom",
                    payload: .object([:]),
                    fallbackTitle: "Host-rendered content"
                )
            ),
            state: .succeeded,
            createdAt: date
        )
        let turn = AgentTurn(
            id: "host-table-turn",
            role: .assistant,
            blocks: [block],
            state: .completed,
            createdAt: date
        )
        let registry = AgentBlockRendererRegistry.default
        registry.register(TableCustomRendererStub())
        let controller = AgentTableConversationViewController(
            store: .init(snapshot: .init(id: "host-table", turns: [turn])),
            rendererRegistry: registry
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let tableView = try XCTUnwrap(
            controller.view.allSubviews.compactMap { $0 as? UITableView }.first
        )
        tableView.layoutIfNeeded()

        XCTAssertEqual(tableView.numberOfRows(inSection: 0), 2)
        XCTAssertEqual(
            tableView.cellForRow(at: .init(row: 0, section: 0))?.accessibilityIdentifier,
            "HostTableCustomCell"
        )
        let metadataCell = try XCTUnwrap(
            tableView.cellForRow(at: .init(row: 1, section: 0))
                as? AgentTableTurnMetadataCell
        )
        let timestamp = try XCTUnwrap(
            metadataCell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentTurnTimestamp"
            } as? UILabel
        )
        XCTAssertEqual(timestamp.text, date.formatted(date: .omitted, time: .shortened))
    }

    func testTableMetadataRowTracksEmptyTurnBlockTransitions() async throws {
        let date = Date(timeIntervalSince1970: 0)
        let emptyTurn = AgentTurn(
            id: "table-empty-transition-turn",
            role: .assistant,
            blocks: [],
            state: .running,
            createdAt: date
        )
        let store = AgentConversationStore(
            snapshot: .init(id: "table-empty-transition", turns: [emptyTurn])
        )
        let controller = AgentTableConversationViewController(store: store)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let tableView = try XCTUnwrap(
            controller.view.allSubviews.compactMap { $0 as? UITableView }.first
        )
        XCTAssertEqual(tableView.numberOfRows(inSection: 0), 0)

        let block = AgentBlock(
            id: "table-empty-transition-block",
            kind: .activity,
            content: .activity(.init(title: "Started thinking")),
            state: .running(progress: nil),
            createdAt: date
        )
        var populatedSnapshot = store.snapshot
        populatedSnapshot.turns[0].blocks = [block]
        store.apply(
            .init(
                snapshot: populatedSnapshot,
                patches: [
                    .insertBlock(turnID: emptyTurn.id, blockID: block.id, index: 0)
                ]
            )
        )

        try await Task.sleep(for: .milliseconds(500))
        tableView.layoutIfNeeded()
        XCTAssertEqual(tableView.numberOfRows(inSection: 0), 2)
        XCTAssertTrue(tableView.cellForRow(at: .init(row: 0, section: 0)) is AgentTableBlockCell)
        XCTAssertTrue(
            tableView.cellForRow(at: .init(row: 1, section: 0))
                is AgentTableTurnMetadataCell
        )

        var emptiedSnapshot = populatedSnapshot
        emptiedSnapshot.turns[0].blocks = []
        store.apply(
            .init(
                snapshot: emptiedSnapshot,
                patches: [.deleteBlock(turnID: emptyTurn.id, blockID: block.id)]
            )
        )

        try await Task.sleep(for: .milliseconds(200))
        tableView.layoutIfNeeded()
        XCTAssertEqual(tableView.numberOfRows(inSection: 0), 0)
    }

    func testTimelineBatchChangesClassifiesOnlyTailInsertionsAsAppends() throws {
        let date = Date(timeIntervalSince1970: 0)
        func block(_ id: String) -> AgentBlock {
            AgentBlock(
                id: .init(rawValue: id),
                kind: .activity,
                content: .activity(.init(title: id)),
                state: .succeeded,
                createdAt: date
            )
        }
        func turn(_ id: String, blocks: [AgentBlock]) -> AgentTurn {
            AgentTurn(
                id: .init(rawValue: id),
                role: .assistant,
                blocks: blocks,
                state: .completed,
                createdAt: date
            )
        }

        let first = turn("first", blocks: [block("first-block")])
        let second = turn("second", blocks: [block("second-block")])
        let appendedTurn = turn("third", blocks: [block("third-block")])
        XCTAssertTrue(
            try XCTUnwrap(
                AgentTimelineBatchChanges(
                    from: [first, second], to: [first, second, appendedTurn])
            ).appendsAtEnd
        )

        let secondWithTailBlock = turn(
            "second",
            blocks: [block("second-block"), block("tail-block")]
        )
        XCTAssertTrue(
            try XCTUnwrap(
                AgentTimelineBatchChanges(
                    from: [first, second],
                    to: [first, secondWithTailBlock]
                )
            ).appendsAtEnd
        )

        let prepended = turn("older", blocks: [block("older-block")])
        XCTAssertFalse(
            try XCTUnwrap(
                AgentTimelineBatchChanges(from: [first, second], to: [prepended, first, second])
            ).appendsAtEnd
        )

        let firstWithMiddleBlock = turn(
            "first",
            blocks: [block("first-block"), block("middle-block")]
        )
        XCTAssertFalse(
            try XCTUnwrap(
                AgentTimelineBatchChanges(
                    from: [first, second],
                    to: [firstWithMiddleBlock, second]
                )
            ).appendsAtEnd
        )

        let emptyLastTurn = turn("empty-last", blocks: [])
        XCTAssertFalse(
            try XCTUnwrap(
                AgentTimelineBatchChanges(
                    from: [first, emptyLastTurn],
                    to: [firstWithMiddleBlock, emptyLastTurn]
                )
            ).appendsAtEnd
        )

        let populatedLastTurn = turn("empty-last", blocks: [block("new-tail-block")])
        XCTAssertTrue(
            try XCTUnwrap(
                AgentTimelineBatchChanges(
                    from: [first, emptyLastTurn],
                    to: [first, populatedLastTurn]
                )
            ).appendsAtEnd
        )
    }

    func testTableControllerPinsBottomAfterInsertionAndMarkdownHeightChange() async throws {
        let date = Date(timeIntervalSince1970: 0)
        func turn(_ index: Int) -> AgentTurn {
            AgentTurn(
                id: .init(rawValue: "table-bottom-turn-\(index)"),
                role: .assistant,
                blocks: [
                    AgentBlock(
                        id: .init(rawValue: "table-bottom-block-\(index)"),
                        kind: .activity,
                        content: .activity(.init(title: "Message \(index)")),
                        state: .succeeded,
                        createdAt: date
                    )
                ],
                state: .completed,
                createdAt: date
            )
        }
        let initialTurns = (0..<18).map(turn)
        let store = AgentConversationStore(
            snapshot: .init(id: "table-bottom", turns: initialTurns)
        )
        let controller = AgentTableConversationViewController(store: store)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let tableView = try XCTUnwrap(
            controller.view.allSubviews.compactMap { $0 as? UITableView }.first
        )
        tableView.layoutIfNeeded()

        let markdown = AgentBlock(
            id: "table-bottom-markdown",
            kind: .markdown,
            content: .markdown(
                .init(
                    markdown: """
                        | Feature | Result |
                        | --- | --- |
                        | UITableView | Ready |
                        | Streaming | Stable |

                        \(String(repeating: "A taller parsed answer.\n", count: 10))
                        """,
                    isFinal: true
                )
            ),
            state: .succeeded,
            createdAt: date
        )
        let inserted = AgentTurn(
            id: "table-bottom-inserted",
            role: .assistant,
            blocks: [markdown],
            state: .completed,
            createdAt: date
        )
        var updated = store.snapshot
        updated.turns.append(inserted)
        store.apply(
            .init(
                snapshot: updated,
                patches: [.insertTurn(inserted.id, index: initialTurns.count)]
            )
        )

        try await Task.sleep(for: .milliseconds(500))
        if let cell = tableView.cellForRow(
            at: .init(row: 0, section: initialTurns.count)
        ) as? AgentTableBlockCell {
            await cell.waitForPendingRendering()
        }
        try await Task.sleep(for: .milliseconds(100))
        tableView.layoutIfNeeded()
        let visibleBottom =
            tableView.contentOffset.y + tableView.bounds.height
            - tableView.adjustedContentInset.bottom

        XCTAssertEqual(tableView.numberOfSections, initialTurns.count + 1)
        XCTAssertEqual(max(0, tableView.contentSize.height - visibleBottom), 0, accuracy: 1)
        XCTAssertNotNil(
            tableView.cellForRow(at: .init(row: 0, section: initialTurns.count))
        )
    }

    func testTableControllerSmoothlyFollowsBatchInsertionAtBottom() async throws {
        let date = Date(timeIntervalSince1970: 0)
        func turn(_ index: Int) -> AgentTurn {
            AgentTurn(
                id: .init(rawValue: "table-batch-turn-\(index)"),
                role: .user,
                blocks: [
                    AgentBlock(
                        id: .init(rawValue: "table-batch-block-\(index)"),
                        kind: .userText,
                        content: .userText(.init(text: "Batch message \(index + 1)")),
                        state: .succeeded,
                        createdAt: date
                    )
                ],
                state: .completed,
                createdAt: date
            )
        }

        let initialTurns = (0..<18).map(turn)
        let store = AgentConversationStore(
            snapshot: .init(id: "table-batch-insertion", turns: initialTurns)
        )
        let controller = AgentTableConversationViewController(store: store)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let tableView = try XCTUnwrap(
            controller.view.allSubviews.compactMap { $0 as? UITableView }.first
        )
        tableView.layoutIfNeeded()

        let insertedTurns = (18..<26).map(turn)
        var updated = store.snapshot
        updated.turns.append(contentsOf: insertedTurns)
        var visualOffsets = [
            tableView.layer.presentation()?.bounds.origin.y ?? tableView.bounds.origin.y
        ]
        var sampleTimes = [CACurrentMediaTime()]
        var contentHeights = [tableView.contentSize.height]
        store.apply(
            .init(
                snapshot: updated,
                patches: insertedTurns.enumerated().map { offset, turn in
                    .insertTurn(turn.id, index: initialTurns.count + offset)
                }
            )
        )

        for _ in 0..<45 {
            try await Task.sleep(for: .milliseconds(16))
            visualOffsets.append(
                tableView.layer.presentation()?.bounds.origin.y ?? tableView.bounds.origin.y
            )
            sampleTimes.append(CACurrentMediaTime())
            contentHeights.append(tableView.contentSize.height)
        }
        tableView.layoutIfNeeded()

        let visibleBottom =
            tableView.contentOffset.y + tableView.bounds.height
            - tableView.adjustedContentInset.bottom
        XCTAssertEqual(tableView.numberOfSections, 26)
        XCTAssertEqual(
            max(0, tableView.contentSize.height - visibleBottom),
            0,
            accuracy: 1,
            "Offsets: \(visualOffsets); heights: \(contentHeights); model: \(tableView.contentOffset.y)"
        )

        let visualSteps = zip(visualOffsets, visualOffsets.dropFirst()).map { $1 - $0 }
        XCTAssertFalse(
            visualSteps.contains { $0 < -1 },
            "Offsets: \(visualOffsets); heights: \(contentHeights)"
        )
        let firstOffset = visualOffsets.first ?? 0
        let finalOffset = visualOffsets.last ?? firstOffset
        let traveledDistance = max(1, finalOffset - firstOffset)
        let sampleIntervals = zip(sampleTimes, sampleTimes.dropFirst()).map { $1 - $0 }
        let excessiveSteps = zip(visualSteps, sampleIntervals).filter { step, interval in
            let elapsedProgress = min(1, interval / 0.25)
            let allowedStep = max(80, traveledDistance * elapsedProgress * 2.5 + 16)
            return step > allowedStep
        }
        XCTAssertTrue(
            excessiveSteps.isEmpty,
            "Offsets: \(visualOffsets); sample times: \(sampleTimes); heights: \(contentHeights)"
        )
        let intermediateOffsets = Set(
            visualOffsets
                .filter { $0 > firstOffset + 1 && $0 < finalOffset - 1 }
                .map { Int($0.rounded()) }
        )
        XCTAssertGreaterThanOrEqual(
            intermediateOffsets.count,
            2,
            "Expected multiple presentation-layer frames; offsets: \(visualOffsets); "
                + "heights: \(contentHeights)"
        )

        let interruptedTurns = (26..<34).map(turn)
        updated.turns.append(contentsOf: interruptedTurns)
        store.apply(
            .init(
                snapshot: updated,
                patches: interruptedTurns.enumerated().map { offset, turn in
                    .insertTurn(turn.id, index: 26 + offset)
                }
            )
        )
        try await Task.sleep(for: .milliseconds(100))
        controller.scrollViewWillBeginDragging(tableView)
        let readingOffset = max(
            -tableView.adjustedContentInset.top,
            tableView.contentOffset.y - 180
        )
        tableView.setContentOffset(
            CGPoint(x: tableView.contentOffset.x, y: readingOffset),
            animated: false
        )
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(tableView.numberOfSections, 34)
        XCTAssertEqual(tableView.contentOffset.y, readingOffset, accuracy: 8)
        let interruptedVisibleBottom =
            tableView.contentOffset.y + tableView.bounds.height
            - tableView.adjustedContentInset.bottom
        XCTAssertGreaterThan(tableView.contentSize.height - interruptedVisibleBottom, 100)
    }

    func testTableControllerSerializesExpansionWithStructuralInsertion() async throws {
        let date = Date(timeIntervalSince1970: 0)
        var output = AgentTextBuffer()
        output.append((0..<6).map { "table queued output \($0)" }.joined(separator: "\n"))
        let command = AgentBlock(
            id: "table-serialized-command",
            kind: .command,
            content: .command(.init(command: "swift test", output: output, exitCode: 0)),
            state: .succeeded,
            createdAt: date
        )
        let initialTurn = AgentTurn(
            id: "table-serialized-turn",
            role: .assistant,
            blocks: [command],
            state: .completed,
            createdAt: date
        )
        let store = AgentConversationStore(
            snapshot: .init(id: "table-serialized", turns: [initialTurn])
        )
        let controller = AgentTableConversationViewController(store: store)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let tableView = try XCTUnwrap(
            controller.view.allSubviews.compactMap { $0 as? UITableView }.first
        )
        tableView.layoutIfNeeded()
        let path = IndexPath(row: 0, section: 0)
        let cell = try XCTUnwrap(tableView.cellForRow(at: path) as? AgentTableBlockCell)
        let collapsedHeight = cell.frame.height
        let header = try XCTUnwrap(
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventHeader"
            } as? UIControl
        )

        header.sendActions(for: .touchUpInside)
        header.sendActions(for: .touchUpInside)

        let insertedBlock = AgentBlock(
            id: "table-serialized-result",
            kind: .activity,
            content: .activity(.init(title: "Inserted during table disclosure")),
            state: .succeeded,
            createdAt: date
        )
        let insertedTurn = AgentTurn(
            id: "table-serialized-inserted-turn",
            role: .assistant,
            blocks: [insertedBlock],
            state: .completed,
            createdAt: date
        )
        var updated = store.snapshot
        updated.turns.append(insertedTurn)
        store.apply(
            .init(snapshot: updated, patches: [.insertTurn(insertedTurn.id, index: 1)])
        )
        let resizeAnchor = try XCTUnwrap(controller.beginViewportResize())
        window.frame.size.width = 430
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        controller.endViewportResize(restoring: resizeAnchor)

        try await Task.sleep(for: .milliseconds(700))
        controller.view.layoutIfNeeded()
        tableView.layoutIfNeeded()

        XCTAssertEqual(tableView.numberOfSections, 2)
        XCTAssertNotNil(tableView.cellForRow(at: .init(row: 0, section: 1)))
        let finalCell = try XCTUnwrap(tableView.cellForRow(at: path) as? AgentTableBlockCell)
        let details = try XCTUnwrap(
            finalCell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventDetails"
            }
        )
        XCTAssertTrue(details.isHidden)
        XCTAssertEqual(finalCell.frame.height, collapsedHeight, accuracy: 1)
        XCTAssertNil(tableView.layer.animationKeys())
    }

    func testTableControllerPreservesVisibleBlockWhenHistoryIsPrepended() async throws {
        let date = Date(timeIntervalSince1970: 0)
        func turn(prefix: String, index: Int) -> AgentTurn {
            AgentTurn(
                id: .init(rawValue: "table-\(prefix)-turn-\(index)"),
                role: .assistant,
                blocks: [
                    AgentBlock(
                        id: .init(rawValue: "table-\(prefix)-block-\(index)"),
                        kind: .activity,
                        content: .activity(.init(title: "\(prefix) message \(index)")),
                        state: .succeeded,
                        createdAt: date
                    )
                ],
                state: .completed,
                createdAt: date
            )
        }
        let initialTurns = (0..<24).map { turn(prefix: "current", index: $0) }
        let store = AgentConversationStore(
            snapshot: .init(
                id: "table-history",
                turns: initialTurns,
                earlierHistoryCursor: "older",
                hasEarlierHistory: true
            )
        )
        let controller = AgentTableConversationViewController(store: store)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let tableView = try XCTUnwrap(
            controller.view.allSubviews.compactMap { $0 as? UITableView }.first
        )
        tableView.scrollToRow(at: .init(row: 0, section: 9), at: .top, animated: false)
        tableView.layoutIfNeeded()
        let firstVisible = try XCTUnwrap(
            tableView.indexPathsForVisibleRows?.min {
                tableView.rectForRow(at: $0).minY < tableView.rectForRow(at: $1).minY
            }
        )
        let anchoredBlockID = initialTurns[firstVisible.section].blocks[firstVisible.row].id
        let originalOffset =
            tableView.rectForRow(at: firstVisible).minY
            - tableView.contentOffset.y
            - tableView.adjustedContentInset.top

        let older = (0..<5).map { turn(prefix: "older", index: $0) }
        var updated = store.snapshot
        updated.turns.insert(contentsOf: older, at: 0)
        updated.hasEarlierHistory = false
        updated.earlierHistoryCursor = nil
        store.apply(
            .init(
                snapshot: updated,
                patches: [.prependTurns(older.map(\.id)), .historyStateChanged]
            )
        )

        let section = try XCTUnwrap(
            updated.turns.firstIndex { $0.blocks.contains { $0.id == anchoredBlockID } }
        )
        let restored = IndexPath(row: 0, section: section)
        let updateSettled = await waitUntil(timeout: 10) {
            tableView.layoutIfNeeded()
            guard tableView.numberOfSections == initialTurns.count + older.count else {
                return false
            }
            let offset =
                tableView.rectForRow(at: restored).minY
                - tableView.contentOffset.y
                - tableView.adjustedContentInset.top
            return abs(offset - originalOffset) <= 1
        }
        let restoredOffset =
            tableView.rectForRow(at: restored).minY
            - tableView.contentOffset.y
            - tableView.adjustedContentInset.top

        XCTAssertTrue(updateSettled)
        XCTAssertEqual(tableView.numberOfSections, initialTurns.count + older.count)
        XCTAssertEqual(restoredOffset, originalOffset, accuracy: 1)
    }

    func testTableControllerPreservesSemanticAnchorAcrossIPadResize() async throws {
        let date = Date(timeIntervalSince1970: 0)
        func turn(_ index: Int) -> AgentTurn {
            let content: AgentBlockContent =
                index.isMultiple(of: 2)
                ? .markdown(
                    .init(
                        markdown: """
                            ## Resize item \(index)

                            \(String(repeating: "Width-sensitive Markdown content. ", count: index % 5 + 2))

                            | Width | Anchor |
                            | --- | --- |
                            | Adaptive | Stable |
                            """,
                        isFinal: true
                    )
                )
                : .tool(
                    .init(
                        toolName: "resize.inspect",
                        title: "Inspect width \(index)",
                        summary: "Expanded tool content reflows with the viewport.",
                        input: .object(["index": .number(Double(index))]),
                        output: .object(["stable": .bool(true)]),
                        displayMode: .expanded
                    )
                )
            return AgentTurn(
                id: .init(rawValue: "resize-turn-\(index)"),
                role: .assistant,
                blocks: [
                    AgentBlock(
                        id: .init(rawValue: "resize-block-\(index)"),
                        kind: content.blockKind,
                        content: content,
                        state: .succeeded,
                        createdAt: date
                    )
                ],
                state: .completed,
                createdAt: date
            )
        }
        let turns = (0..<60).map(turn)
        let store = AgentConversationStore(
            snapshot: .init(id: "resize-conversation", turns: turns)
        )
        let controller = AgentTableConversationViewController(
            store: store,
            configuration: .init(toolPresentationStyle: .capsule)
        )
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 1_024, height: 768))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let tableView = try XCTUnwrap(
            controller.view.allSubviews.compactMap { $0 as? UITableView }.first
        )
        tableView.scrollToRow(at: .init(row: 0, section: 30), at: .top, animated: false)
        tableView.layoutIfNeeded()
        controller.scrollViewWillBeginDragging(tableView)
        controller.scrollViewDidEndDragging(tableView, willDecelerate: false)
        try await Task.sleep(for: .milliseconds(150))

        var expectedAnchor = try XCTUnwrap(controller.beginViewportResize())
        XCTAssertEqual(expectedAnchor.edge, .top)
        for width: CGFloat in [760, 920, 620, 1_024] {
            window.frame.size.width = width
            controller.view.frame = window.bounds
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            controller.endViewportResize(restoring: expectedAnchor)
            try await Task.sleep(for: .milliseconds(100))

            let restored = try XCTUnwrap(controller.beginViewportResize())
            XCTAssertEqual(restored.blockID, expectedAnchor.blockID)
            XCTAssertEqual(restored.viewportOffset, expectedAnchor.viewportOffset, accuracy: 4)
            expectedAnchor = restored
        }
    }

    func testTableControllerReconfiguresVisibleMarkdownAfterViewportResize() async throws {
        let block = AgentBlock(
            id: "table-resize-markdown",
            kind: .markdown,
            content: .markdown(
                .init(
                    markdown: """
                        | Width | Content |
                        | --- | --- |
                        | Adaptive | Reconfigured after resize |
                        """,
                    isFinal: true
                )
            ),
            state: .succeeded,
            createdAt: .distantPast
        )
        let store = AgentConversationStore(
            snapshot: .init(
                id: "table-resize-conversation",
                turns: [
                    .init(
                        id: "turn",
                        role: .assistant,
                        blocks: [block],
                        state: .completed,
                        createdAt: .distantPast
                    )
                ]
            )
        )
        let controller = AgentTableConversationViewController(store: store)
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 1_024, height: 768))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let tableView = try XCTUnwrap(
            controller.view.allSubviews.compactMap { $0 as? UITableView }.first
        )
        let path = IndexPath(row: 0, section: 0)
        let cell = try XCTUnwrap(tableView.cellForRow(at: path) as? AgentTableBlockCell)
        await cell.waitForPendingRendering()
        tableView.layoutIfNeeded()
        let previousMarkdownTable = try XCTUnwrap(
            cell.contentView.allSubviews.first { $0 is AgentMarkdownTableView }
        )
        let anchor = try XCTUnwrap(controller.beginViewportResize())
        XCTAssertEqual(anchor.edge, .bottom)

        window.frame.size.width = 620
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        controller.endViewportResize(restoring: anchor)
        try await Task.sleep(for: .milliseconds(100))

        let resizedCell = try XCTUnwrap(
            tableView.cellForRow(at: path) as? AgentTableBlockCell
        )
        await resizedCell.waitForPendingRendering()
        let resizedMarkdownTable = try XCTUnwrap(
            resizedCell.contentView.allSubviews.first { $0 is AgentMarkdownTableView }
        )
        XCTAssertFalse(previousMarkdownTable === resizedMarkdownTable)
        let followingAnchor = try XCTUnwrap(controller.beginViewportResize())
        XCTAssertEqual(followingAnchor.edge, .bottom)
        controller.endViewportResize(restoring: followingAnchor)
    }

    func testCollectionControllerReconfiguresVisibleMarkdownAfterViewportResize() async throws {
        let block = AgentBlock(
            id: "collection-resize-markdown",
            kind: .markdown,
            content: .markdown(
                .init(
                    markdown: """
                        | Width | Content |
                        | --- | --- |
                        | Adaptive | Reconfigured after resize |
                        """,
                    isFinal: true
                )
            ),
            state: .succeeded,
            createdAt: .distantPast
        )
        let store = AgentConversationStore(
            snapshot: .init(
                id: "collection-resize-conversation",
                turns: [
                    .init(
                        id: "turn",
                        role: .assistant,
                        blocks: [block],
                        state: .completed,
                        createdAt: .distantPast
                    )
                ]
            )
        )
        let controller = AgentConversationViewController(store: store)
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 1_024, height: 768))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let collectionView = try XCTUnwrap(
            controller.view.allSubviews.compactMap { $0 as? UICollectionView }.first
        )
        let path = IndexPath(item: 0, section: 0)
        let cell = try XCTUnwrap(collectionView.cellForItem(at: path) as? AgentBlockCell)
        await cell.waitForPendingRendering()
        collectionView.layoutIfNeeded()
        let previousMarkdownTable = try XCTUnwrap(
            cell.contentView.allSubviews.first { $0 is AgentMarkdownTableView }
        )
        let anchor = try XCTUnwrap(controller.beginViewportResize())
        XCTAssertEqual(anchor.edge, .bottom)

        window.frame.size.width = 620
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        controller.endViewportResize(restoring: anchor)
        try await Task.sleep(for: .milliseconds(100))

        let resizedCell = try XCTUnwrap(
            collectionView.cellForItem(at: path) as? AgentBlockCell
        )
        await resizedCell.waitForPendingRendering()
        let resizedMarkdownTable = try XCTUnwrap(
            resizedCell.contentView.allSubviews.first { $0 is AgentMarkdownTableView }
        )
        XCTAssertFalse(previousMarkdownTable === resizedMarkdownTable)
        let followingAnchor = try XCTUnwrap(controller.beginViewportResize())
        XCTAssertEqual(followingAnchor.edge, .bottom)
        controller.endViewportResize(restoring: followingAnchor)
    }

    func testTableControllerRebuildsRichMarkdownForDynamicTypeChange() async throws {
        let store = dynamicTypeMarkdownStore(id: "table-dynamic-type")
        let controller = AgentTableConversationViewController(store: store)
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let tableView = try XCTUnwrap(
            controller.view.allSubviews.compactMap { $0 as? UITableView }.first
        )
        let path = IndexPath(row: 0, section: 0)
        let originalCell = try XCTUnwrap(tableView.cellForRow(at: path) as? AgentTableBlockCell)
        await originalCell.waitForPendingRendering()
        let originalMarkdown = try XCTUnwrap(
            originalCell.contentView.allSubviews.compactMap { $0 as? AgentMarkdownContentView }
                .first
        )
        let originalHeadingFont = try headingFont(in: originalMarkdown)
        let originalCodeFont = try codeFont(in: originalMarkdown)

        controller.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        NotificationCenter.default.post(
            name: UIContentSizeCategory.didChangeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(150))

        let updatedCell = try XCTUnwrap(tableView.cellForRow(at: path) as? AgentTableBlockCell)
        await updatedCell.waitForPendingRendering()
        let updatedMarkdown = try XCTUnwrap(
            updatedCell.contentView.allSubviews.compactMap { $0 as? AgentMarkdownContentView }.first
        )
        XCTAssertFalse(originalMarkdown === updatedMarkdown)
        XCTAssertGreaterThan(
            try headingFont(in: updatedMarkdown).pointSize, originalHeadingFont.pointSize)
        XCTAssertGreaterThan(
            try codeFont(in: updatedMarkdown).pointSize, originalCodeFont.pointSize)
    }

    func testCollectionControllerRebuildsRichMarkdownForDynamicTypeChange() async throws {
        let store = dynamicTypeMarkdownStore(id: "collection-dynamic-type")
        let controller = AgentConversationViewController(store: store)
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let collectionView = try XCTUnwrap(
            controller.view.allSubviews.compactMap { $0 as? UICollectionView }.first
        )
        let path = IndexPath(item: 0, section: 0)
        let originalCell = try XCTUnwrap(collectionView.cellForItem(at: path) as? AgentBlockCell)
        await originalCell.waitForPendingRendering()
        let originalMarkdown = try XCTUnwrap(
            originalCell.contentView.allSubviews.compactMap { $0 as? AgentMarkdownContentView }
                .first
        )
        let originalHeadingFont = try headingFont(in: originalMarkdown)

        controller.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        NotificationCenter.default.post(
            name: UIContentSizeCategory.didChangeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(150))

        let updatedCell = try XCTUnwrap(collectionView.cellForItem(at: path) as? AgentBlockCell)
        await updatedCell.waitForPendingRendering()
        let updatedMarkdown = try XCTUnwrap(
            updatedCell.contentView.allSubviews.compactMap { $0 as? AgentMarkdownContentView }.first
        )
        XCTAssertFalse(originalMarkdown === updatedMarkdown)
        XCTAssertGreaterThan(
            try headingFont(in: updatedMarkdown).pointSize, originalHeadingFont.pointSize)
    }

    func testTableControllerPreservesAnchorAcrossTwentyMixedHeightHistoryPages() async throws {
        let date = Date(timeIntervalSince1970: 0)
        func turn(prefix: String, index: Int) -> AgentTurn {
            let content: AgentBlockContent
            switch index % 3 {
            case 0:
                content = .markdown(
                    .init(
                        markdown: """
                            **History \(index)**

                            \(String(repeating: "A mixed-height Markdown line.\n", count: index % 5 + 1))
                            """,
                        isFinal: true
                    )
                )
            case 1:
                content = .tool(
                    .init(
                        toolName: "history.inspect",
                        title: "History tool \(index)",
                        summary: "Expanded detail for history page insertion.",
                        input: .object(["pageItem": .number(Double(index))]),
                        output: .object(["loaded": .bool(true)]),
                        displayMode: .expanded
                    )
                )
            default:
                content = .activity(
                    .init(title: "History activity \(index)", detail: "Stable identifier")
                )
            }
            return AgentTurn(
                id: .init(rawValue: "\(prefix)-turn-\(index)"),
                role: .assistant,
                blocks: [
                    AgentBlock(
                        id: .init(rawValue: "\(prefix)-block-\(index)"),
                        kind: content.blockKind,
                        content: content,
                        state: .succeeded,
                        createdAt: date
                    )
                ],
                state: .completed,
                createdAt: date
            )
        }
        let current = (0..<80).map { turn(prefix: "current", index: $0) }
        let store = AgentConversationStore(
            snapshot: .init(
                id: "twenty-page-history",
                turns: current,
                earlierHistoryCursor: "page-20",
                hasEarlierHistory: true
            )
        )
        let controller = AgentTableConversationViewController(
            store: store,
            configuration: .init(toolPresentationStyle: .capsule)
        )
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let tableView = try XCTUnwrap(
            controller.view.allSubviews.compactMap { $0 as? UITableView }.first
        )
        tableView.scrollToRow(at: .init(row: 0, section: 25), at: .top, animated: false)
        tableView.layoutIfNeeded()
        let anchoredBlockID = current[25].blocks[0].id
        let originalOffset =
            tableView.rectForRow(at: .init(row: 0, section: 25)).minY
            - tableView.contentOffset.y
            - tableView.adjustedContentInset.top

        var updated = store.snapshot
        for page in 0..<20 {
            let pageTurns = (0..<50).map {
                turn(prefix: "page-\(page)", index: page * 50 + $0)
            }
            updated.turns.insert(contentsOf: pageTurns, at: 0)
            updated.earlierHistoryCursor =
                page == 19 ? nil : AgentHistoryCursor(rawValue: "page-\(19 - page)")
            updated.hasEarlierHistory = page < 19
            store.apply(
                .init(
                    snapshot: updated,
                    patches: [
                        .prependTurns(pageTurns.map(\.id)),
                        .historyStateChanged,
                    ]
                )
            )
            let expectedSectionCount = current.count + (page + 1) * pageTurns.count
            let expectedAnchorSection = 25 + (page + 1) * pageTurns.count
            guard
                await waitUntil(
                    timeout: 15, interval: .milliseconds(25),
                    condition: {
                        tableView.layoutIfNeeded()
                        guard tableView.numberOfSections == expectedSectionCount else {
                            return false
                        }
                        let offset =
                            tableView.rectForRow(
                                at: .init(row: 0, section: expectedAnchorSection)
                            ).minY
                            - tableView.contentOffset.y
                            - tableView.adjustedContentInset.top
                        return abs(offset - originalOffset) <= 2
                    })
            else {
                XCTFail("History page \(page + 1) did not preserve its semantic anchor")
                return
            }
        }
        tableView.layoutIfNeeded()
        let section = try XCTUnwrap(
            updated.turns.firstIndex { $0.blocks.contains { $0.id == anchoredBlockID } }
        )
        let restoredOffset =
            tableView.rectForRow(at: .init(row: 0, section: section)).minY
            - tableView.contentOffset.y
            - tableView.adjustedContentInset.top

        XCTAssertEqual(tableView.numberOfSections, 1_080)
        XCTAssertEqual(restoredOffset, originalOffset, accuracy: 2)
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

    func testCapsuleCommandUsesDirectTerminalIconAndStructuredHeader() throws {
        var output = AgentTextBuffer()
        output.append("Build Succeeded\n")
        let block = AgentBlock(
            id: "capsule-command",
            kind: .command,
            content: .command(
                .init(
                    command: "xcodebuild -scheme AgentChatDemo",
                    output: output,
                    exitCode: 0,
                    duration: 7.2
                )
            ),
            state: .succeeded,
            createdAt: .distantPast,
            metadata: [
                AgentBlockMetadataKey.displayTitle: .string("Build demo application"),
                AgentBlockMetadataKey.displaySubtitle: .string("xcodebuild · 7.2s"),
            ]
        )
        let turn = AgentTurn(
            id: "turn",
            role: .assistant,
            blocks: [block],
            state: .completed,
            createdAt: .distantPast
        )
        let renderer = AgentDefaultBlockRenderer(supportedKinds: [.command])
        let collectionView = UICollectionView(
            frame: .init(x: 0, y: 0, width: 390, height: 844),
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
                toolPresentationStyle: .capsule
            )
        )
        let event = try XCTUnwrap(
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEvent"
            }
        )
        let icon = try XCTUnwrap(
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventIcon"
            } as? UIImageView
        )
        let title = try XCTUnwrap(
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventTitle"
            } as? UILabel
        )
        let stateIcon = try XCTUnwrap(
            cell.contentView.allSubviews.compactMap { $0 as? UIImageView }.first {
                $0.image == UIImage(systemName: "checkmark.circle.fill")
            }
        )

        XCTAssertEqual(event.layer.cornerRadius, 14)
        XCTAssertEqual(icon.image, UIImage(systemName: "apple.terminal"))
        let expectedIconDimension = min(32, max(20, ceil(title.font.lineHeight)))
        XCTAssertEqual(
            icon.constraints.first { $0.firstAttribute == .width }?.constant,
            expectedIconDimension
        )
        XCTAssertEqual(title.text, "Build demo application  ·  xcodebuild · 7.2s")
        XCTAssertEqual(title.numberOfLines, 0)
        XCTAssertEqual(
            title.font.pointSize,
            UIFontMetrics(forTextStyle: .subheadline).scaledFont(
                for: .systemFont(ofSize: 15, weight: .semibold)
            ).pointSize,
            accuracy: 0.01
        )
        XCTAssertEqual(stateIcon.tintColor, AgentChatTheme.system.colors.secondaryText)
        XCTAssertEqual(
            stateIcon.constraints.first { $0.firstAttribute == .width }?.constant,
            expectedIconDimension
        )
        let header = try XCTUnwrap(
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventHeader"
            }
        )
        XCTAssertTrue(header.accessibilityLabel?.contains("xcodebuild · 7.2s") == true)
        XCTAssertTrue(header.accessibilityLabel?.contains(AgentStrings.succeeded) == true)
        XCTAssertNotNil(
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventDetails"
            }
        )
    }

    func testCapsuleToolRendersExpandedDetailMetadata() throws {
        let detail = "Checked package targets and dependency boundaries."
        let block = AgentBlock(
            id: "tool-detail",
            kind: .tool,
            content: .tool(.init(toolName: "repository.inspect", title: "Inspect repository")),
            state: .succeeded,
            createdAt: .distantPast,
            metadata: [AgentBlockMetadataKey.expandedDetail: .string(detail)]
        )
        let turn = AgentTurn(
            id: "turn",
            role: .assistant,
            blocks: [block],
            state: .completed,
            createdAt: .distantPast
        )
        let renderer = AgentDefaultBlockRenderer(supportedKinds: [.tool])
        let collectionView = UICollectionView(
            frame: .init(x: 0, y: 0, width: 390, height: 844),
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
                toolPresentationStyle: .capsule
            )
        )

        XCTAssertNotNil(
            cell.contentView.allSubviews.first {
                ($0 as? UILabel)?.text == detail
            }
        )
    }

    func testReasoningActivityKeepsInlineThinkingTreatmentInCapsuleMode() throws {
        let block = AgentBlock(
            id: "reasoning",
            kind: .activity,
            content: .activity(.init(title: "Runtime reasoning", detail: "Safe summary")),
            state: .running(progress: nil),
            createdAt: .distantPast,
            metadata: [AgentBlockMetadataKey.activityKind: .string("reasoning")]
        )
        let turn = AgentTurn(
            id: "turn",
            role: .assistant,
            blocks: [block],
            state: .running,
            createdAt: .distantPast
        )
        let renderer = AgentDefaultBlockRenderer(supportedKinds: [.activity])
        let collectionView = UICollectionView(
            frame: .init(x: 0, y: 0, width: 390, height: 844),
            collectionViewLayout: fixedHeightLayout()
        )
        renderer.register(in: collectionView)
        let cell = renderer.dequeueConfiguredCell(
            from: collectionView,
            at: .init(item: 0, section: 0),
            context: renderContext(
                turn: turn,
                block: block,
                toolPresentationStyle: .capsule
            )
        )
        let event = try XCTUnwrap(
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEvent"
            }
        )
        let title = try XCTUnwrap(
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventTitle"
            } as? UILabel
        )
        let icon = try XCTUnwrap(
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventIcon"
            } as? UIImageView
        )

        XCTAssertEqual(event.layer.cornerRadius, 0)
        XCTAssertEqual(title.text, "\(AgentStrings.thinking) Safe summary")
        XCTAssertEqual(icon.tintColor, AgentChatTheme.system.colors.secondaryText)
        XCTAssertEqual(
            title.font.pointSize,
            UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
            accuracy: 0.01
        )
    }

    func testReasoningActivityInfersSemanticIconFromTitle() throws {
        let block = AgentBlock(
            id: "inferred-reasoning",
            kind: .activity,
            content: .activity(.init(title: "Runtime activity")),
            state: .succeeded,
            createdAt: .distantPast,
            metadata: [
                AgentBlockMetadataKey.displayTitle: .string("Reasoning completed")
            ]
        )
        let turn = AgentTurn(
            id: "turn",
            role: .assistant,
            blocks: [block],
            state: .completed,
            createdAt: .distantPast
        )
        let renderer = AgentDefaultBlockRenderer(supportedKinds: [.activity])
        let collectionView = UICollectionView(
            frame: .init(x: 0, y: 0, width: 390, height: 844),
            collectionViewLayout: fixedHeightLayout()
        )
        renderer.register(in: collectionView)
        let cell = renderer.dequeueConfiguredCell(
            from: collectionView,
            at: .init(item: 0, section: 0),
            context: renderContext(
                turn: turn,
                block: block,
                toolPresentationStyle: .capsule
            )
        )
        let event = try XCTUnwrap(
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEvent"
            }
        )
        let icon = try XCTUnwrap(
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventIcon"
            } as? UIImageView
        )
        let title = try XCTUnwrap(
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventTitle"
            } as? UILabel
        )

        XCTAssertEqual(event.layer.cornerRadius, 0)
        XCTAssertEqual(icon.image, UIImage(systemName: "brain.head.profile"))
        XCTAssertEqual(title.text, "Reasoning completed")
    }

    func testCompactHeaderScalesIconsAndExpandsAnOverflowingSummary() throws {
        func makeHeader(isExpanded: Bool) -> AgentCompactEventHeaderControl {
            AgentCompactEventHeaderControl(
                icon: UIImage(systemName: "apple.terminal"),
                iconTint: AgentChatTheme.system.colors.secondaryText,
                title: "Ran a command with a deliberately long title that needs more space",
                subtitle: "swift · 1.2s",
                titleColor: AgentChatTheme.system.colors.primaryText,
                subtitleColor: AgentChatTheme.system.colors.secondaryText,
                textStyle: .subheadline,
                contentSizeCategory: .accessibilityLarge,
                state: .succeeded,
                destructiveColor: AgentChatTheme.system.colors.destructive,
                style: .capsule,
                isExpanded: isExpanded,
                hasDetails: true,
                activation: {}
            )
        }

        let collapsed = makeHeader(isExpanded: false)
        let expanded = makeHeader(isExpanded: true)
        let collapsedTitle = try XCTUnwrap(
            collapsed.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventTitle"
            } as? UILabel
        )
        let expandedTitle = try XCTUnwrap(
            expanded.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventTitle"
            } as? UILabel
        )
        let leadingIcon = try XCTUnwrap(
            collapsed.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventIcon"
            } as? UIImageView
        )
        let stateIcon = try XCTUnwrap(
            collapsed.allSubviews.compactMap { $0 as? UIImageView }.first {
                $0.image == UIImage(systemName: "checkmark.circle.fill")
            }
        )
        let iconDimension = try XCTUnwrap(
            leadingIcon.constraints.first { $0.firstAttribute == .width }?.constant
        )

        XCTAssertEqual(collapsedTitle.numberOfLines, 1)
        XCTAssertEqual(expandedTitle.numberOfLines, 0)
        XCTAssertTrue(collapsedTitle.text?.contains("swift · 1.2s") == true)
        XCTAssertGreaterThan(iconDimension, 18)
        XCTAssertEqual(
            stateIcon.constraints.first { $0.firstAttribute == .width }?.constant,
            iconDimension
        )
    }

    func testCapsuleFailureExposesRetryAndRoutesTheBlockID() throws {
        let block = AgentBlock(
            id: "failed-tool",
            kind: .tool,
            content: .tool(
                .init(toolName: "package.publish", title: "Publish package")
            ),
            state: .failed(
                .init(code: "publish.failed", message: "Publish failed", isRetryable: true)
            ),
            createdAt: .distantPast
        )
        let turn = AgentTurn(
            id: "turn",
            role: .assistant,
            blocks: [block],
            state: .completed,
            createdAt: .distantPast
        )
        let renderer = AgentDefaultBlockRenderer(supportedKinds: [.tool])
        let collectionView = UICollectionView(
            frame: .init(x: 0, y: 0, width: 390, height: 844),
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
                canRetry: true,
                toolPresentationStyle: .capsule,
                actionSink: .init { receivedAction = $0 }
            )
        )
        let retry = try XCTUnwrap(
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventRetry"
            } as? UIButton
        )

        retry.sendActions(for: .touchUpInside)

        XCTAssertEqual(receivedAction, .retry(block.id))
        let header = try XCTUnwrap(
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventHeader"
            } as? AgentCompactEventHeaderControl
        )
        let retryAccessibilityAction = try XCTUnwrap(header.accessibilityCustomActions?.first)
        XCTAssertEqual(retryAccessibilityAction.name, AgentStrings.retry)
    }

    func testCapsuleFailureHidesRetryWhenRuntimeDoesNotSupportIt() throws {
        let block = AgentBlock(
            id: "failed-tool",
            kind: .tool,
            content: .tool(.init(toolName: "package.publish", title: "Publish package")),
            state: .failed(
                .init(code: "publish.failed", message: "Publish failed", isRetryable: true)
            ),
            createdAt: .distantPast
        )
        let turn = AgentTurn(
            id: "turn",
            role: .assistant,
            blocks: [block],
            state: .completed,
            createdAt: .distantPast
        )
        let renderer = AgentDefaultBlockRenderer(supportedKinds: [.tool])
        let collectionView = UICollectionView(
            frame: .init(x: 0, y: 0, width: 390, height: 844),
            collectionViewLayout: fixedHeightLayout()
        )
        renderer.register(in: collectionView)
        let cell = renderer.dequeueConfiguredCell(
            from: collectionView,
            at: .init(item: 0, section: 0),
            context: renderContext(
                turn: turn,
                block: block,
                canRetry: false,
                toolPresentationStyle: .capsule
            )
        )

        XCTAssertNil(
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventRetry"
            }
        )
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

    func testMarkdownTablePreservesInlineStylesLinksAndImagePreviews() async throws {
        let image = UIGraphicsImageRenderer(size: .init(width: 24, height: 16)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(.init(x: 0, y: 0, width: 24, height: 16))
        }
        let block = AgentBlock(
            id: "rich-markdown-table",
            kind: .markdown,
            content: .markdown(
                .init(
                    markdown: """
                        | Content |
                        | --- |
                        | **Styled** [Link](https://example.com/table) ![Thumb](table-preview) |
                        """,
                    isFinal: true
                )
            ),
            state: .succeeded,
            createdAt: .distantPast
        )
        let turn = AgentTurn(
            id: "rich-markdown-table-turn",
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
        var receivedActions: [AgentBlockUIAction] = []
        let cell = renderer.dequeueConfiguredCell(
            from: collectionView,
            at: .init(item: 0, section: 0),
            context: renderContext(
                turn: turn,
                block: block,
                imageProvider: StubImageProvider(result: image),
                actionSink: .init { receivedActions.append($0) }
            )
        )

        await (cell as? AgentBlockCell)?.waitForPendingRendering()
        let table = try XCTUnwrap(
            cell.contentView.allSubviews.compactMap { $0 as? AgentMarkdownTableView }.first
        )
        let markdownImage = try XCTUnwrap(
            table.allSubviews.compactMap { $0 as? AgentMarkdownImageView }.first
        )
        await markdownImage.waitForLoad()
        let richText = try XCTUnwrap(
            table.allSubviews.compactMap { $0 as? AgentSelectableTextView }.first { textView in
                textView.attributedText.string.contains("Styled")
            }
        )
        let source = richText.attributedText.string as NSString
        let styledRange = source.range(of: "Styled")
        let linkRange = source.range(of: "Link")
        let styledFont = try XCTUnwrap(
            richText.attributedText.attribute(
                .font,
                at: styledRange.location,
                effectiveRange: nil
            ) as? UIFont
        )
        let link =
            richText.attributedText.attribute(
                .link,
                at: linkRange.location,
                effectiveRange: nil
            ) as? URL

        XCTAssertTrue(styledFont.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertEqual(link, URL(string: "https://example.com/table"))
        richText.onOpenURL?(try XCTUnwrap(link))
        let preview = try XCTUnwrap(
            markdownImage.allSubviews.compactMap { $0 as? AgentInlineImagePreviewView }.first
        )
        XCTAssertTrue(preview.accessibilityActivate())
        XCTAssertTrue(receivedActions.contains(.openLink(try XCTUnwrap(link))))
        XCTAssertTrue(
            receivedActions.contains(
                .previewImage(
                    reference: .localIdentifier("table-preview"),
                    alternativeText: "Thumb"
                )
            )
        )
        XCTAssertGreaterThan(table.intrinsicContentSize.height, 160)
    }

    func testMarkdownUsesSelectableAttributedInlineStyles() async throws {
        let block = AgentBlock(
            id: "markdown-inline-styles",
            kind: .markdown,
            content: .markdown(
                .init(
                    markdown:
                        "Plain **strong** *emphasis* ~~removed~~ `code` [link](https://example.com).",
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

        let textView = try XCTUnwrap(
            cell.contentView.allSubviews.compactMap { $0 as? AgentSelectableTextView }.first
        )
        let attributed = try XCTUnwrap(textView.attributedText)
        let source = attributed.string as NSString
        let strongRange = source.range(of: "strong")
        let emphasisRange = source.range(of: "emphasis")
        let removedRange = source.range(of: "removed")
        let codeRange = source.range(of: "code")
        let linkRange = source.range(of: "link")
        let strongFont =
            attributed.attribute(.font, at: strongRange.location, effectiveRange: nil)
            as? UIFont
        let emphasisFont =
            attributed.attribute(
                .font,
                at: emphasisRange.location,
                effectiveRange: nil
            ) as? UIFont

        XCTAssertTrue(textView.isSelectable)
        XCTAssertTrue(strongFont?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        XCTAssertTrue(emphasisFont?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
        XCTAssertNotNil(
            attributed.attribute(
                .strikethroughStyle,
                at: removedRange.location,
                effectiveRange: nil
            )
        )
        XCTAssertNotNil(
            attributed.attribute(.backgroundColor, at: codeRange.location, effectiveRange: nil)
        )
        XCTAssertEqual(
            attributed.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL,
            URL(string: "https://example.com")
        )
    }

    func testMarkdownCodeBlockScrollsCopiesAndExpands() async throws {
        let lines = (1...24).map { index in
            "let generatedValue\(index) = \(index) // a deliberately wide source line for horizontal scrolling"
        }.joined(separator: "\n")
        let block = AgentBlock(
            id: "markdown-code",
            kind: .markdown,
            content: .markdown(.init(markdown: "```swift\n\(lines)\n```", isFinal: true)),
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

        let codeBlock = try XCTUnwrap(
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentMarkdownCodeBlock"
            } as? AgentMarkdownCodeBlockView
        )
        let scrollView = try XCTUnwrap(
            codeBlock.allSubviews.first {
                $0.accessibilityIdentifier == "AgentMarkdownCodeScrollView"
            } as? UIScrollView
        )
        let copyButton = try XCTUnwrap(
            codeBlock.allSubviews.first {
                $0.accessibilityIdentifier == "AgentMarkdownCodeCopyButton"
            } as? UIButton
        )
        let disclosure = try XCTUnwrap(
            codeBlock.allSubviews.first {
                $0.accessibilityIdentifier == "AgentMarkdownCodeDisclosureButton"
            } as? UIButton
        )
        let collapsedHeight = codeBlock.systemLayoutSizeFitting(
            .init(width: 320, height: UIView.layoutFittingCompressedSize.height)
        ).height
        codeBlock.frame = .init(x: 0, y: 0, width: 320, height: collapsedHeight)
        codeBlock.layoutIfNeeded()
        scrollView.layoutIfNeeded()

        var copiedCode: String?
        codeBlock.copyHandler = { copiedCode = $0 }
        copyButton.sendActions(for: .touchUpInside)
        disclosure.sendActions(for: .touchUpInside)
        let expandedHeight = codeBlock.systemLayoutSizeFitting(
            .init(width: 320, height: UIView.layoutFittingCompressedSize.height)
        ).height

        XCTAssertEqual(copiedCode?.trimmingCharacters(in: .newlines), lines)
        XCTAssertGreaterThan(scrollView.contentSize.width, 320)
        XCTAssertGreaterThan(expandedHeight, collapsedHeight)
        XCTAssertEqual(disclosure.configuration?.title, AgentStrings.showLess)
    }

    func testMarkdownCodeBlockBoundsRenderedTextAndWidthMeasurement() throws {
        let code = String(repeating: "W", count: 100_000)
        let codeBlock = AgentMarkdownCodeBlockView(
            language: "text",
            code: code,
            availableWidth: 320,
            pointSize: 13,
            contentSizeCategory: .large,
            textColor: .label,
            secondaryColor: .secondaryLabel,
            accentColor: .systemBlue
        )
        let fittingHeight = codeBlock.systemLayoutSizeFitting(
            .init(width: 320, height: UIView.layoutFittingCompressedSize.height)
        ).height
        codeBlock.frame = .init(x: 0, y: 0, width: 320, height: fittingHeight)
        codeBlock.layoutIfNeeded()
        let codeView = try XCTUnwrap(
            codeBlock.allSubviews.compactMap { $0 as? AgentSelectableTextView }.first
        )
        let scrollView = try XCTUnwrap(
            codeBlock.allSubviews.first {
                $0.accessibilityIdentifier == "AgentMarkdownCodeScrollView"
            } as? UIScrollView
        )
        scrollView.layoutIfNeeded()

        XCTAssertLessThan(codeView.text.count, code.count)
        XCTAssertLessThanOrEqual(
            codeView.text.count,
            AgentMarkdownCodeBlockView.maximumRenderedCharacterCount + 2
        )
        XCTAssertLessThanOrEqual(
            codeView.bounds.width, AgentMarkdownCodeBlockView.maximumContentWidth)
        XCTAssertTrue(
            codeBlock.allSubviews.compactMap { ($0 as? UILabel)?.text }
                .contains { $0.contains(AgentStrings.codeTruncated) }
        )
    }

    func testMarkdownCodeBlockCountsWrappedVisualLinesForDisclosureAndHeight() throws {
        let code = String(repeating: "wrapped token ", count: 2_000)
        let codeBlock = AgentMarkdownCodeBlockView(
            language: "text",
            code: code,
            availableWidth: 320,
            pointSize: 13,
            contentSizeCategory: .large,
            textColor: .label,
            secondaryColor: .secondaryLabel,
            accentColor: .systemBlue
        )
        let disclosure = try XCTUnwrap(
            codeBlock.allSubviews.first {
                $0.accessibilityIdentifier == "AgentMarkdownCodeDisclosureButton"
            } as? UIButton
        )
        let collapsedHeight = codeBlock.systemLayoutSizeFitting(
            .init(width: 320, height: UIView.layoutFittingCompressedSize.height)
        ).height

        XCTAssertFalse(disclosure.isHidden)
        disclosure.sendActions(for: .touchUpInside)

        let expandedHeight = codeBlock.systemLayoutSizeFitting(
            .init(width: 320, height: UIView.layoutFittingCompressedSize.height)
        ).height
        XCTAssertGreaterThan(expandedHeight, collapsedHeight)
    }

    func testTableRichInlineMarkdownUsesAutomaticRowHeight() async throws {
        let block = AgentBlock(
            id: "table-rich-inline-markdown",
            kind: .markdown,
            content: .markdown(
                .init(
                    markdown: String(
                        repeating: "**Bold content near a wrapping boundary** ", count: 8),
                    isFinal: true
                )
            ),
            state: .succeeded,
            createdAt: .distantPast
        )
        let store = AgentConversationStore(
            snapshot: .init(
                id: "table-rich-inline-conversation",
                turns: [
                    .init(
                        id: "turn",
                        role: .assistant,
                        blocks: [block],
                        state: .completed,
                        createdAt: .distantPast
                    )
                ]
            )
        )
        let controller = AgentTableConversationViewController(store: store)
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let tableView = try XCTUnwrap(
            controller.view.allSubviews.compactMap { $0 as? UITableView }.first
        )
        let path = IndexPath(row: 0, section: 0)
        let cell = try XCTUnwrap(tableView.cellForRow(at: path) as? AgentTableBlockCell)
        await cell.waitForPendingRendering()

        XCTAssertEqual(
            controller.tableView(tableView, heightForRowAt: path),
            UITableView.automaticDimension
        )
    }

    func testTableMarkdownCodeDisclosureUpdatesAutomaticRowHeight() async throws {
        let lines = (1...24).map { "let row\($0) = \($0)" }.joined(separator: "\n")
        let block = AgentBlock(
            id: "table-markdown-code",
            kind: .markdown,
            content: .markdown(.init(markdown: "```swift\n\(lines)\n```", isFinal: true)),
            state: .succeeded,
            createdAt: .distantPast
        )
        let store = AgentConversationStore(
            snapshot: .init(
                id: "table-markdown-code-conversation",
                turns: [
                    .init(
                        id: "turn",
                        role: .assistant,
                        blocks: [block],
                        state: .completed,
                        createdAt: .distantPast
                    )
                ]
            )
        )
        let controller = AgentTableConversationViewController(store: store)
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let tableView = try XCTUnwrap(
            controller.view.allSubviews.compactMap { $0 as? UITableView }.first
        )
        let path = IndexPath(row: 0, section: 0)
        let cell = try XCTUnwrap(tableView.cellForRow(at: path) as? AgentTableBlockCell)
        await cell.waitForPendingRendering()
        tableView.layoutIfNeeded()

        XCTAssertEqual(
            controller.tableView(tableView, heightForRowAt: path),
            UITableView.automaticDimension
        )
        let collapsedHeight = tableView.rectForRow(at: path).height
        let disclosure = try XCTUnwrap(
            cell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentMarkdownCodeDisclosureButton"
            } as? UIButton
        )
        disclosure.sendActions(for: .touchUpInside)
        try await Task.sleep(for: .milliseconds(350))
        tableView.layoutIfNeeded()

        XCTAssertGreaterThan(tableView.rectForRow(at: path).height, collapsedHeight)
        let expandedCell = try XCTUnwrap(
            tableView.cellForRow(at: path) as? AgentTableBlockCell
        )
        await expandedCell.waitForPendingRendering()
        let expandedDisclosure = try XCTUnwrap(
            expandedCell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentMarkdownCodeDisclosureButton"
            } as? UIButton
        )
        XCTAssertEqual(expandedDisclosure.configuration?.title, AgentStrings.showLess)

        controller.apply(theme: .system)
        controller.view.layoutIfNeeded()
        let themedCell = try XCTUnwrap(
            tableView.cellForRow(at: path) as? AgentTableBlockCell
        )
        await themedCell.waitForPendingRendering()
        let themedDisclosure = try XCTUnwrap(
            themedCell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentMarkdownCodeDisclosureButton"
            } as? UIButton
        )
        XCTAssertEqual(themedDisclosure.configuration?.title, AgentStrings.showLess)
    }

    func testMarkdownImageUsesProviderAndRoutesPreview() async throws {
        let image = UIGraphicsImageRenderer(size: .init(width: 24, height: 16)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(.init(x: 0, y: 0, width: 24, height: 16))
        }
        let block = AgentBlock(
            id: "markdown-image",
            kind: .markdown,
            content: .markdown(
                .init(
                    markdown: "Before *emphasis ![Architecture](diagram-preview) after*.",
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
        var receivedAction: AgentBlockUIAction?
        let cell = renderer.dequeueConfiguredCell(
            from: collectionView,
            at: .init(item: 0, section: 0),
            context: renderContext(
                turn: turn,
                block: block,
                imageProvider: StubImageProvider(result: image),
                actionSink: .init { receivedAction = $0 }
            )
        )

        await (cell as? AgentBlockCell)?.waitForPendingRendering()
        let markdownImage = try XCTUnwrap(
            cell.contentView.allSubviews.compactMap { $0 as? AgentMarkdownImageView }.first
        )
        await markdownImage.waitForLoad()
        let preview = try XCTUnwrap(
            markdownImage.allSubviews.compactMap { $0 as? AgentInlineImagePreviewView }.first
        )
        let imageView = try XCTUnwrap(
            markdownImage.allSubviews.first {
                $0.accessibilityIdentifier == "AgentInlineImagePreviewImage"
            } as? UIImageView
        )

        XCTAssertNotNil(imageView.image)
        XCTAssertTrue(preview.accessibilityActivate())
        XCTAssertEqual(
            receivedAction,
            .previewImage(
                reference: .localIdentifier("diagram-preview"),
                alternativeText: "Architecture"
            )
        )
    }

    func testMarkdownImagesInsideLinksListsAndQuotesUseProvider() async throws {
        let image = UIGraphicsImageRenderer(size: .init(width: 24, height: 16)).image { context in
            UIColor.systemIndigo.setFill()
            context.fill(.init(x: 0, y: 0, width: 24, height: 16))
        }
        let block = AgentBlock(
            id: "nested-markdown-images",
            kind: .markdown,
            content: .markdown(
                .init(
                    markdown: """
                        > Quoted [![Quote](quote-preview)](https://example.com/quote)

                        - Item with **![List](list-preview)**
                        """,
                    isFinal: true
                )
            ),
            state: .succeeded,
            createdAt: .distantPast
        )
        let turn = AgentTurn(
            id: "nested-markdown-images-turn",
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
        var receivedActions: [AgentBlockUIAction] = []
        let cell = renderer.dequeueConfiguredCell(
            from: collectionView,
            at: .init(item: 0, section: 0),
            context: renderContext(
                turn: turn,
                block: block,
                imageProvider: StubImageProvider(result: image),
                actionSink: .init { receivedActions.append($0) }
            )
        )

        await (cell as? AgentBlockCell)?.waitForPendingRendering()
        let markdownImages = cell.contentView.allSubviews.compactMap {
            $0 as? AgentMarkdownImageView
        }
        XCTAssertEqual(markdownImages.count, 2)
        for markdownImage in markdownImages {
            await markdownImage.waitForLoad()
        }

        let previews = cell.contentView.allSubviews.compactMap {
            $0 as? AgentInlineImagePreviewView
        }
        XCTAssertEqual(previews.count, 2)
        XCTAssertTrue(previews.allSatisfy { $0.targetSize.width < 320 })
        XCTAssertTrue(previews.allSatisfy { $0.accessibilityActivate() })
        XCTAssertEqual(
            Set(receivedActions),
            Set([
                .previewImage(
                    reference: .localIdentifier("quote-preview"),
                    alternativeText: "Quote"
                ),
                .previewImage(
                    reference: .localIdentifier("list-preview"),
                    alternativeText: "List"
                ),
            ])
        )
    }

    func testRawUnifiedDiffParsesOffMainActorAndUpdatesSummary() async throws {
        let date = Date(timeIntervalSince1970: 0)
        let block = AgentBlock(
            id: "raw-diff",
            kind: .diff,
            content: .diff(
                .init(
                    title: "Parsed diff",
                    rawUnifiedDiff: """
                        --- a/Old.swift
                        +++ b/New.swift
                        @@ -1 +1 @@
                        -let old = true
                        +let updated = true
                        """
                )
            ),
            state: .succeeded,
            revision: 3,
            createdAt: date
        )
        let turn = AgentTurn(
            id: "raw-diff-turn",
            role: .assistant,
            blocks: [block],
            state: .completed,
            createdAt: date
        )
        let renderer = AgentDefaultBlockRenderer(supportedKinds: [.diff])
        let tableView = UITableView(frame: .init(x: 0, y: 0, width: 390, height: 600))
        renderer.register(in: tableView)
        let cell = try XCTUnwrap(
            renderer.dequeueConfiguredCell(
                from: tableView,
                at: .init(row: 0, section: 0),
                context: renderContext(turn: turn, block: block)
            ) as? AgentTableBlockCell
        )

        await cell.waitForPendingRendering()

        let labels = cell.contentView.allSubviews.compactMap { ($0 as? UILabel)?.text }
        XCTAssertTrue(labels.contains("1 files · +1 −1"))
    }

    func testTruncatedRawUnifiedDiffMarksStatisticsAsIncomplete() async throws {
        let date = Date(timeIntervalSince1970: 0)
        let additions = (0..<1_100).map { "+line \($0)" }.joined(separator: "\n")
        let block = AgentBlock(
            id: "truncated-raw-diff",
            kind: .diff,
            content: .diff(
                .init(
                    title: "Large diff",
                    rawUnifiedDiff: """
                        --- a/Large.swift
                        +++ b/Large.swift
                        @@ -0,0 +1,1100 @@
                        \(additions)
                        """
                )
            ),
            state: .succeeded,
            revision: 1,
            createdAt: date
        )
        let turn = AgentTurn(
            id: "truncated-raw-diff-turn",
            role: .assistant,
            blocks: [block],
            state: .completed,
            createdAt: date
        )
        let renderer = AgentDefaultBlockRenderer(supportedKinds: [.diff])
        let tableView = UITableView(frame: .init(x: 0, y: 0, width: 390, height: 600))
        renderer.register(in: tableView)
        let cell = try XCTUnwrap(
            renderer.dequeueConfiguredCell(
                from: tableView,
                at: .init(row: 0, section: 0),
                context: renderContext(turn: turn, block: block)
            ) as? AgentTableBlockCell
        )

        await cell.waitForPendingRendering()

        let labels = cell.contentView.allSubviews.compactMap { ($0 as? UILabel)?.text }
        XCTAssertTrue(
            labels.contains { label in
                label.contains("1 files") && label.contains(AgentStrings.outputTruncated)
            }
        )
    }

    func testMarkdownContentUsesTheSameHorizontalBaselineAsCompactRows() async throws {
        let date = Date(timeIntervalSince1970: 0)
        let activity = AgentBlock(
            id: "activity-baseline",
            kind: .activity,
            content: .activity(.init(title: "Compact row")),
            state: .succeeded,
            createdAt: date
        )
        let markdown = AgentBlock(
            id: "markdown-baseline",
            kind: .markdown,
            content: .markdown(
                .init(
                    markdown: """
                        # Baseline

                        | Feature | Status |
                        | --- | --- |
                        | Spacing | Aligned |
                        """,
                    isFinal: true
                )
            ),
            state: .succeeded,
            createdAt: date
        )
        let turn = AgentTurn(
            id: "baseline-turn",
            role: .assistant,
            blocks: [activity, markdown],
            state: .completed,
            createdAt: date
        )
        let store = AgentConversationStore(
            snapshot: .init(id: "baseline-conversation", turns: [turn])
        )
        let controller = AgentTableConversationViewController(store: store)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let tableView = try XCTUnwrap(
            controller.view.allSubviews.compactMap { $0 as? UITableView }.first
        )
        tableView.layoutIfNeeded()
        let activityCell = try XCTUnwrap(
            tableView.cellForRow(at: .init(row: 0, section: 0)) as? AgentTableBlockCell
        )
        let markdownCell = try XCTUnwrap(
            tableView.cellForRow(at: .init(row: 1, section: 0)) as? AgentTableBlockCell
        )
        await markdownCell.waitForPendingRendering()
        tableView.performBatchUpdates(nil)
        tableView.layoutIfNeeded()

        let activityHeader = try XCTUnwrap(
            activityCell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentActivityEventHeader"
            }
        )
        let markdownView = try XCTUnwrap(
            markdownCell.contentView.allSubviews.first { $0 is AgentMarkdownContentView }
        )
        let markdownTable = try XCTUnwrap(
            markdownCell.contentView.allSubviews.first {
                $0.accessibilityIdentifier == "AgentMarkdownTable"
            }
        )
        let activityLeading = activityHeader.convert(activityHeader.bounds, to: tableView).minX
        let markdownLeading = markdownView.convert(markdownView.bounds, to: tableView).minX
        let tableFrame = markdownTable.convert(markdownTable.bounds, to: tableView)

        XCTAssertEqual(activityLeading, 16, accuracy: 1)
        XCTAssertEqual(markdownLeading, activityLeading, accuracy: 1)
        XCTAssertEqual(tableFrame.minX, markdownLeading, accuracy: 1)
        XCTAssertEqual(tableFrame.maxX, tableView.bounds.width - 16, accuracy: 1)
        XCTAssertFalse(activityCell.isAccessibilityElement)
        XCTAssertFalse(markdownCell.isAccessibilityElement)
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

    func testTableTextRowsUseCalculatedHeightsAndSemanticTextViews() async throws {
        let date = Date(timeIntervalSince1970: 0)
        let turns = [
            AgentTurn(
                id: "calculated-user-turn",
                role: .user,
                blocks: [
                    AgentBlock(
                        id: "calculated-user",
                        kind: .userText,
                        content: .userText(.init(text: "A lightweight user message")),
                        state: .succeeded,
                        createdAt: date
                    )
                ],
                state: .completed,
                createdAt: date
            ),
            AgentTurn(
                id: "calculated-markdown-turn",
                role: .assistant,
                blocks: [
                    AgentBlock(
                        id: "calculated-markdown",
                        kind: .markdown,
                        content: .markdown(
                            .init(markdown: "A simple Markdown paragraph.", isFinal: true)
                        ),
                        state: .succeeded,
                        createdAt: date
                    )
                ],
                state: .completed,
                createdAt: date
            ),
        ]
        let store = AgentConversationStore(
            snapshot: .init(id: "calculated-heights", turns: turns)
        )
        let controller = AgentTableConversationViewController(store: store)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let tableView = try XCTUnwrap(
            controller.view.allSubviews.compactMap { $0 as? UITableView }.first
        )
        tableView.layoutIfNeeded()

        let userPath = IndexPath(row: 0, section: 0)
        let userHeight = controller.tableView(tableView, heightForRowAt: userPath)
        XCTAssertNotEqual(userHeight, UITableView.automaticDimension)
        let userCell = try XCTUnwrap(
            tableView.cellForRow(at: userPath) as? AgentTableBlockCell
        )
        XCTAssertTrue(userCell.contentView.allSubviews.contains { $0 is UILabel })
        XCTAssertFalse(userCell.contentView.allSubviews.contains { $0 is UITextView })

        let markdownPath = IndexPath(row: 0, section: 1)
        let markdownCell = try XCTUnwrap(
            tableView.cellForRow(at: markdownPath) as? AgentTableBlockCell
        )
        await markdownCell.waitForPendingRendering()
        tableView.performBatchUpdates(nil)
        tableView.layoutIfNeeded()
        let markdownHeight = controller.tableView(tableView, heightForRowAt: markdownPath)
        XCTAssertNotEqual(markdownHeight, UITableView.automaticDimension)
        XCTAssertTrue(markdownCell.contentView.allSubviews.contains { $0 is UITextView })
    }

    func testUpdateSchedulerCoalescesBlockRevisions() async {
        let expectation = expectation(description: "flush")
        var received: AgentScheduledUpdate?
        let scheduler = AgentUpdateScheduler(
            coalescingMilliseconds: 33,
            flush: {
                received = $0
                expectation.fulfill()
            }
        )
        scheduler.enqueue(.reconfigureBlock("block"))
        scheduler.enqueue(.reconfigureBlock("block"))
        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(received?.reconfiguredBlockIDs, ["block"])
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

    private func dynamicTypeMarkdownStore(id: AgentConversationID) -> AgentConversationStore {
        AgentConversationStore(
            snapshot: .init(
                id: id,
                turns: [
                    .init(
                        id: "dynamic-type-turn",
                        role: .assistant,
                        blocks: [
                            .init(
                                id: "dynamic-type-markdown",
                                kind: .markdown,
                                content: .markdown(
                                    .init(
                                        markdown: """
                                            # Dynamic heading

                                            ```swift
                                            let category = "accessible"
                                            ```
                                            """,
                                        isFinal: true
                                    )
                                ),
                                state: .succeeded,
                                createdAt: .distantPast
                            )
                        ],
                        state: .completed,
                        createdAt: .distantPast
                    )
                ]
            )
        )
    }

    private func headingFont(in markdown: AgentMarkdownContentView) throws -> UIFont {
        let codeBlocks = markdown.allSubviews.compactMap { $0 as? AgentMarkdownCodeBlockView }
        let heading = try XCTUnwrap(
            markdown.allSubviews.compactMap { $0 as? AgentSelectableTextView }.first { textView in
                !codeBlocks.contains { textView.isDescendant(of: $0) }
                    && textView.attributedText.length > 0
            }
        )
        return try XCTUnwrap(
            heading.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        )
    }

    private func codeFont(in markdown: AgentMarkdownContentView) throws -> UIFont {
        let codeBlock = try XCTUnwrap(
            markdown.allSubviews.compactMap { $0 as? AgentMarkdownCodeBlockView }.first
        )
        let codeView = try XCTUnwrap(
            codeBlock.allSubviews.compactMap { $0 as? AgentSelectableTextView }.first
        )
        return try XCTUnwrap(codeView.font)
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
        canRetry: Bool = false,
        toolPresentationStyle: AgentToolPresentationStyle = .inline,
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
                expandedBlockIDs: expandedBlockIDs,
                canRetry: canRetry,
                toolPresentationStyle: toolPresentationStyle
            ),
            imageProvider: imageProvider,
            actionSink: actionSink
        )
    }

    private func waitUntil(
        timeout: TimeInterval,
        interval: Duration = .milliseconds(20),
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            await Task.yield()
            try? await Task.sleep(for: interval)
        }
        return condition()
    }
}

@MainActor
private final class TableCustomRendererStub: AgentTableBlockRenderer {
    let supportedKinds: Set<AgentBlockKind> = ["test.table.custom"]

    func register(in collectionView: UICollectionView) {
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "custom")
    }

    func dequeueConfiguredCell(
        from collectionView: UICollectionView,
        at indexPath: IndexPath,
        context: AgentBlockRenderContext
    ) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: "custom", for: indexPath)
    }

    func register(in tableView: UITableView) {
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "custom")
    }

    func dequeueConfiguredCell(
        from tableView: UITableView,
        at indexPath: IndexPath,
        context: AgentBlockRenderContext
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "custom", for: indexPath)
        cell.accessibilityIdentifier = "HostTableCustomCell"
        return cell
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

extension AgentBlockContent {
    fileprivate var blockKind: AgentBlockKind {
        switch self {
        case .userText: .userText
        case .markdown: .markdown
        case .activity: .activity
        case .tool: .tool
        case .command: .command
        case .fileSearch: .fileSearch
        case .fileOperation: .fileOperation
        case .diff: .diff
        case .approval: .approval
        case .artifact: .artifact
        case .image: .image
        case .error: .error
        case .custom(let value): .init(rawValue: value.kind)
        }
    }
}
