import XCTest

@MainActor
final class AgentChatDemoUITests: XCTestCase {
    private func makeDefaultApp() -> XCUIApplication {
        XCUIApplication()
    }

    private func makeApp(
        scenario: String = "complete-cell-showcase",
        playbackMode: String = "instant"
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--agentchat-uitest"]
        app.launchEnvironment["AGENTCHAT_SCENARIO"] = scenario
        app.launchEnvironment["AGENTCHAT_PLAYBACK_MODE"] = playbackMode
        return app
    }

    private func contentElement(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
    }

    func testDefaultLaunchOpensCompleteConversationExperience() {
        continueAfterFailure = false
        let app = makeDefaultApp()
        app.launch()

        XCTAssertTrue(app.navigationBars["Complete Conversation"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.collectionViews["AgentConversationTimeline"].waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.textViews["AgentComposerTextView"].exists)
        XCTAssertTrue(app.buttons["AgentChatDemoTestLab"].exists)
    }

    func testComposerAcceptsTouchInputAndStreamsAResponse() {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        let editor = app.textViews["AgentComposerTextView"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))

        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        editor.typeText("Show the SDK integration states")

        let send = app.buttons["AgentComposerSendButton"]
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: send)
        waitForExpectations(timeout: 5)
        send.tap()

        let response = app.cells.matching(
            NSPredicate(format: "label CONTAINS %@", "Demo 实时响应")
        ).firstMatch
        XCTAssertTrue(response.waitForExistence(timeout: 15))

        let tableResult = app.descendants(matching: .any)
            .matching(identifier: "AgentMarkdownTableCell")
            .matching(NSPredicate(format: "label CONTAINS %@", "Markdown 表格"))
            .firstMatch
        XCTAssertTrue(tableResult.waitForExistence(timeout: 5))
    }

    func testThinkingLifecycleShowsRunningReasoningRow() {
        continueAfterFailure = false
        let app = makeApp(scenario: "thinking-lifecycle")
        app.launch()

        let thinking = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ AND label BEGINSWITH %@",
                "AgentActivityEventHeader",
                "Thinking"
            )
        ).firstMatch
        XCTAssertTrue(thinking.waitForExistence(timeout: 10))
    }

    func testCapsuleCommandExpandsFromTheWholeHeader() {
        continueAfterFailure = false
        let app = makeApp(scenario: "shell-command")
        app.launch()

        let header = app.buttons["AgentActivityEventHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertEqual(header.value as? String, "Expand")

        header.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["AgentActivityEventDetails"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertEqual(header.value as? String, "Collapse")
    }

    func testTableTimelineExpandsToolAndAppendsComposerResponse() {
        continueAfterFailure = false
        let app = makeApp(scenario: "shell-command")
        app.launch()

        let lab = app.buttons["AgentChatDemoTestLab"]
        XCTAssertTrue(lab.waitForExistence(timeout: 10))
        lab.tap()
        let openTable = app.buttons["Open TableView Version"]
        XCTAssertTrue(openTable.waitForExistence(timeout: 5))
        openTable.tap()

        let timeline = app.tables["AgentTableConversationTimeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 10))
        let header = app.buttons["AgentActivityEventHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertEqual(header.value as? String, "Expand")

        header.tap()

        expectation(
            for: NSPredicate(format: "value == %@", "Collapse"),
            evaluatedWith: header
        )
        waitForExpectations(timeout: 2)
        XCTAssertEqual(header.value as? String, "Collapse")
        XCTAssertTrue(app.staticTexts["Output"].exists)

        let editor = app.textViews["AgentComposerTextView"]
        editor.tap()
        editor.typeText("Animate a response at the bottom")
        app.buttons["AgentComposerSendButton"].tap()

        let response = contentElement(containing: "Demo 实时响应", in: app)
        XCTAssertTrue(response.waitForExistence(timeout: 15))
    }

    func testTableTimelineBatchInsertsMessagesAtBottom() {
        continueAfterFailure = false
        let app = makeApp(
            scenario: "bottom-batch-insertion",
            playbackMode: "realtime"
        )
        app.launchEnvironment["AGENTCHAT_TIMELINE"] = "table"
        app.launch()

        let timeline = app.tables["AgentTableConversationTimeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Initial message 18"].waitForExistence(timeout: 5))

        let lastInsertedMessage = app.staticTexts["Batch message 8"]
        XCTAssertTrue(lastInsertedMessage.waitForExistence(timeout: 6))
        let timelineFrame = timeline.frame
        let visibleInsideTimeline = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return element.frame.intersects(timelineFrame)
                && element.frame.maxY <= timelineFrame.maxY + 1
        }
        expectation(
            for: visibleInsideTimeline,
            evaluatedWith: lastInsertedMessage
        )
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.staticTexts["Batch message 7"].exists)
    }

    func testFailedCapsuleCanRetryToSuccess() {
        continueAfterFailure = false
        let app = makeApp(scenario: "failure-and-retry")
        app.launch()

        let retry = app.buttons["AgentActivityEventRetry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        retry.tap()

        let succeeded = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Publish package")
        ).firstMatch
        XCTAssertTrue(succeeded.waitForExistence(timeout: 5))
    }

    func testTestLabAndRichComposerControlsAreDiscoverable() {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.buttons["AgentChatDemoTestLab"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["AgentComposerAttachmentButton"].exists)
        XCTAssertTrue(app.buttons["AgentComposerAccessory.model"].exists)
        XCTAssertTrue(app.buttons["AgentComposerAccessory.reasoning"].exists)
        XCTAssertTrue(app.buttons["AgentComposerAccessory.workspace"].exists)

        app.buttons["AgentChatDemoTestLab"].tap()
        let browse = app.buttons["Browse All Scenarios"]
        XCTAssertTrue(browse.waitForExistence(timeout: 5))
        browse.tap()
        XCTAssertTrue(app.navigationBars["Test Lab"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.cells["AgentChatDemoScenario.complete-conversation"].exists)
        XCTAssertTrue(app.cells["AgentChatDemoScenario.complete-cell-showcase"].exists)
    }

    func testCompletedPlaybackShowsStateAndRunsSampleResponse() {
        continueAfterFailure = false
        let app = makeApp(scenario: "complete-conversation")
        app.launch()
        XCTAssertTrue(
            contentElement(containing: "完整会话体验", in: app).waitForExistence(timeout: 10)
        )

        let lab = app.buttons["AgentChatDemoTestLab"]
        XCTAssertTrue(lab.waitForExistence(timeout: 10))
        lab.tap()

        let status = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Playback: Completed")
        ).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Resume"].isEnabled)
        XCTAssertFalse(app.buttons["Pause"].isEnabled)
        XCTAssertFalse(app.buttons["Step"].isEnabled)
        XCTAssertTrue(app.buttons["Replay Scenario"].isEnabled)

        let sample = app.buttons["Run Sample Response"]
        XCTAssertTrue(sample.isEnabled)
        sample.tap()

        let response = app.cells.matching(
            NSPredicate(format: "label CONTAINS %@", "Demo 实时响应")
        ).firstMatch
        XCTAssertTrue(response.waitForExistence(timeout: 15))

        lab.tap()
        let replay = app.buttons["Replay Scenario"]
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
        replay.tap()
        XCTAssertTrue(response.waitForNonExistence(timeout: 5))
    }

    func testPausedPlaybackCanResume() {
        continueAfterFailure = false
        let app = makeApp(scenario: "basic-streaming", playbackMode: "paused")
        app.launch()

        let lab = app.buttons["AgentChatDemoTestLab"]
        XCTAssertTrue(lab.waitForExistence(timeout: 10))
        lab.tap()
        let status = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Playback: Paused")
        ).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))

        let resume = app.buttons["Resume"]
        XCTAssertTrue(resume.isEnabled)
        resume.tap()

        let streamedContent = app.cells.matching(
            NSPredicate(format: "label CONTAINS %@", "Hello from AgentChatKit")
        ).firstMatch
        XCTAssertTrue(streamedContent.waitForExistence(timeout: 10))
    }

    func testResetPausedCanReleaseOneStep() {
        continueAfterFailure = false
        let app = makeApp(scenario: "complete-conversation")
        app.launch()
        XCTAssertTrue(
            contentElement(containing: "完整会话体验", in: app).waitForExistence(timeout: 10)
        )

        let lab = app.buttons["AgentChatDemoTestLab"]
        lab.tap()
        let reset = app.buttons["Reset Paused"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()

        XCTAssertTrue(lab.waitForExistence(timeout: 5))
        lab.tap()
        let status = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Playback: Paused")
        ).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))

        let step = app.buttons["Step"]
        XCTAssertTrue(step.isEnabled)
        step.tap()
        XCTAssertTrue(
            contentElement(containing: "完整会话体验", in: app).waitForExistence(timeout: 10)
        )
    }

    func testManualReadingShowsUnreadControlAndCanReturnToLatest() {
        continueAfterFailure = false
        let app = makeApp(scenario: "complete-conversation")
        app.launch()
        let timeline = app.collectionViews["AgentConversationTimeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 10))

        timeline.swipeDown()
        timeline.swipeDown()

        let editor = app.textViews["AgentComposerTextView"]
        editor.tap()
        editor.typeText("Stream a new result while I read history")
        app.buttons["AgentComposerSendButton"].tap()

        let jump = app.buttons["AgentConversationJumpToLatestButton"]
        XCTAssertTrue(jump.waitForExistence(timeout: 5))
        jump.tap()

        let response = app.cells.matching(
            NSPredicate(format: "label CONTAINS %@", "Demo 实时响应")
        ).firstMatch
        XCTAssertTrue(response.waitForExistence(timeout: 15))
    }

    func testHistoryPaginationLoadsEarlierPage() {
        continueAfterFailure = false
        let app = makeApp(scenario: "history-pagination")
        app.launch()
        let timeline = app.collectionViews["AgentConversationTimeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 10))

        timeline.swipeDown()
        let historyMarker = app.cells.matching(
            NSPredicate(format: "label CONTAINS %@", "历史消息 #1")
        ).firstMatch
        for _ in 0..<4 where !historyMarker.exists {
            timeline.swipeDown()
        }
        XCTAssertTrue(historyMarker.waitForExistence(timeout: 8))
    }

    func testMarkdownTableScenarioExposesTableContent() {
        continueAfterFailure = false
        let app = makeApp(scenario: "markdown-showcase")
        app.launch()

        XCTAssertTrue(app.staticTexts["Markdown Showcase"].waitForExistence(timeout: 10))
        let tableHeader = app.descendants(matching: .any)
            .matching(identifier: "AgentMarkdownTableCell")
            .matching(NSPredicate(format: "label CONTAINS %@", "Feature"))
            .firstMatch
        XCTAssertTrue(tableHeader.waitForExistence(timeout: 10))
    }
}
