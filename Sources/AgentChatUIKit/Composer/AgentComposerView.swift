import AgentChatCore
import UIKit
import UniformTypeIdentifiers

/// Upload or validation state shown for an input attachment.
public enum AgentComposerAttachmentStatus: Hashable, Sendable {
    /// The attachment is ready to submit.
    case ready
    /// The host is preparing or uploading the attachment.
    case uploading(progress: Double?)
    /// The attachment needs user attention.
    case failed(message: String)
}

/// A runtime-neutral control supplied by a host for model, reasoning, workspace, or custom input.
public struct AgentComposerAccessory: Identifiable, Hashable, Sendable {
    /// Stable control identifier routed back in `AgentComposerAction`.
    public var id: String
    /// User-visible short title.
    public var title: String
    /// Optional SF Symbol name.
    public var systemImageName: String?
    /// Whether the current value is selected.
    public var isSelected: Bool
    /// Whether the control accepts interaction.
    public var isEnabled: Bool

    /// Creates a host-defined composer control.
    public init(
        id: String,
        title: String,
        systemImageName: String? = nil,
        isSelected: Bool = false,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.systemImageName = systemImageName
        self.isSelected = isSelected
        self.isEnabled = isEnabled
    }
}

/// State applied to a composer implementation.
public struct AgentComposerState: Hashable, Sendable {
    /// Current draft text.
    public var text: String
    /// Current attachment metadata.
    public var attachments: [AgentAttachment]
    /// Per-attachment upload or validation state.
    public var attachmentStatuses: [AgentAttachmentID: AgentComposerAttachmentStatus]
    /// Host-defined controls such as model or workspace selection.
    public var accessories: [AgentComposerAccessory]
    /// Optional status or disabled-reason text displayed above the toolbar.
    public var statusMessage: String?
    /// Optional compact context-budget or runtime description.
    public var contextDescription: String?
    /// Whether the current run can be stopped.
    public var isRunning: Bool
    /// Whether sending is currently permitted.
    public var canSend: Bool
    /// Whether attachment picking is available.
    public var canPickAttachments: Bool

    /// Creates composer state.
    public init(
        text: String = "",
        attachments: [AgentAttachment] = [],
        attachmentStatuses: [AgentAttachmentID: AgentComposerAttachmentStatus] = [:],
        accessories: [AgentComposerAccessory] = [],
        statusMessage: String? = nil,
        contextDescription: String? = nil,
        isRunning: Bool = false,
        canSend: Bool = true,
        canPickAttachments: Bool = true
    ) {
        self.text = text
        self.attachments = attachments
        self.attachmentStatuses = attachmentStatuses
        self.accessories = accessories
        self.statusMessage = statusMessage
        self.contextDescription = contextDescription
        self.isRunning = isRunning
        self.canSend = canSend
        self.canPickAttachments = canPickAttachments
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
    /// Removes an attachment from the pending draft.
    case removeAttachment(AgentAttachmentID)
    /// Retries host preparation of a failed attachment.
    case retryAttachment(AgentAttachmentID)
    /// Selects a host-defined composer control.
    case selectAccessory(String)
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
    /// The stream of send, stop, attachment, and accessory actions.
    public let actionStream: AsyncStream<AgentComposerAction>
    /// Called when the user pastes non-text item providers into the default text editor.
    public var importHandler: (([NSItemProvider], UIView) -> Void)?

    private let continuation: AsyncStream<AgentComposerAction>.Continuation
    private let rootStack = UIStackView()
    private let statusLabel = UILabel()
    private let attachmentScrollView = UIScrollView()
    private let attachmentStack = UIStackView()
    private let textView = AgentComposerTextView()
    private let placeholderLabel = UILabel()
    private let toolbar = UIStackView()
    private let attachmentButton = UIButton(type: .system)
    private let accessoryScrollView = UIScrollView()
    private let accessoryStack = UIStackView()
    private let contextLabel = UILabel()
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
            bufferingPolicy: .bufferingNewest(32)
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

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateTextHeight()
    }

    /// Applies draft, attachments, runtime state, and host-defined controls.
    public func apply(_ state: AgentComposerState) {
        self.state = state
        if textView.text != state.text { textView.text = state.text }
        placeholderLabel.isHidden = !state.text.isEmpty
        statusLabel.text = state.statusMessage
        statusLabel.isHidden = state.statusMessage?.isEmpty != false
        contextLabel.text = state.contextDescription
        contextLabel.isHidden = state.contextDescription?.isEmpty != false
        attachmentButton.isEnabled = state.canPickAttachments
        attachmentButton.isHidden = !state.canPickAttachments
        rebuildAttachments()
        rebuildAccessories()
        configureSendButton()
        updateTextHeight()
    }

    /// Focuses the text editor.
    @discardableResult
    public func focus() -> Bool { textView.becomeFirstResponder() }

    func submitCurrentInput() { sendOrStop() }

    private func configureView() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.borderWidth = 1 / UIScreen.main.scale
        layer.borderColor = UIColor.separator.withAlphaComponent(0.5).cgColor
        directionalLayoutMargins = .init(top: 10, leading: 12, bottom: 8, trailing: 10)
        accessibilityIdentifier = "AgentComposer"

        rootStack.axis = .vertical
        rootStack.spacing = 6
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)

        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 2
        statusLabel.accessibilityIdentifier = "AgentComposerStatus"
        rootStack.addArrangedSubview(statusLabel)

        attachmentScrollView.showsHorizontalScrollIndicator = false
        attachmentScrollView.accessibilityIdentifier = "AgentComposerAttachmentStrip"
        attachmentStack.axis = .horizontal
        attachmentStack.alignment = .center
        attachmentStack.spacing = 6
        attachmentStack.translatesAutoresizingMaskIntoConstraints = false
        attachmentScrollView.addSubview(attachmentStack)
        NSLayoutConstraint.activate([
            attachmentStack.leadingAnchor.constraint(
                equalTo: attachmentScrollView.contentLayoutGuide.leadingAnchor),
            attachmentStack.trailingAnchor.constraint(
                equalTo: attachmentScrollView.contentLayoutGuide.trailingAnchor),
            attachmentStack.topAnchor.constraint(
                equalTo: attachmentScrollView.contentLayoutGuide.topAnchor),
            attachmentStack.bottomAnchor.constraint(
                equalTo: attachmentScrollView.contentLayoutGuide.bottomAnchor),
            attachmentStack.heightAnchor.constraint(
                equalTo: attachmentScrollView.frameLayoutGuide.heightAnchor),
            attachmentScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
        ])
        rootStack.addArrangedSubview(attachmentScrollView)

        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.delegate = self
        textView.textContainerInset = .init(top: 6, left: 0, bottom: 6, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.accessibilityLabel = AgentStrings.messagePlaceholder
        textView.accessibilityIdentifier = "AgentComposerTextView"
        textView.importItemProviders = { [weak self] providers in
            guard let self, !providers.isEmpty else { return false }
            self.importHandler?(providers, self)
            return self.importHandler != nil
        }

        placeholderLabel.text = AgentStrings.messagePlaceholder
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)
        textHeightConstraint = textView.heightAnchor.constraint(equalToConstant: 44)
        textHeightConstraint?.isActive = true
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.topAnchor.constraint(
                equalTo: textView.topAnchor,
                constant: textView.textContainerInset.top
            ),
        ])
        rootStack.addArrangedSubview(textView)

        toolbar.axis = .horizontal
        toolbar.alignment = .center
        toolbar.spacing = 7
        rootStack.addArrangedSubview(toolbar)

        var attachmentConfiguration = UIButton.Configuration.plain()
        attachmentConfiguration.image = UIImage(systemName: "plus")
        attachmentConfiguration.cornerStyle = .capsule
        attachmentButton.configuration = attachmentConfiguration
        attachmentButton.accessibilityLabel = AgentStrings.attach
        attachmentButton.accessibilityIdentifier = "AgentComposerAttachmentButton"
        attachmentButton.addAction(
            UIAction { [weak self] _ in self?.continuation.yield(.pickAttachments) },
            for: .touchUpInside
        )
        NSLayoutConstraint.activate([
            attachmentButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            attachmentButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        toolbar.addArrangedSubview(attachmentButton)

        accessoryScrollView.showsHorizontalScrollIndicator = false
        accessoryStack.axis = .horizontal
        accessoryStack.alignment = .center
        accessoryStack.spacing = 4
        accessoryStack.translatesAutoresizingMaskIntoConstraints = false
        accessoryScrollView.addSubview(accessoryStack)
        NSLayoutConstraint.activate([
            accessoryStack.leadingAnchor.constraint(
                equalTo: accessoryScrollView.contentLayoutGuide.leadingAnchor),
            accessoryStack.trailingAnchor.constraint(
                equalTo: accessoryScrollView.contentLayoutGuide.trailingAnchor),
            accessoryStack.topAnchor.constraint(
                equalTo: accessoryScrollView.contentLayoutGuide.topAnchor),
            accessoryStack.bottomAnchor.constraint(
                equalTo: accessoryScrollView.contentLayoutGuide.bottomAnchor),
            accessoryStack.heightAnchor.constraint(
                equalTo: accessoryScrollView.frameLayoutGuide.heightAnchor),
        ])
        accessoryScrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        accessoryScrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        toolbar.addArrangedSubview(accessoryScrollView)

        contextLabel.font = .preferredFont(forTextStyle: .caption2)
        contextLabel.adjustsFontForContentSizeCategory = true
        contextLabel.textColor = .tertiaryLabel
        contextLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        toolbar.addArrangedSubview(contextLabel)

        sendButton.accessibilityIdentifier = "AgentComposerSendButton"
        sendButton.addAction(UIAction { [weak self] _ in self?.sendOrStop() }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            sendButton.widthAnchor.constraint(equalToConstant: 44),
            sendButton.heightAnchor.constraint(equalToConstant: 44),
        ])
        toolbar.addArrangedSubview(sendButton)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])
    }

    private func rebuildAttachments() {
        for view in attachmentStack.arrangedSubviews {
            attachmentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for attachment in state.attachments {
            let chip = AgentComposerAttachmentChip(
                attachment: attachment,
                status: state.attachmentStatuses[attachment.id] ?? .ready
            )
            chip.onRemove = { [weak self] in self?.removeAttachment(attachment.id) }
            chip.onRetry = { [weak self] in
                self?.continuation.yield(.retryAttachment(attachment.id))
            }
            attachmentStack.addArrangedSubview(chip)
        }
        attachmentScrollView.isHidden = state.attachments.isEmpty
    }

    private func rebuildAccessories() {
        for view in accessoryStack.arrangedSubviews {
            accessoryStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for accessory in state.accessories {
            var configuration = UIButton.Configuration.gray()
            configuration.title = accessory.title
            configuration.image = accessory.systemImageName.flatMap(UIImage.init(systemName:))
            configuration.imagePadding = 4
            configuration.cornerStyle = .capsule
            if accessory.isSelected { configuration.baseForegroundColor = .systemBlue }
            let button = UIButton(configuration: configuration)
            button.isEnabled = accessory.isEnabled
            button.accessibilityIdentifier = "AgentComposerAccessory.\(accessory.id)"
            button.addAction(
                UIAction { [weak self] _ in
                    self?.continuation.yield(.selectAccessory(accessory.id))
                },
                for: .touchUpInside
            )
            accessoryStack.addArrangedSubview(button)
        }
        accessoryScrollView.isHidden = state.accessories.isEmpty
    }

    private func configureSendButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: state.isRunning ? "stop.fill" : "arrow.up")
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = state.isRunning ? .systemRed : .systemBlue
        sendButton.configuration = configuration
        sendButton.accessibilityLabel = state.isRunning ? AgentStrings.stop : AgentStrings.send
        let hasContent =
            !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !state.attachments.isEmpty
        let hasUnavailableAttachment = state.attachments.contains { attachment in
            switch state.attachmentStatuses[attachment.id] ?? .ready {
            case .ready: false
            case .uploading, .failed: true
            }
        }
        sendButton.isEnabled =
            state.isRunning || (state.canSend && hasContent && !hasUnavailableAttachment)
    }

    private func removeAttachment(_ id: AgentAttachmentID) {
        state.attachments.removeAll { $0.id == id }
        state.attachmentStatuses[id] = nil
        apply(state)
        continuation.yield(.removeAttachment(id))
    }

    private func sendOrStop() {
        if state.isRunning {
            continuation.yield(.stop)
            return
        }
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state.canSend, !text.isEmpty || !state.attachments.isEmpty else { return }
        continuation.yield(.send(text: text, attachments: state.attachments))
    }

    private func updateTextHeight() {
        guard textView.bounds.width > 20 else { return }
        let targetWidth = textView.bounds.width
        let size = textView.sizeThatFits(
            .init(width: targetWidth, height: .greatestFiniteMagnitude)
        )
        let height = min(max(44, size.height), maximumHeight)
        guard textHeightConstraint?.constant != height else { return }
        textHeightConstraint?.constant = height
        textView.isScrollEnabled = size.height > maximumHeight
        invalidateIntrinsicContentSize()
    }
}

extension AgentComposerView: UITextViewDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        state.text = textView.text
        placeholderLabel.isHidden = !textView.text.isEmpty
        configureSendButton()
        updateTextHeight()
    }
}

private final class AgentComposerTextView: UITextView {
    var importItemProviders: (([NSItemProvider]) -> Bool)?

    override func paste(_ sender: Any?) {
        let providers = UIPasteboard.general.itemProviders.filter { provider in
            provider.registeredTypeIdentifiers.contains { identifier in
                guard let type = UTType(identifier) else { return false }
                return !type.conforms(to: .text)
                    && !type.conforms(to: .url)
                    && (type.conforms(to: .content) || type.conforms(to: .data))
            }
        }
        if !providers.isEmpty, importItemProviders?(providers) == true { return }
        super.paste(sender)
    }
}

@MainActor
private final class AgentComposerAttachmentChip: UIView {
    var onRemove: (() -> Void)?
    var onRetry: (() -> Void)?

    init(attachment: AgentAttachment, status: AgentComposerAttachmentStatus) {
        super.init(frame: .zero)
        backgroundColor = .tertiarySystemFill
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        accessibilityIdentifier = "AgentComposerAttachment.\(attachment.id.rawValue)"

        let icon = UIImageView(image: UIImage(systemName: Self.iconName(for: attachment)))
        icon.tintColor = .secondaryLabel
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let title = UILabel()
        title.text = attachment.name
        title.font = .preferredFont(forTextStyle: .caption1)
        title.adjustsFontForContentSizeCategory = true
        title.lineBreakMode = .byTruncatingMiddle
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let statusView: UIView
        switch status {
        case .ready:
            statusView = UIView()
            statusView.isHidden = true
        case .uploading(let progress):
            if let progress {
                let indicator = UIProgressView(progressViewStyle: .default)
                indicator.progress = Float(min(1, max(0, progress)))
                indicator.accessibilityLabel = AgentStrings.uploading
                indicator.widthAnchor.constraint(equalToConstant: 38).isActive = true
                statusView = indicator
            } else {
                let indicator = UIActivityIndicatorView(style: .medium)
                indicator.accessibilityLabel = AgentStrings.uploading
                indicator.startAnimating()
                statusView = indicator
            }
        case .failed(let message):
            let retry = UIButton(type: .system)
            retry.setImage(
                UIImage(systemName: "exclamationmark.arrow.triangle.2.circlepath"), for: .normal)
            retry.accessibilityLabel = AgentStrings.retry
            retry.accessibilityValue = message
            retry.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
            statusView = retry
        }

        let remove = UIButton(type: .system)
        remove.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        remove.tintColor = .tertiaryLabel
        remove.accessibilityLabel = AgentStrings.removeAttachment
        remove.addAction(UIAction { [weak self] _ in self?.onRemove?() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [icon, title, statusView, remove])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(lessThanOrEqualToConstant: 260),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            remove.widthAnchor.constraint(greaterThanOrEqualToConstant: 30),
            remove.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private static func iconName(for attachment: AgentAttachment) -> String {
        guard let mediaType = attachment.mediaType,
            let type = UTType(mimeType: mediaType)
        else { return "doc" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .movie) { return "film" }
        return "doc"
    }
}
