import XCTest

@MainActor
final class AgentChatDemoUITests: XCTestCase {
    private func makeApp(scenario: String = "complete-cell-showcase") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--agentchat-uitest"]
        app.launchEnvironment["AGENTCHAT_SCENARIO"] = scenario
        app.launchEnvironment["AGENTCHAT_PLAYBACK_MODE"] = "instant"
        return app
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

        let thinking = app.cells.matching(
            NSPredicate(format: "label CONTAINS %@", "思考")
        ).firstMatch
        XCTAssertTrue(thinking.waitForExistence(timeout: 3))

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

    func testTestLabAndRichComposerControlsAreDiscoverable() {
        continueAfterFailure = false
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.buttons["AgentChatDemoTestLab"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["AgentComposerAttachmentButton"].exists)
        XCTAssertTrue(app.buttons["AgentComposerAccessory.model"].exists)
        XCTAssertTrue(app.buttons["AgentComposerAccessory.reasoning"].exists)
        XCTAssertTrue(app.buttons["AgentComposerAccessory.workspace"].exists)
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
