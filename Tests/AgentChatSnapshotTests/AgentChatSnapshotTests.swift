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
                precision: 0.99,
                perceptualPrecision: 0.98,
                traits: traits
            ),
            named: name,
            record: ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1" ? .all : nil,
            file: file,
            testName: testName,
            line: line
        )
    }
}
