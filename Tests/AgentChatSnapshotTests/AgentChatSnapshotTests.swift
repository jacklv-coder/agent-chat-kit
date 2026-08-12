import AgentChatCore
import SnapshotTesting
import UIKit
import XCTest

@testable import AgentChatUIKit

@MainActor
final class AgentChatSnapshotTests: XCTestCase {
    func testComposerPhoneLightAndDark() {
        let attachment = AgentAttachment(
            id: "design",
            name: "agent-chat-design.png",
            mediaType: "image/png",
            byteCount: 42_000,
            reference: .localIdentifier("design")
        )
        let state = AgentComposerState(
            text: "Compare the SDK states and stream the result",
            attachments: [attachment],
            attachmentStatuses: ["design": .uploading(progress: 0.42)],
            accessories: [
                .init(id: "model", title: "GPT-5", systemImageName: "cpu"),
                .init(id: "reasoning", title: "Medium", systemImageName: "brain"),
            ],
            contextDescription: "32k",
            canPickAttachments: true
        )

        assertComposerSnapshot(state: state, style: .light, width: 390, name: "phone-light")
        assertComposerSnapshot(state: state, style: .dark, width: 390, name: "phone-dark")
    }

    func testComposerIPadFailureAndRunningStates() {
        let attachment = AgentAttachment(
            id: "report",
            name: "integration-report.pdf",
            mediaType: "application/pdf",
            reference: .localIdentifier("report")
        )
        let failure = AgentComposerState(
            text: "The draft remains available after reconnecting",
            attachments: [attachment],
            attachmentStatuses: ["report": .failed(message: "Upload failed")],
            accessories: [
                .init(id: "workspace", title: "AgentChatKit", systemImageName: "folder")
            ],
            statusMessage: "Reconnect before sending",
            contextDescription: "Offline",
            canSend: false
        )
        let running = AgentComposerState(
            text: "Continue after the tool result",
            accessories: [
                .init(id: "model", title: "Local", systemImageName: "cpu", isSelected: true)
            ],
            statusMessage: "Running",
            contextDescription: "18k",
            isRunning: true,
            canSend: false
        )

        assertComposerSnapshot(state: failure, style: .light, width: 720, name: "ipad-failure")
        assertComposerSnapshot(state: running, style: .dark, width: 720, name: "ipad-running")
    }

    func testConversationPhoneEnglishRichContent() async {
        await assertConversationSnapshot(
            blocks: richContentBlocks(),
            style: .light,
            size: .init(width: 390, height: 844),
            contentSizeCategory: .large,
            layoutDirection: .leftToRight,
            name: "phone-english-rich-content"
        )
    }

    func testConversationPhoneDarkToolLifecycle() async {
        await assertConversationSnapshot(
            blocks: toolLifecycleBlocks(),
            style: .dark,
            size: .init(width: 430, height: 932),
            contentSizeCategory: .accessibilityLarge,
            layoutDirection: .leftToRight,
            name: "phone-dark-tool-lifecycle"
        )
    }

    func testConversationIPadChineseActionsLandscape() async {
        await assertConversationSnapshot(
            blocks: actionBlocks(),
            style: .light,
            size: .init(width: 1_024, height: 768),
            contentSizeCategory: .extraExtraLarge,
            layoutDirection: .leftToRight,
            accessibilityContrast: .high,
            name: "ipad-chinese-actions-landscape"
        )
    }

    func testConversationPhoneRTLLandscape() async {
        await assertConversationSnapshot(
            blocks: rtlBlocks(),
            style: .dark,
            size: .init(width: 844, height: 390),
            contentSizeCategory: .large,
            layoutDirection: .rightToLeft,
            name: "phone-rtl-landscape"
        )
    }

    private func assertComposerSnapshot(
        state: AgentComposerState,
        style: UIUserInterfaceStyle,
        width: CGFloat,
        name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let composer = AgentComposerView()
        composer.overrideUserInterfaceStyle = style
        composer.apply(state)
        composer.frame = .init(x: 0, y: 0, width: width, height: 280)
        composer.setNeedsLayout()
        composer.layoutIfNeeded()
        let fittingHeight = composer.systemLayoutSizeFitting(
            .init(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        composer.frame.size.height = fittingHeight
        composer.layoutIfNeeded()
        let traits = UITraitCollection { mutableTraits in
            mutableTraits.userInterfaceStyle = style
            mutableTraits.horizontalSizeClass = width > 500 ? .regular : .compact
            mutableTraits.verticalSizeClass = .regular
            mutableTraits.displayScale = width > 500 ? 2 : 3
        }

        assertSnapshot(
            of: composer,
            as: .image(
                // Keep geometry strict while allowing the small font and SF Symbols
                // rasterization differences between supported Xcode/iOS runtimes.
                precision: 0.98,
                perceptualPrecision: 0.84,
                traits: traits
            ),
            named: name,
            record: ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1" ? .all : nil,
            file: file,
            testName: testName,
            line: line
        )
    }

    private func assertConversationSnapshot(
        blocks: [AgentBlock],
        style: UIUserInterfaceStyle,
        size: CGSize,
        contentSizeCategory: UIContentSizeCategory,
        layoutDirection: UITraitEnvironmentLayoutDirection,
        accessibilityContrast: UIAccessibilityContrast = .normal,
        name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) async {
        let previousTimeZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
        defer { NSTimeZone.default = previousTimeZone }

        let date = Date(timeIntervalSince1970: 0)
        let turn = AgentTurn(
            id: .init(rawValue: "snapshot-turn-\(name)"),
            role: .assistant,
            blocks: blocks,
            state: .completed,
            createdAt: date,
            completedAt: date
        )
        let store = AgentConversationStore(
            snapshot: .init(
                id: .init(rawValue: "snapshot-conversation-\(name)"),
                turns: [turn],
                state: .connected
            )
        )
        let configuration = AgentConversationConfiguration(
            runtimeCapabilities: [.retry],
            composerAccessories: [
                .init(id: "model", title: "GPT-5", systemImageName: "cpu")
            ],
            composerContextDescription: "32k",
            imageProvider: SnapshotImageProvider(),
            toolPresentationStyle: .capsule
        )
        let controller = AgentTableConversationViewController(
            store: store,
            configuration: configuration
        )
        let traits = UITraitCollection { mutableTraits in
            mutableTraits.userInterfaceStyle = style
            mutableTraits.horizontalSizeClass = size.width > 700 ? .regular : .compact
            mutableTraits.verticalSizeClass = size.height > 500 ? .regular : .compact
            mutableTraits.preferredContentSizeCategory = contentSizeCategory
            mutableTraits.layoutDirection = layoutDirection
            mutableTraits.accessibilityContrast = accessibilityContrast
            mutableTraits.displayScale = size.width > 700 ? 2 : 3
        }
        controller.traitOverrides.userInterfaceStyle = style
        controller.traitOverrides.horizontalSizeClass = size.width > 700 ? .regular : .compact
        controller.traitOverrides.verticalSizeClass = size.height > 500 ? .regular : .compact
        controller.traitOverrides.preferredContentSizeCategory = contentSizeCategory
        controller.traitOverrides.layoutDirection = layoutDirection
        controller.traitOverrides.accessibilityContrast = accessibilityContrast
        controller.overrideUserInterfaceStyle = style
        controller.view.semanticContentAttribute =
            layoutDirection == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        let window = UIWindow(frame: .init(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = style
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        try? await Task.sleep(for: .milliseconds(250))
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        guard let tableView = controller.view.findSubview(of: UITableView.self) else {
            XCTFail("The production conversation table is missing")
            return
        }
        XCTAssertGreaterThan(tableView.frame.height, 0)
        XCTAssertEqual(tableView.numberOfSections, 1)
        tableView.setContentOffset(
            .init(x: 0, y: -tableView.adjustedContentInset.top),
            animated: false
        )
        tableView.layoutIfNeeded()

        let rendererFormat = UIGraphicsImageRendererFormat(for: traits)
        rendererFormat.scale = traits.displayScale
        let renderedImage = UIGraphicsImageRenderer(
            size: size,
            format: rendererFormat
        ).image { context in
            controller.view.layer.render(in: context.cgContext)
        }
        assertSnapshot(
            of: renderedImage,
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.84,
                scale: traits.displayScale
            ),
            named: name,
            record: ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1" ? .all : nil,
            file: file,
            testName: testName,
            line: line
        )
    }

    private func richContentBlocks() -> [AgentBlock] {
        let date = Date(timeIntervalSince1970: 0)
        return [
            block(
                "user",
                content: .userText(
                    .init(
                        text: "Review the conversation SDK and keep the result concise.",
                        attachments: [
                            .init(
                                id: "requirements",
                                name: "requirements.md",
                                mediaType: "text/markdown",
                                byteCount: 4_096,
                                reference: .localIdentifier("requirements")
                            )
                        ]
                    )
                ),
                state: .succeeded,
                date: date
            ),
            block(
                "markdown",
                content: .markdown(
                    .init(
                        markdown: """
                            ## Native message list

                            **Bold**, *emphasis*, `inline code`, and [a link](https://example.com).

                            | Capability | Status |
                            | --- | --- |
                            | Streaming updates | Ready |
                            | History anchors | Stable |

                            ```swift
                            let controller = AgentTableConversationViewController(store: store)
                            ```
                            """,
                        isFinal: true
                    )
                ),
                state: .succeeded,
                date: date
            ),
        ]
    }

    private func toolLifecycleBlocks() -> [AgentBlock] {
        let date = Date(timeIntervalSince1970: 0)
        var output = AgentTextBuffer()
        output.append("Building AgentChatKit…\nAll tests passed.\n")
        return [
            block(
                "thinking",
                content: .activity(
                    .init(
                        title: "Analyzing the project", detail: "Inspecting list updates and cells."
                    )
                ),
                state: .running(progress: 0.45),
                date: date,
                metadata: [AgentBlockMetadataKey.activityKind: .string("reasoning")]
            ),
            block(
                "tool",
                content: .tool(
                    .init(
                        toolName: "repository.inspect",
                        title: "Inspected repository",
                        summary: "Found 42 Swift files.",
                        input: .object(["root": .string("/project")]),
                        output: .object(["files": .number(42)]),
                        displayMode: .expanded
                    )
                ),
                state: .succeeded,
                date: date
            ),
            block(
                "command",
                content: .command(
                    .init(command: "swift test", output: output, exitCode: 0, duration: 1.2)
                ),
                state: .succeeded,
                date: date
            ),
            block(
                "search",
                content: .fileSearch(
                    .init(
                        query: "AgentTableConversationViewController",
                        root: "Sources",
                        matches: [
                            .init(path: "Sources/AgentChatUIKit/Conversation.swift", line: 41)
                        ],
                        totalCount: 1
                    )
                ),
                state: .streaming,
                date: date
            ),
            block(
                "file",
                content: .fileOperation(
                    .init(
                        operation: .update,
                        path: "Sources/AgentChatUIKit/Conversation.swift",
                        summary: "Updated targeted row sizing."
                    )
                ),
                state: .queued,
                date: date
            ),
        ]
    }

    private func actionBlocks() -> [AgentBlock] {
        let date = Date(timeIntervalSince1970: 0)
        let failure = AgentFailure(
            code: "preview.timeout",
            message: "预览请求超时，可安全重试。",
            isRetryable: true
        )
        return [
            block(
                "diff",
                content: .diff(
                    .init(
                        title: "更新消息列表",
                        files: [
                            .init(
                                oldPath: "旧文件.swift",
                                newPath: "会话列表.swift",
                                hunks: [
                                    .init(
                                        header: "@@ -1 +1 @@",
                                        lines: [
                                            .init(kind: .deletion, text: "reloadData()"),
                                            .init(kind: .addition, text: "insertRows(at:)"),
                                        ]
                                    )
                                ]
                            )
                        ]
                    )
                ),
                state: .succeeded,
                date: date
            ),
            block(
                "approval",
                content: .approval(
                    .init(
                        approvalID: "publish",
                        title: "是否发布已验证的改动？",
                        message: "该操作会推送到远端仓库。",
                        risk: .medium,
                        choices: [
                            .init(id: "approve", title: "允许", role: .approve),
                            .init(id: "reject", title: "取消", role: .reject),
                        ]
                    )
                ),
                state: .waitingForApproval,
                date: date
            ),
            block(
                "artifact",
                content: .artifact(
                    .init(
                        id: "report",
                        title: "性能验收报告",
                        mediaType: "text/markdown",
                        reference: .runtimeURI("artifact://performance"),
                        summary: "包含六类压力场景。"
                    )
                ),
                state: .succeeded,
                date: date
            ),
            block(
                "image",
                content: .image(
                    .init(
                        reference: .localIdentifier("timeline-preview"),
                        alternativeText: "会话列表预览"
                    )
                ),
                state: .succeeded,
                date: date
            ),
            block(
                "error",
                content: .error(.init(failure: failure, retryTitle: "重试预览")),
                state: .failed(failure),
                date: date
            ),
            block(
                "custom",
                kind: "company.release",
                content: .custom(
                    .init(
                        kind: "company.release",
                        payload: .object(["ready": .bool(true)]),
                        fallbackTitle: "自定义发布摘要",
                        fallbackSummary: "未注册 Renderer 时使用安全回退。"
                    )
                ),
                state: .cancelled,
                date: date
            ),
        ]
    }

    private func rtlBlocks() -> [AgentBlock] {
        let date = Date(timeIntervalSince1970: 0)
        return [
            block(
                "rtl-markdown",
                content: .markdown(
                    .init(
                        markdown: "## قائمة الرسائل\n\nتحديثات متدفقة مع موضع قراءة ثابت.",
                        isFinal: true)
                ),
                state: .succeeded,
                date: date
            ),
            block(
                "rtl-tool",
                content: .activity(
                    .init(title: "جارٍ تحليل المشروع", detail: "تم فحص قائمة الرسائل")),
                state: .running(progress: nil),
                date: date
            ),
        ]
    }

    private func block(
        _ id: AgentBlockID,
        kind: AgentBlockKind? = nil,
        content: AgentBlockContent,
        state: AgentBlockState,
        date: Date,
        metadata: [String: JSONValue] = [:]
    ) -> AgentBlock {
        AgentBlock(
            id: id,
            kind: kind ?? content.blockKind,
            content: content,
            state: state,
            createdAt: date,
            metadata: metadata
        )
    }
}

private struct SnapshotImageProvider: AgentImageProviding {
    func image(
        for reference: AgentResourceReference,
        targetSize: CGSize,
        scale: CGFloat
    ) async throws -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: .init(width: 320, height: 160), format: format)
            .image { context in
                UIColor(red: 0.08, green: 0.49, blue: 0.95, alpha: 1).setFill()
                context.fill(.init(x: 0, y: 0, width: 320, height: 160))
                UIColor.white.withAlphaComponent(0.22).setFill()
                context.fill(.init(x: 24, y: 24, width: 272, height: 112))
            }
    }
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

extension UIView {
    fileprivate func findSubview<T: UIView>(of type: T.Type) -> T? {
        if let view = self as? T { return view }
        for subview in subviews {
            if let match = subview.findSubview(of: type) { return match }
        }
        return nil
    }
}
