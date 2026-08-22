import AgentChatCore
import UIKit
import XCTest

@testable import AgentChatUIKit

@MainActor
final class AgentComposerInjectionTests: XCTestCase {
    func testLegacyComposerConformerRemainsSourceCompatible() {
        let composer = LegacyComposer()

        composer.apply(.init(text: "compatible"))
        XCTAssertNotNil(composer.view)
    }

    func testTableControllerUsesInjectedComposerViewAndDefaultInitializer() {
        let store = makeStore(id: "table-injection")
        let composer = SpyComposer()
        let controller = AgentTableConversationViewController(store: store, composer: composer)

        controller.loadViewIfNeeded()

        XCTAssertTrue(controller.view.subviews.contains { $0 === composer.view })
        XCTAssertEqual(composer.actionStreamAccessCount, 1)

        let defaultController = AgentTableConversationViewController(store: store)
        defaultController.loadViewIfNeeded()
        XCTAssertTrue(defaultController.view.subviews.contains { $0 is AgentComposerView })
    }

    func testCollectionControllerUsesInjectedComposerViewAndNilUsesDefault() {
        let store = makeStore(id: "collection-injection")
        let composer = SpyComposer()
        let controller = AgentConversationViewController(store: store, composer: composer)

        controller.loadViewIfNeeded()

        XCTAssertTrue(controller.view.subviews.contains { $0 === composer.view })
        XCTAssertEqual(composer.actionStreamAccessCount, 1)

        let defaultController = AgentConversationViewController(store: store, composer: nil)
        defaultController.loadViewIfNeeded()
        XCTAssertTrue(defaultController.view.subviews.contains { $0 is AgentComposerView })
    }

    func testStoreAndHostStateUpdatesAreAppliedWithoutLosingLiveDraft() async throws {
        let initialTurn = makeTurn(id: "state-turn", state: .completed)
        let store = makeStore(id: "composer-state", turns: [initialTurn])
        let composer = SpyComposer()
        let controller = AgentTableConversationViewController(
            store: store,
            configuration: .init(
                runtimeCapabilities: [.attachments, .interrupt],
                composerAccessories: [
                    .init(id: "model", title: "Local", systemImageName: "cpu")
                ],
                composerContextDescription: "32k"
            ),
            composer: composer
        )
        controller.loadViewIfNeeded()
        composer.setLiveDraft("正在编辑的草稿")

        let attachment = AgentAttachment(
            id: "draft",
            name: "draft.txt",
            reference: .localIdentifier("draft")
        )
        controller.setComposerAttachments([attachment])
        controller.setComposerAttachmentStatus(.uploading(progress: 0.5), for: attachment.id)
        controller.setComposerAccessories([
            .init(id: "model", title: "Remote", systemImageName: "network")
        ])

        var runningSnapshot = store.snapshot
        runningSnapshot.turns[0].state = .running
        store.apply(
            .init(
                snapshot: runningSnapshot,
                patches: [.reconfigureTurn(initialTurn.id)]
            )
        )

        let receivedRunningState = await waitUntil {
            composer.currentState.isRunning
                && composer.currentState.text == "正在编辑的草稿"
                && composer.currentState.attachments == [attachment]
        }
        XCTAssertTrue(receivedRunningState)
        XCTAssertEqual(
            composer.currentState.attachmentStatuses[attachment.id], .uploading(progress: 0.5))
        XCTAssertEqual(composer.currentState.accessories.first?.title, "Remote")
        XCTAssertEqual(composer.currentState.contextDescription, "32k")
        XCTAssertTrue(composer.currentState.canPickAttachments)
        XCTAssertFalse(composer.currentState.canSend)

        var offlineSnapshot = runningSnapshot
        offlineSnapshot.state = .offline(message: "Reconnect")
        offlineSnapshot.turns[0].state = .completed
        store.apply(
            .init(
                snapshot: offlineSnapshot,
                patches: [.reconfigureTurn(initialTurn.id), .conversationStateChanged]
            )
        )

        let receivedOfflineState = await waitUntil {
            !composer.currentState.isRunning
                && composer.currentState.statusMessage == "Reconnect"
                && composer.currentState.text == "正在编辑的草稿"
        }
        XCTAssertTrue(receivedOfflineState)
        XCTAssertGreaterThan(composer.appliedStates.count, 3)
    }

    func testCustomComposerSendRoutesRuntimeSubmit() async {
        let store = makeStore(id: "send")
        let composer = SpyComposer()
        let recorder = ActionRecorder()
        let controller = AgentTableConversationViewController(store: store, composer: composer)
        controller.actionHandler = { [recorder] action in recorder.actions.append(action) }
        controller.loadViewIfNeeded()

        let attachment = AgentAttachment(
            id: "attachment",
            name: "notes.md",
            reference: .localIdentifier("attachment")
        )
        composer.setLiveDraft("实时草稿")
        composer.emit(.send(text: "发送内容", attachments: [attachment]))

        let receivedSubmit = await waitUntil { recorder.actions.count == 1 }
        XCTAssertTrue(receivedSubmit)
        XCTAssertEqual(
            recorder.actions.first,
            .runtime(
                .submit(
                    .init(
                        conversationID: "send",
                        text: "发送内容",
                        attachments: [attachment]
                    )
                )
            )
        )
        XCTAssertEqual(composer.currentState.text, "")
        XCTAssertTrue(composer.currentState.attachments.isEmpty)
    }

    func testCustomComposerCannotSubmitWhileSendingIsUnavailable() async {
        let tableComposer = SpyComposer()
        let tableRecorder = ActionRecorder()
        let tableController = AgentTableConversationViewController(
            store: makeStore(id: "table-offline", state: .offline(message: "Offline")),
            composer: tableComposer
        )
        tableController.actionHandler = { [tableRecorder] action in
            tableRecorder.actions.append(action)
        }
        tableController.loadViewIfNeeded()

        tableComposer.emit(.send(text: "blocked", attachments: []))
        tableComposer.emit(.selectAccessory("table-probe"))
        let tableProbeReceived = await waitUntil { tableRecorder.actions.count == 1 }
        XCTAssertTrue(tableProbeReceived)
        XCTAssertEqual(
            tableRecorder.actions,
            [
                .host(
                    .custom(
                        kind: "agentchat.composer.accessory",
                        payload: .object(["id": .string("table-probe")])))
            ]
        )

        let collectionComposer = SpyComposer()
        let collectionRecorder = ActionRecorder()
        let collectionController = AgentConversationViewController(
            store: makeStore(id: "collection-offline", state: .offline(message: "Offline")),
            composer: collectionComposer
        )
        collectionController.actionHandler = { [collectionRecorder] action in
            collectionRecorder.actions.append(action)
        }
        collectionController.loadViewIfNeeded()

        collectionComposer.emit(.send(text: "blocked", attachments: []))
        collectionComposer.emit(.selectAccessory("collection-probe"))
        let collectionProbeReceived = await waitUntil { collectionRecorder.actions.count == 1 }
        XCTAssertTrue(collectionProbeReceived)
        XCTAssertEqual(
            collectionRecorder.actions,
            [
                .host(
                    .custom(
                        kind: "agentchat.composer.accessory",
                        payload: .object(["id": .string("collection-probe")])))
            ]
        )
    }

    func testRapidCustomComposerSendsProduceOnlyOneSubmitUntilRuntimeStarts() async {
        let composer = SpyComposer()
        let recorder = ActionRecorder()
        let controller = AgentConversationViewController(
            store: makeStore(id: "deduplicated-send"),
            composer: composer
        )
        controller.actionHandler = { [recorder] action in recorder.actions.append(action) }
        controller.loadViewIfNeeded()

        composer.emit(.send(text: "first", attachments: []))
        composer.emit(.send(text: "second", attachments: []))

        let firstSubmitReceived = await waitUntil { recorder.actions.count == 1 }
        XCTAssertTrue(firstSubmitReceived)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(
            recorder.actions,
            [
                .runtime(
                    .submit(
                        .init(
                            conversationID: "deduplicated-send",
                            text: "first",
                            attachments: []
                        )
                    )
                )
            ]
        )
    }

    func testOfflineQueueAcceptsAnotherSendAfterPreviousSubmitCompletes() async {
        let composer = SpyComposer()
        let recorder = ActionRecorder()
        let controller = AgentConversationViewController(
            store: makeStore(id: "offline-queue", state: .offline(message: "Queued")),
            configuration: .init(allowsSendingWhileOffline: true),
            composer: composer
        )
        controller.actionHandler = { [recorder] action in recorder.actions.append(action) }
        controller.loadViewIfNeeded()

        composer.emit(.send(text: "first", attachments: []))
        let firstSubmitReceived = await waitUntil { recorder.actions.count == 1 }
        XCTAssertTrue(firstSubmitReceived)

        composer.emit(.send(text: "second", attachments: []))
        let secondSubmitReceived = await waitUntil { recorder.actions.count == 2 }
        XCTAssertTrue(secondSubmitReceived)
    }

    func testCustomComposerStopAndAccessoryRouteExpectedActions() async {
        let store = makeStore(id: "actions")
        let composer = SpyComposer()
        let recorder = ActionRecorder()
        let controller = AgentConversationViewController(
            store: store,
            configuration: .init(runtimeCapabilities: [.interrupt]),
            composer: composer
        )
        controller.actionHandler = { [recorder] action in recorder.actions.append(action) }
        controller.loadViewIfNeeded()

        composer.emit(.stop)
        composer.emit(.selectAccessory("reasoning"))

        let receivedActions = await waitUntil { recorder.actions.count == 2 }
        XCTAssertTrue(receivedActions)
        XCTAssertEqual(
            recorder.actions[0],
            .runtime(.interrupt(.init(conversationID: "actions")))
        )
        XCTAssertEqual(
            recorder.actions[1],
            .host(
                .custom(
                    kind: "agentchat.composer.accessory",
                    payload: .object(["id": .string("reasoning")])
                )
            )
        )
    }

    func testAttachmentPickerUsesInjectedComposerViewAsSource() async {
        let store = makeStore(id: "attachment-picker")
        let composer = SpyComposer()
        let delegate = ComposerHostDelegateSpy()
        let controller = AgentTableConversationViewController(
            store: store,
            configuration: .init(runtimeCapabilities: [.attachments]),
            composer: composer
        )
        controller.delegate = delegate
        controller.loadViewIfNeeded()

        composer.emit(.pickAttachments)

        let receivedAttachmentRequest = await waitUntil { delegate.attachmentSourceView != nil }
        XCTAssertTrue(receivedAttachmentRequest)
        XCTAssertTrue(delegate.attachmentSourceView === composer.view)
    }

    func testCustomComposerRemoveAndRetryUpdateHostDraftState() async {
        let store = makeStore(id: "attachment-actions")
        let composer = SpyComposer()
        let delegate = ComposerHostDelegateSpy()
        let controller = AgentTableConversationViewController(
            store: store,
            configuration: .init(runtimeCapabilities: [.attachments]),
            composer: composer
        )
        controller.delegate = delegate
        controller.loadViewIfNeeded()
        let attachment = AgentAttachment(
            id: "retry",
            name: "retry.txt",
            reference: .localIdentifier("retry")
        )
        controller.setComposerAttachments([attachment])

        composer.emit(.retryAttachment(attachment.id))
        composer.emit(.removeAttachment(attachment.id))

        let receivedUpdates = await waitUntil {
            delegate.retryAttachmentID == attachment.id
                && delegate.updatedAttachments == []
        }
        XCTAssertTrue(receivedUpdates)
        XCTAssertTrue(composer.currentState.attachments.isEmpty)
    }

    func testOptionalImportRoutingForwardsProvidersAndSourceView() {
        let store = makeStore(id: "import-routing")
        let composer = ImportRoutingSpyComposer()
        let delegate = ComposerHostDelegateSpy()
        let controller = AgentConversationViewController(store: store, composer: composer)
        controller.delegate = delegate
        controller.loadViewIfNeeded()
        let providers = [NSItemProvider(object: "pasted" as NSString)]

        composer.importHandler?(providers, composer.view)

        XCTAssertEqual(delegate.pastedProviderCount, 1)
        XCTAssertTrue(delegate.pasteSourceView === composer.view)
    }

    func testHardwareKeyboardCommandsUseCustomComposerContract() async {
        let tableStore = makeStore(
            id: "table-keyboard",
            turns: [makeTurn(id: "keyboard-running", state: .running)]
        )
        let tableComposer = SpyComposer()
        let recorder = ActionRecorder()
        let tableController = AgentTableConversationViewController(
            store: tableStore,
            configuration: .init(runtimeCapabilities: [.interrupt]),
            composer: tableComposer
        )
        tableController.actionHandler = { [recorder] action in recorder.actions.append(action) }
        tableController.loadViewIfNeeded()

        tableController.sendFromKeyboard()
        tableController.focusComposer()

        XCTAssertEqual(tableComposer.primaryActionCallCount, 1)
        XCTAssertEqual(tableComposer.focusCallCount, 1)

        XCTAssertTrue(tableComposer.currentState.isRunning)
        tableController.stopFromKeyboard()
        let receivedInterrupt = await waitUntil { recorder.actions.count == 1 }
        XCTAssertTrue(receivedInterrupt)
        XCTAssertEqual(
            recorder.actions.first,
            .runtime(.interrupt(.init(conversationID: "table-keyboard")))
        )
        XCTAssertEqual(tableComposer.primaryActionCallCount, 1)

        let collectionComposer = SpyComposer()
        let collectionController = AgentConversationViewController(
            store: makeStore(id: "collection-keyboard"),
            composer: collectionComposer
        )
        collectionController.loadViewIfNeeded()
        collectionController.sendFromKeyboard()
        collectionController.focusComposer()

        XCTAssertEqual(collectionComposer.primaryActionCallCount, 1)
        XCTAssertEqual(collectionComposer.focusCallCount, 1)
    }

    func testComposerStreamIsConsumedOnceAndCancelledWhenControllersDeallocate() async {
        let tableComposer = SpyComposer()
        weak var weakTableController: AgentTableConversationViewController?
        autoreleasepool {
            var controller: AgentTableConversationViewController? =
                AgentTableConversationViewController(
                    store: makeStore(id: "table-lifetime"),
                    composer: tableComposer
                )
            controller?.loadViewIfNeeded()
            controller?.loadViewIfNeeded()
            weakTableController = controller
            controller = nil
        }

        XCTAssertNil(weakTableController)
        XCTAssertEqual(tableComposer.actionStreamAccessCount, 1)
        let tableStreamTerminated = await waitUntil { tableComposer.terminationCount == 1 }
        XCTAssertTrue(tableStreamTerminated)

        let collectionComposer = SpyComposer()
        weak var weakCollectionController: AgentConversationViewController?
        autoreleasepool {
            var controller: AgentConversationViewController? = AgentConversationViewController(
                store: makeStore(id: "collection-lifetime"),
                composer: collectionComposer
            )
            controller?.loadViewIfNeeded()
            controller?.loadViewIfNeeded()
            weakCollectionController = controller
            controller = nil
        }

        XCTAssertNil(weakCollectionController)
        XCTAssertEqual(collectionComposer.actionStreamAccessCount, 1)
        let collectionStreamTerminated = await waitUntil {
            collectionComposer.terminationCount == 1
        }
        XCTAssertTrue(collectionStreamTerminated)
    }

    private func makeStore(
        id: AgentConversationID,
        turns: [AgentTurn] = [],
        state: AgentConversationState = .connected
    ) -> AgentConversationStore {
        AgentConversationStore(snapshot: .init(id: id, turns: turns, state: state))
    }

    private func makeTurn(id: AgentTurnID, state: AgentTurnState) -> AgentTurn {
        AgentTurn(
            id: id,
            role: .assistant,
            blocks: [],
            state: state,
            createdAt: .distantPast
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}

@MainActor
private final class LegacyComposer: AgentComposerProviding {
    let view = UIView()
    let actionStream = AsyncStream<AgentComposerAction> { continuation in
        continuation.finish()
    }

    func apply(_ state: AgentComposerState) {}
}

@MainActor
private class SpyComposer: AgentComposerInteracting {
    let view = UIView()
    private let stream: AsyncStream<AgentComposerAction>
    private let continuation: AsyncStream<AgentComposerAction>.Continuation
    private(set) var actionStreamAccessCount = 0
    private(set) var appliedStates: [AgentComposerState] = []
    private(set) var focusCallCount = 0
    private(set) var primaryActionCallCount = 0
    private(set) var terminationCount = 0
    var currentState = AgentComposerState()

    var actionStream: AsyncStream<AgentComposerAction> {
        actionStreamAccessCount += 1
        return stream
    }

    init() {
        let pair = AsyncStream<AgentComposerAction>.makeStream(
            bufferingPolicy: .bufferingNewest(32)
        )
        stream = pair.stream
        continuation = pair.continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.terminationCount += 1 }
        }
        view.accessibilityIdentifier = "SpyComposer"
    }

    func apply(_ state: AgentComposerState) {
        currentState = state
        appliedStates.append(state)
    }

    @discardableResult
    func focus() -> Bool {
        focusCallCount += 1
        return true
    }

    func performPrimaryAction() { primaryActionCallCount += 1 }

    func emit(_ action: AgentComposerAction) { continuation.yield(action) }

    func setLiveDraft(_ text: String) { currentState.text = text }

    deinit { continuation.finish() }
}

@MainActor
private final class ImportRoutingSpyComposer: SpyComposer, AgentComposerImportRouting {
    var importHandler: (([NSItemProvider], UIView) -> Void)?
}

@MainActor
private final class ActionRecorder {
    var actions: [AgentConversationAction] = []
}

@MainActor
private final class ComposerHostDelegateSpy: AgentConversationViewControllerDelegate,
    AgentTableConversationViewControllerDelegate
{
    var attachmentSourceView: UIView?
    var pasteSourceView: UIView?
    var pastedProviderCount = 0
    var retryAttachmentID: AgentAttachmentID?
    var updatedAttachments: [AgentAttachment]?

    func tableConversationViewControllerDidRequestAttachments(
        _ controller: AgentTableConversationViewController,
        sourceView: UIView
    ) {
        attachmentSourceView = sourceView
    }

    func conversationViewController(
        _ controller: AgentConversationViewController,
        didPaste itemProviders: [NSItemProvider],
        sourceView: UIView
    ) {
        pastedProviderCount = itemProviders.count
        pasteSourceView = sourceView
    }

    func tableConversationViewController(
        _ controller: AgentTableConversationViewController,
        didRequestRetryFor attachmentID: AgentAttachmentID
    ) {
        retryAttachmentID = attachmentID
    }

    func tableConversationViewController(
        _ controller: AgentTableConversationViewController,
        didUpdateDraftAttachments attachments: [AgentAttachment]
    ) {
        updatedAttachments = attachments
    }
}
