import AgentChatCore
import UIKit

/// State applied to a composer implementation.
public struct AgentComposerState: Hashable, Sendable {
    /// Current draft text.
    public var text: String
    /// Current attachment metadata.
    public var attachments: [AgentAttachment]
    /// Whether the current run can be stopped.
    public var isRunning: Bool
    /// Whether sending is currently permitted.
    public var canSend: Bool
    /// Creates composer state.
    public init(
        text: String = "",
        attachments: [AgentAttachment] = [],
        isRunning: Bool = false,
        canSend: Bool = true
    ) {
        self.text = text
        self.attachments = attachments
        self.isRunning = isRunning
        self.canSend = canSend
    }
}

/// User actions emitted by a composer implementation.
public enum AgentComposerAction: Hashable, Sendable {
    /// Submits non-empty input and attachment metadata.
    case send(text: String, attachments: [AgentAttachment])
    /// Stops the current run.
    case stop
    /// Requests host attachment picking.
    case pickAttachments
}

/// A host-replaceable composer surface.
@MainActor
public protocol AgentComposerProviding: AnyObject {
    /// The composer view.
    var view: UIView { get }
    /// A single stream of user actions.
    var actionStream: AsyncStream<AgentComposerAction> { get }
    /// Applies the latest composer state.
    func apply(_ state: AgentComposerState)
}

/// A host-injected attachment picker. Core never owns attachment bytes or permissions.
@MainActor
public protocol AgentAttachmentPicking: AnyObject {
    /// Picks attachment metadata from a source view.
    func pickAttachments(from sourceView: UIView) async throws -> [AgentAttachment]
}

/// The default multiline, Dynamic Type composer.
@MainActor
public final class AgentComposerView: UIView, AgentComposerProviding {
    /// The view exposed by `AgentComposerProviding`.
    public var view: UIView { self }
    /// The stream of send, stop, and attachment actions.
    public let actionStream: AsyncStream<AgentComposerAction>

    private let continuation: AsyncStream<AgentComposerAction>.Continuation
    private let attachmentButton = UIButton(type: .system)
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let attachmentLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private var state = AgentComposerState()
    private var textHeightConstraint: NSLayoutConstraint?
    private let maximumHeight: CGFloat

    var currentState: AgentComposerState {
        var current = state
        current.text = textView.text
        return current
    }

    /// Creates the default composer.
    public init(maximumHeight: CGFloat = 180) {
        let pair = AsyncStream<AgentComposerAction>.makeStream(
            bufferingPolicy: .bufferingNewest(16)
        )
        self.actionStream = pair.stream
        self.continuation = pair.continuation
        self.maximumHeight = max(80, maximumHeight)
        super.init(frame: .zero)
        configureView()
        apply(state)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit { continuation.finish() }

    /// Applies draft, attachments, running state, and send availability.
    public func apply(_ state: AgentComposerState) {
        self.state = state
        if textView.text != state.text { textView.text = state.text }
        placeholderLabel.isHidden = !state.text.isEmpty
        attachmentLabel.text = state.attachments.map(\.name).joined(separator: ", ")
        attachmentLabel.isHidden = state.attachments.isEmpty
        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.title = state.isRunning ? AgentStrings.stop : AgentStrings.send
        buttonConfiguration.image = UIImage(
            systemName: state.isRunning ? "stop.fill" : "arrow.up"
        )
        buttonConfiguration.imagePadding = 5
        sendButton.configuration = buttonConfiguration
        let hasContent =
            !state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !state.attachments.isEmpty
        sendButton.isEnabled = state.isRunning || (state.canSend && hasContent)
        updateTextHeight()
    }

    /// Focuses the text editor.
    public func focus() { textView.becomeFirstResponder() }

    func submitCurrentInput() { sendOrStop() }

    private func configureView() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 18
        directionalLayoutMargins = .init(top: 8, leading: 10, bottom: 8, trailing: 10)

        attachmentButton.setImage(UIImage(systemName: "paperclip"), for: .normal)
        attachmentButton.accessibilityLabel = AgentStrings.attach
        attachmentButton.addAction(
            UIAction { [weak self] _ in self?.continuation.yield(.pickAttachments) },
            for: .touchUpInside
        )

        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.delegate = self
        textView.textContainerInset = .init(top: 8, left: 4, bottom: 8, right: 4)
        textView.accessibilityLabel = AgentStrings.messagePlaceholder
        textView.accessibilityIdentifier = "AgentComposerTextView"

        placeholderLabel.text = AgentStrings.messagePlaceholder
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)

        attachmentLabel.font = .preferredFont(forTextStyle: .caption1)
        attachmentLabel.adjustsFontForContentSizeCategory = true
        attachmentLabel.textColor = .secondaryLabel
        attachmentLabel.numberOfLines = 2

        sendButton.addAction(UIAction { [weak self] _ in self?.sendOrStop() }, for: .touchUpInside)
        sendButton.accessibilityIdentifier = "AgentComposerSendButton"

        let inputStack = UIStackView(arrangedSubviews: [attachmentLabel, textView])
        inputStack.axis = .vertical
        inputStack.spacing = 2
        let focusRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(focusFromTap)
        )
        focusRecognizer.cancelsTouchesInView = false
        inputStack.addGestureRecognizer(focusRecognizer)
        let stack = UIStackView(arrangedSubviews: [attachmentButton, inputStack, sendButton])
        stack.axis = .horizontal
        stack.alignment = .bottom
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        textHeightConstraint = textView.heightAnchor.constraint(equalToConstant: 44)
        textHeightConstraint?.isActive = true
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            placeholderLabel.leadingAnchor.constraint(
                equalTo: textView.leadingAnchor,
                constant: textView.textContainerInset.left + 5
            ),
            placeholderLabel.topAnchor.constraint(
                equalTo: textView.topAnchor,
                constant: textView.textContainerInset.top
            ),
        ])
    }

    private func sendOrStop() {
        if state.isRunning {
            continuation.yield(.stop)
            return
        }
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !state.attachments.isEmpty else { return }
        continuation.yield(.send(text: text, attachments: state.attachments))
    }

    private func updateTextHeight() {
        let targetWidth = max(1, textView.bounds.width)
        let size = textView.sizeThatFits(
            .init(width: targetWidth, height: .greatestFiniteMagnitude))
        let height = min(max(44, size.height), maximumHeight)
        textHeightConstraint?.constant = height
        textView.isScrollEnabled = size.height > maximumHeight
    }

    @objc private func focusFromTap() { focus() }
}

extension AgentComposerView: UITextViewDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        state.text = textView.text
        placeholderLabel.isHidden = !textView.text.isEmpty
        let hasContent =
            !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !state.attachments.isEmpty
        sendButton.isEnabled = state.isRunning || (state.canSend && hasContent)
        updateTextHeight()
    }
}
