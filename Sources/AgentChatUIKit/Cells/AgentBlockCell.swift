import AgentChatCore
import AgentChatMarkdown
import UIKit

@MainActor
private final class AgentBlockContentView: UIView {
    var didChangeHeight: (() -> Void)?

    private let rootStack = UIStackView()
    private var asynchronousTask: Task<Void, Never>?
    private var representedBlockID: AgentBlockID?
    private var representedRevision: Int64?

    override init(frame: CGRect) {
        super.init(frame: frame)
        rootStack.axis = .vertical
        rootStack.spacing = 8
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func reset() {
        asynchronousTask?.cancel()
        asynchronousTask = nil
        representedBlockID = nil
        representedRevision = nil
        didChangeHeight = nil
        removeArrangedSubviews()
        accessibilityLabel = nil
        accessibilityValue = nil
        accessibilityTraits = []
    }

    func configure(
        context: AgentBlockRenderContext,
        parser: AgentMarkdownParser,
        cache: AgentMarkdownDocumentCache
    ) {
        asynchronousTask?.cancel()
        removeArrangedSubviews()
        representedBlockID = context.block.id
        representedRevision = context.block.revision
        backgroundColor = .clear

        let card = makeCard(context: context)
        rootStack.addArrangedSubview(card)
        accessibilityLabel = accessibilityText(for: context.block)
        accessibilityValue = stateText(context.block.state)

        if case .markdown(let markdown) = context.block.content {
            guard let markdownView = card.findSubview(of: AgentMarkdownContentView.self) else {
                return
            }
            let blockID = context.block.id
            let revision = context.block.revision
            asynchronousTask = Task { [weak self, weak markdownView] in
                let key = AgentMarkdownCacheKey(
                    blockID: blockID,
                    revision: revision,
                    width: Int(context.availableWidth.rounded()),
                    contentSizeCategory: context.environment.contentSizeCategory,
                    themeVersion: context.theme.version
                )
                let document: AgentMarkdownRenderDocument
                if let cached = await cache.document(for: key) {
                    document = cached
                } else {
                    guard
                        let parsed = try? await parser.parseStreaming(
                            markdown.markdown,
                            isFinal: markdown.isFinal
                        ),
                        !Task.isCancelled
                    else { return }
                    document = parsed
                    await cache.insert(parsed, for: key)
                }
                guard let self,
                    self.representedBlockID == blockID,
                    self.representedRevision == revision
                else { return }
                markdownView?.apply(document)
                // The parsed document can replace a short raw placeholder with a much taller
                // table, list, or code block without changing the model revision. Explicitly
                // invalidate the self-sizing cell so the collection view resolves the final
                // height in the same layout-follow cycle.
                self.invalidateIntrinsicContentSize()
                self.didChangeHeight?()
            }
            return
        }

        startImageLoadIfNeeded(in: card, context: context)
    }

    func waitForPendingRendering() async {
        await asynchronousTask?.value
    }

    private func startImageLoadIfNeeded(
        in card: UIView,
        context: AgentBlockRenderContext
    ) {
        guard case .image(let value) = context.block.content,
            isCompactEventExpanded(context: context),
            let preview = card.findSubview(of: AgentInlineImagePreviewView.self)
        else { return }

        preview.onTap = {
            context.actionSink.send(
                .previewImage(
                    reference: value.reference,
                    alternativeText: value.alternativeText
                )
            )
        }
        guard let provider = context.imageProvider else {
            preview.showMessage(AgentStrings.imageProvidedByHost)
            return
        }

        preview.showLoading()
        let blockID = context.block.id
        let revision = context.block.revision
        let targetSize = preview.targetSize
        let scale = UIScreen.main.scale
        asynchronousTask = Task { [weak self, weak preview] in
            do {
                let image = try await provider.image(
                    for: value.reference,
                    targetSize: targetSize,
                    scale: scale
                )
                try Task.checkCancellation()
                guard let self,
                    self.representedBlockID == blockID,
                    self.representedRevision == revision
                else { return }
                preview?.show(image: image, alternativeText: value.alternativeText)
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                    self.representedBlockID == blockID,
                    self.representedRevision == revision
                else { return }
                preview?.showMessage(AgentStrings.imageUnavailable)
            }
        }
    }

    private func makeCard(context: AgentBlockRenderContext) -> UIView {
        if isCompactEvent(context.block.content) {
            return makeCompactEvent(context: context)
        }

        let container = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let isUser: Bool
        if case .userText = context.block.content { isUser = true } else { isUser = false }
        let isTransparentMarkdown: Bool
        if case .markdown = context.block.content {
            isTransparentMarkdown = true
        } else {
            isTransparentMarkdown = false
        }
        container.backgroundColor =
            isUser
            ? context.theme.colors.userBackground
            : background(for: context.block, theme: context.theme)
        container.layer.cornerRadius = isUser ? context.theme.metrics.cornerRadius : 10

        let horizontalInset: CGFloat = isUser ? 12 : (isTransparentMarkdown ? 0 : 10)
        let verticalInset: CGFloat = isUser ? 12 : 10
        let leading = stack.leadingAnchor.constraint(
            equalTo: container.leadingAnchor, constant: horizontalInset)
        let trailing = stack.trailingAnchor.constraint(
            equalTo: container.trailingAnchor, constant: -horizontalInset)
        NSLayoutConstraint.activate([
            leading, trailing,
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: verticalInset),
            stack.bottomAnchor.constraint(
                equalTo: container.bottomAnchor, constant: -verticalInset),
        ])

        if isUser {
            let wrapper = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(container)
            NSLayoutConstraint.activate([
                container.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                container.topAnchor.constraint(equalTo: wrapper.topAnchor),
                container.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                container.leadingAnchor.constraint(greaterThanOrEqualTo: wrapper.leadingAnchor),
                container.widthAnchor.constraint(
                    lessThanOrEqualTo: wrapper.widthAnchor, multiplier: 0.78),
            ])
            populate(stack, context: context)
            return wrapper
        }

        populate(stack, context: context)
        return container
    }

    private func makeCompactEvent(context: AgentBlockRenderContext) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 0
        container.accessibilityIdentifier = "AgentActivityEvent"
        let usesCapsulePresentation = context.environment.toolPresentationStyle == .capsule
        let isCapsule = usesCapsulePresentation && !isReasoningActivity(context.block)
        if isCapsule {
            container.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.72)
            container.layer.cornerRadius = 14
            container.layer.cornerCurve = .continuous
            container.layer.borderWidth = 1 / UIScreen.main.scale
            container.layer.borderColor = UIColor.separator.withAlphaComponent(0.32).cgColor
            container.clipsToBounds = true
        }

        let expanded = isCompactEventExpanded(context: context)
        let details = compactEventDetails(context: context)
        let hasDetails = !details.arrangedSubviews.isEmpty
        let title = compactEventTitle(for: context.block)
        let retryActivation: (@MainActor () -> Void)?
        if context.environment.canRetry, isRetryableFailure(context.block.state) {
            retryActivation = { context.actionSink.send(.retry(context.block.id)) }
        } else {
            retryActivation = nil
        }
        let header = AgentCompactEventHeaderControl(
            icon: eventIcon(for: context.block),
            iconTint: eventTint(for: context.block, theme: context.theme),
            title: title,
            subtitle: usesCapsulePresentation
                ? compactEventSubtitle(for: context.block)
                : nil,
            titleColor: isCapsule
                ? context.theme.colors.primaryText
                : context.theme.colors.secondaryText,
            subtitleColor: context.theme.colors.secondaryText,
            textStyle: context.theme.typography.body,
            state: context.block.state,
            accentColor: context.theme.colors.accent,
            destructiveColor: context.theme.colors.destructive,
            style: isCapsule ? .capsule : .inline,
            isExpanded: expanded,
            hasDetails: hasDetails,
            retryActivation: retryActivation
        ) {
            context.actionSink.send(.toggleExpanded(context.block.id))
        }
        container.addArrangedSubview(header)

        if hasDetails {
            details.isLayoutMarginsRelativeArrangement = true
            details.layoutMargins =
                isCapsule
                ? .init(top: 12, left: 14, bottom: 14, right: 14)
                : .init(top: 6, left: 28, bottom: 2, right: 0)
            details.accessibilityIdentifier = "AgentActivityEventDetails"
            if isCapsule {
                details.backgroundColor = UIColor.tertiarySystemBackground
                let detailContainer = UIStackView()
                detailContainer.axis = .vertical
                detailContainer.spacing = 0
                detailContainer.isHidden = !expanded
                let separator = UIView()
                separator.backgroundColor = UIColor.separator.withAlphaComponent(0.32)
                separator.translatesAutoresizingMaskIntoConstraints = false
                separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
                    .isActive = true
                detailContainer.addArrangedSubview(separator)
                detailContainer.addArrangedSubview(details)
                container.addArrangedSubview(detailContainer)
            } else {
                details.isHidden = !expanded
                container.addArrangedSubview(details)
            }
        }
        return container
    }

    private func compactEventDetails(context: AgentBlockRenderContext) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6

        switch context.block.content {
        case .activity(let value):
            if let detail = value.detail {
                stack.addArrangedSubview(detailLabel(detail, context: context))
            }

        case .tool(let value):
            if let summary = value.summary {
                stack.addArrangedSubview(detailLabel(summary, context: context))
            }
            addJSON(value.input, title: AgentStrings.input, to: stack, context: context)
            addJSON(value.output, title: AgentStrings.output, to: stack, context: context)

        case .command(let value):
            stack.addArrangedSubview(detailSectionLabel(AgentStrings.command, context: context))
            stack.addArrangedSubview(codeTextView(value.command, context: context))
            if let directory = value.workingDirectory {
                stack.addArrangedSubview(detailLabel(directory, context: context))
            }
            if !value.output.text.isEmpty {
                stack.addArrangedSubview(detailSectionLabel(AgentStrings.output, context: context))
                stack.addArrangedSubview(codeTextView(value.output.text, context: context))
            }
            if value.output.wasTruncated {
                stack.addArrangedSubview(
                    detailLabel(AgentStrings.outputTruncated, context: context))
            }
            var status = stateText(context.block.state)
            if let exitCode = value.exitCode { status += " · exit \(exitCode)" }
            if let duration = value.duration {
                status += " · \(duration.formatted(.number.precision(.fractionLength(1))))s"
            }
            stack.addArrangedSubview(detailLabel(status, context: context))

        case .fileSearch(let value):
            if let root = value.root {
                stack.addArrangedSubview(detailLabel(root, context: context))
            }
            for match in value.matches.prefix(8) {
                let button = actionButton(title: match.path, context: context) {
                    context.actionSink.send(.openFile(.localIdentifier(match.path)))
                }
                stack.addArrangedSubview(button)
            }

        case .fileOperation(let value):
            if let destination = value.destinationPath {
                stack.addArrangedSubview(detailLabel("→ \(destination)", context: context))
            }
            if let summary = value.summary {
                stack.addArrangedSubview(detailLabel(summary, context: context))
            }

        case .image(let value):
            let width = min(max(context.availableWidth * 0.5, 160), 280)
            let preview = AgentInlineImagePreviewView(
                size: .init(width: width, height: width * 0.75),
                tintColor: context.theme.colors.secondaryText,
                alternativeText: value.alternativeText
            )
            let row = UIStackView(arrangedSubviews: [preview, UIView()])
            row.axis = .horizontal
            row.alignment = .top
            row.spacing = 0
            stack.addArrangedSubview(row)

        default:
            break
        }

        if let expandedDetail = metadataString(
            AgentBlockMetadataKey.expandedDetail,
            in: context.block
        ),
            !stack.arrangedSubviews.contains(where: { view in
                (view as? UILabel)?.text == expandedDetail
            })
        {
            stack.addArrangedSubview(detailLabel(expandedDetail, context: context))
        }

        if shouldShowCompactEventState(context.block.state),
            !isCommand(context.block.content)
        {
            stack.addArrangedSubview(detailLabel(stateText(context.block.state), context: context))
        }
        return stack
    }

    private func isCompactEvent(_ content: AgentBlockContent) -> Bool {
        switch content {
        case .activity, .tool, .command, .fileSearch, .fileOperation, .image:
            true
        default:
            false
        }
    }

    private func isCompactEventExpanded(context: AgentBlockRenderContext) -> Bool {
        context.environment.expandedBlockIDs.contains(context.block.id)
    }

    private func compactEventTitle(for block: AgentBlock) -> String {
        if let title = metadataString(AgentBlockMetadataKey.displayTitle, in: block) {
            return title
        }
        switch block.content {
        case .activity(let value):
            return isReasoningActivity(block) ? reasoningTitle(for: block.state) : value.title
        case .tool(let value):
            return value.title
        case .command(let value):
            return "\(commandVerb(for: block.state)) \(value.command)"
        case .fileSearch(let value):
            return "\(AgentStrings.fileSearch) \(value.query)"
        case .fileOperation(let value):
            return "\(fileOperationVerb(value.operation)) \(value.path)"
        case .image(let value):
            return value.alternativeText
        default:
            return accessibilityText(for: block)
        }
    }

    private func compactEventSubtitle(for block: AgentBlock) -> String? {
        if let subtitle = metadataString(AgentBlockMetadataKey.displaySubtitle, in: block) {
            return subtitle
        }
        switch block.content {
        case .activity(let value):
            return value.detail
        case .tool(let value):
            return value.summary
        case .command(let value):
            var components: [String] = []
            if let executable = value.command.split(whereSeparator: { $0.isWhitespace }).first {
                components.append(String(executable))
            }
            if let duration = value.duration {
                components.append(
                    "\(duration.formatted(.number.precision(.fractionLength(1))))s"
                )
            }
            return components.isEmpty ? nil : components.joined(separator: " · ")
        case .fileSearch(let value):
            return value.totalCount.map { "\($0) \(AgentStrings.results)" } ?? value.root
        case .fileOperation(let value):
            return value.summary
        case .image:
            return AgentStrings.image
        default:
            return nil
        }
    }

    private func isReasoningActivity(_ block: AgentBlock) -> Bool {
        metadataString(AgentBlockMetadataKey.activityKind, in: block) == "reasoning"
    }

    private func reasoningTitle(for state: AgentBlockState) -> String {
        switch state {
        case .queued, .streaming, .running, .waitingForApproval:
            AgentStrings.thinking
        case .succeeded:
            AgentStrings.thought
        case .failed:
            AgentStrings.thinkingFailed
        case .cancelled:
            AgentStrings.thinkingCancelled
        }
    }

    private func metadataString(_ key: String, in block: AgentBlock) -> String? {
        guard case .string(let value) = block.metadata[key], !value.isEmpty else { return nil }
        return value
    }

    private func commandVerb(for state: AgentBlockState) -> String {
        switch state {
        case .queued:
            AgentStrings.queued
        case .streaming, .running, .waitingForApproval:
            AgentStrings.running
        case .succeeded:
            AgentStrings.ran
        case .failed:
            AgentStrings.failed
        case .cancelled:
            AgentStrings.cancelled
        }
    }

    private func fileOperationVerb(_ operation: AgentFileOperation) -> String {
        switch operation {
        case .read: AgentStrings.read
        case .create: AgentStrings.created
        case .update: AgentStrings.edited
        case .delete: AgentStrings.deleted
        case .move: AgentStrings.moved
        }
    }

    private func eventIcon(for block: AgentBlock) -> UIImage? {
        let symbol: String
        switch block.content {
        case .activity(let value):
            let title = value.title.lowercased()
            if isReasoningActivity(block) {
                symbol = "brain.head.profile"
            } else if title.contains("command") || title.contains("命令") {
                symbol = "apple.terminal"
            } else if title.contains("skill") || title.contains("技能") {
                symbol = "wrench"
            } else {
                symbol = "bolt.horizontal"
            }
        case .tool(let value):
            let name = value.toolName.lowercased()
            if name.contains("simulator") || name.contains("iphone") {
                symbol = "iphone"
            } else if name.contains("browser") {
                symbol = "globe"
            } else if name.contains("skill") {
                symbol = "wrench"
            } else {
                symbol = "wrench.and.screwdriver"
            }
        case .command:
            symbol = "apple.terminal"
        case .fileSearch:
            symbol = "doc.text.magnifyingglass"
        case .fileOperation(let value):
            switch value.operation {
            case .read: symbol = "doc.text"
            case .create: symbol = "doc.badge.plus"
            case .update: symbol = "pencil"
            case .delete: symbol = "trash"
            case .move: symbol = "arrow.right.doc.on.clipboard"
            }
        case .image:
            symbol = "photo.on.rectangle"
        default:
            symbol = "circle"
        }
        if let image = UIImage(systemName: symbol) { return image }
        if case .command = block.content, let fallback = UIImage(systemName: "terminal") {
            return fallback
        }
        return UIImage(systemName: "chevron.left.forwardslash.chevron.right")
    }

    private func eventTint(for block: AgentBlock, theme: AgentChatTheme) -> UIColor {
        if case .failed = block.state { return theme.colors.destructive }
        if case .running = block.state { return theme.colors.accent }
        if case .streaming = block.state { return theme.colors.accent }
        if case .tool(let value) = block.content {
            let name = value.toolName.lowercased()
            if name.contains("simulator") || name.contains("iphone") {
                return theme.colors.accent
            }
        }
        return theme.colors.secondaryText
    }

    private func shouldShowCompactEventState(_ state: AgentBlockState) -> Bool {
        if case .succeeded = state { return false }
        return true
    }

    private func isRetryableFailure(_ state: AgentBlockState) -> Bool {
        guard case .failed(let failure) = state else { return false }
        return failure.isRetryable
    }

    private func isCommand(_ content: AgentBlockContent) -> Bool {
        if case .command = content { return true }
        return false
    }

    private func populate(_ stack: UIStackView, context: AgentBlockRenderContext) {
        switch context.block.content {
        case .userText(let value):
            stack.addArrangedSubview(textView(value.text, context: context))
            for attachment in value.attachments {
                stack.addArrangedSubview(detailLabel("📎 \(attachment.name)", context: context))
            }

        case .markdown(let value):
            stack.addArrangedSubview(
                AgentMarkdownContentView(source: value.markdown, context: context)
            )

        case .activity(let value):
            stack.addArrangedSubview(titleLabel(value.title, context: context))
            if let detail = value.detail {
                stack.addArrangedSubview(detailLabel(detail, context: context))
            }
            stack.addArrangedSubview(detailLabel(stateText(context.block.state), context: context))

        case .tool(let value):
            stack.addArrangedSubview(titleLabel(value.title, context: context))
            if let summary = value.summary {
                stack.addArrangedSubview(detailLabel(summary, context: context))
            }
            addJSON(value.input, title: AgentStrings.input, to: stack, context: context)
            addJSON(value.output, title: AgentStrings.output, to: stack, context: context)
            stack.addArrangedSubview(detailLabel(stateText(context.block.state), context: context))

        case .command(let value):
            stack.addArrangedSubview(titleLabel(AgentStrings.command, context: context))
            stack.addArrangedSubview(codeTextView(value.command, context: context))
            if let directory = value.workingDirectory {
                stack.addArrangedSubview(detailLabel(directory, context: context))
            }
            if !value.output.text.isEmpty {
                stack.addArrangedSubview(codeTextView(value.output.text, context: context))
            }
            if value.output.wasTruncated {
                stack.addArrangedSubview(
                    detailLabel(AgentStrings.outputTruncated, context: context))
            }
            var status = stateText(context.block.state)
            if let exitCode = value.exitCode { status += " · exit \(exitCode)" }
            stack.addArrangedSubview(detailLabel(status, context: context))

        case .fileSearch(let value):
            stack.addArrangedSubview(
                titleLabel("\(AgentStrings.fileSearch): \(value.query)", context: context))
            if let root = value.root {
                stack.addArrangedSubview(detailLabel(root, context: context))
            }
            for match in value.matches.prefix(8) {
                let button = actionButton(title: match.path, context: context) {
                    context.actionSink.send(.openFile(.localIdentifier(match.path)))
                }
                stack.addArrangedSubview(button)
            }

        case .fileOperation(let value):
            stack.addArrangedSubview(
                titleLabel(
                    "\(value.operation.rawValue.capitalized): \(value.path)", context: context)
            )
            if let destination = value.destinationPath {
                stack.addArrangedSubview(detailLabel("→ \(destination)", context: context))
            }
            if let summary = value.summary {
                stack.addArrangedSubview(detailLabel(summary, context: context))
            }

        case .diff(let value):
            stack.addArrangedSubview(
                titleLabel(value.title ?? AgentStrings.changes, context: context))
            let additions = value.files.reduce(0) { $0 + $1.additions }
            let deletions = value.files.reduce(0) { $0 + $1.deletions }
            stack.addArrangedSubview(
                detailLabel(
                    "\(value.files.count) files · +\(additions) −\(deletions)", context: context)
            )
            if let raw = value.rawUnifiedDiff {
                stack.addArrangedSubview(codeTextView(String(raw.prefix(8_000)), context: context))
            }

        case .approval(let value):
            stack.addArrangedSubview(titleLabel(value.title, context: context))
            if let message = value.message {
                stack.addArrangedSubview(textView(message, context: context))
            }
            stack.addArrangedSubview(
                detailLabel("\(AgentStrings.risk): \(value.risk.rawValue)", context: context)
            )
            if let resolution = value.resolution {
                stack.addArrangedSubview(detailLabel("✓ \(resolution.choiceID)", context: context))
            } else {
                let buttons = UIStackView()
                buttons.axis = .vertical
                buttons.spacing = 6
                for choice in value.choices {
                    let response = AgentApprovalResponse(
                        conversationID: context.conversationID,
                        approvalID: value.approvalID,
                        choiceID: choice.id
                    )
                    let button = actionButton(title: choice.title, context: context) {
                        [weak buttons] in
                        for case let actionButton as UIButton in buttons?.arrangedSubviews ?? [] {
                            actionButton.isEnabled = false
                        }
                        if choice.role == .reject {
                            context.actionSink.send(.reject(response))
                        } else {
                            context.actionSink.send(.approve(response))
                        }
                    }
                    if choice.role == .reject {
                        button.tintColor = context.theme.colors.destructive
                    }
                    button.isEnabled = !context.environment.resolvingApprovalIDs.contains(
                        value.approvalID
                    )
                    buttons.addArrangedSubview(button)
                }
                stack.addArrangedSubview(buttons)
            }

        case .artifact(let value):
            stack.addArrangedSubview(titleLabel(value.title, context: context))
            if let summary = value.summary {
                stack.addArrangedSubview(detailLabel(summary, context: context))
            }
            stack.addArrangedSubview(
                actionButton(title: AgentStrings.open, context: context) {
                    context.actionSink.send(.openArtifact(value.id))
                }
            )

        case .image(let value):
            stack.addArrangedSubview(titleLabel(value.alternativeText, context: context))
            stack.addArrangedSubview(
                detailLabel(AgentStrings.imageProvidedByHost, context: context))

        case .error(let value):
            stack.addArrangedSubview(titleLabel(value.failure.message, context: context))
            if value.failure.isRetryable {
                stack.addArrangedSubview(
                    actionButton(title: value.retryTitle ?? AgentStrings.retry, context: context) {
                        context.actionSink.send(.retry(context.block.id))
                    }
                )
            }

        case .custom(let value):
            stack.addArrangedSubview(titleLabel(value.fallbackTitle, context: context))
            if let summary = value.fallbackSummary {
                stack.addArrangedSubview(detailLabel(summary, context: context))
            }
            stack.addArrangedSubview(detailLabel(value.kind, context: context))
            addJSON(value.payload, title: AgentStrings.payload, to: stack, context: context)
            stack.addArrangedSubview(
                actionButton(title: AgentStrings.copyRawPayload, context: context) {
                    context.actionSink.send(.copy(context.block.id))
                }
            )
        }
    }

    private func titleLabel(_ text: String, context: AgentBlockRenderContext) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: context.theme.typography.headline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = context.theme.colors.primaryText
        label.numberOfLines = 0
        label.text = text
        return label
    }

    private func detailLabel(_ text: String, context: AgentBlockRenderContext) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: context.theme.typography.detail)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = context.theme.colors.secondaryText
        label.numberOfLines = 0
        label.text = text
        return label
    }

    private func detailSectionLabel(
        _ text: String,
        context: AgentBlockRenderContext
    ) -> UILabel {
        let label = detailLabel(text, context: context)
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 12, weight: .semibold)
        )
        return label
    }

    private func textView(_ text: String, context: AgentBlockRenderContext) -> UITextView {
        let view = AgentSelectableTextView()
        view.font = .preferredFont(forTextStyle: context.theme.typography.body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = context.theme.colors.primaryText
        view.linkTextAttributes = [.foregroundColor: context.theme.colors.accent]
        view.text = text
        return view
    }

    private func codeTextView(_ text: String, context: AgentBlockRenderContext) -> UITextView {
        let view = textView(text, context: context)
        view.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .monospacedSystemFont(
                ofSize: context.theme.typography.codePointSize,
                weight: .regular
            )
        )
        view.backgroundColor = UIColor.tertiarySystemFill
        view.layer.cornerRadius = 8
        view.textContainerInset = .init(top: 8, left: 8, bottom: 8, right: 8)
        return view
    }

    private func actionButton(
        title: String,
        context: AgentBlockRenderContext,
        action: @escaping @MainActor () -> Void
    ) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.cornerStyle = .medium
        let button = UIButton(configuration: configuration)
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.accessibilityLabel = title
        return button
    }

    private func addJSON(
        _ value: JSONValue?,
        title: String,
        to stack: UIStackView,
        context: AgentBlockRenderContext
    ) {
        guard let value,
            let data = try? JSONEncoder.pretty.encode(value),
            let string = String(data: data, encoding: .utf8)
        else { return }
        stack.addArrangedSubview(detailLabel(title, context: context))
        stack.addArrangedSubview(codeTextView(string, context: context))
    }

    private func background(for block: AgentBlock, theme: AgentChatTheme) -> UIColor {
        switch block.content {
        case .markdown: .clear
        default: theme.colors.cardBackground
        }
    }

    private func stateText(_ state: AgentBlockState) -> String {
        switch state {
        case .queued: AgentStrings.queued
        case .streaming: AgentStrings.streaming
        case .running(let progress):
            progress.map { "\(AgentStrings.running) \(Int($0 * 100))%" }
                ?? AgentStrings.running
        case .waitingForApproval: AgentStrings.waitingForApproval
        case .succeeded: AgentStrings.succeeded
        case .failed(let failure): "\(AgentStrings.failed): \(failure.message)"
        case .cancelled: AgentStrings.cancelled
        }
    }

    private func accessibilityText(for block: AgentBlock) -> String {
        switch block.content {
        case .userText(let value): value.text
        case .markdown(let value): value.markdown
        case .activity(let value): value.title
        case .tool(let value): value.title
        case .command(let value): "\(AgentStrings.command), \(value.command)"
        case .fileSearch(let value): "\(AgentStrings.fileSearch), \(value.query)"
        case .fileOperation(let value): "\(value.operation.rawValue), \(value.path)"
        case .diff(let value): value.title ?? AgentStrings.changes
        case .approval(let value): "\(value.title), \(AgentStrings.risk) \(value.risk.rawValue)"
        case .artifact(let value): value.title
        case .image(let value): value.alternativeText
        case .error(let value): value.failure.message
        case .custom(let value): value.fallbackTitle
        }
    }

    private func removeArrangedSubviews() {
        for view in rootStack.arrangedSubviews {
            rootStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}

@MainActor
final class AgentBlockCell: UICollectionViewCell {
    static let reuseIdentifier = "AgentBlockCell"

    private let blockContentView = AgentBlockContentView()

    var didChangeHeight: (() -> Void)? {
        get { blockContentView.didChangeHeight }
        set { blockContentView.didChangeHeight = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        blockContentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(blockContentView)
        NSLayoutConstraint.activate([
            blockContentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            blockContentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            blockContentView.topAnchor.constraint(equalTo: contentView.topAnchor),
            blockContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        blockContentView.reset()
    }

    func configure(
        context: AgentBlockRenderContext,
        parser: AgentMarkdownParser,
        cache: AgentMarkdownDocumentCache
    ) {
        blockContentView.configure(context: context, parser: parser, cache: cache)
        accessibilityLabel = blockContentView.accessibilityLabel
        accessibilityValue = blockContentView.accessibilityValue
        accessibilityTraits = blockContentView.accessibilityTraits
    }

    func waitForPendingRendering() async {
        await blockContentView.waitForPendingRendering()
    }
}

@MainActor
final class AgentTableBlockCell: UITableViewCell {
    static let reuseIdentifier = "AgentTableBlockCell"

    private let blockContentView = AgentBlockContentView()
    private var widthConstraint: NSLayoutConstraint!
    private var maximumWidthConstraint: NSLayoutConstraint!
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!

    var didChangeHeight: (() -> Void)? {
        get { blockContentView.didChangeHeight }
        set { blockContentView.didChangeHeight = newValue }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        isAccessibilityElement = false
        contentView.isAccessibilityElement = false
        blockContentView.isAccessibilityElement = false
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        blockContentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(blockContentView)
        leadingConstraint = blockContentView.leadingAnchor.constraint(
            greaterThanOrEqualTo: contentView.leadingAnchor
        )
        trailingConstraint = blockContentView.trailingAnchor.constraint(
            lessThanOrEqualTo: contentView.trailingAnchor
        )
        widthConstraint = blockContentView.widthAnchor.constraint(
            equalTo: contentView.widthAnchor
        )
        widthConstraint.priority = .defaultHigh
        maximumWidthConstraint = blockContentView.widthAnchor.constraint(
            lessThanOrEqualToConstant: 900)
        NSLayoutConstraint.activate([
            blockContentView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            maximumWidthConstraint,
            leadingConstraint,
            trailingConstraint,
            widthConstraint,
            blockContentView.topAnchor.constraint(equalTo: contentView.topAnchor),
            blockContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        blockContentView.reset()
    }

    func configure(
        context: AgentBlockRenderContext,
        parser: AgentMarkdownParser,
        cache: AgentMarkdownDocumentCache
    ) {
        let sideInset = context.theme.metrics.pageInset
        leadingConstraint.constant = sideInset
        trailingConstraint.constant = -sideInset
        widthConstraint.constant = -sideInset * 2
        maximumWidthConstraint.constant = context.theme.metrics.maximumContentWidth
        blockContentView.configure(context: context, parser: parser, cache: cache)
        accessibilityLabel = nil
        accessibilityValue = nil
        accessibilityTraits = []
    }

    func waitForPendingRendering() async {
        await blockContentView.waitForPendingRendering()
    }
}

@MainActor
final class AgentCompactEventHeaderControl: UIControl {
    private let activation: @MainActor () -> Void
    private let retryActivation: (@MainActor () -> Void)?

    init(
        icon: UIImage?,
        iconTint: UIColor,
        title: String,
        subtitle: String?,
        titleColor: UIColor,
        subtitleColor: UIColor,
        textStyle: UIFont.TextStyle,
        state: AgentBlockState,
        accentColor: UIColor,
        destructiveColor: UIColor,
        style: AgentToolPresentationStyle,
        isExpanded: Bool,
        hasDetails: Bool,
        retryActivation: (@MainActor () -> Void)? = nil,
        activation: @escaping @MainActor () -> Void
    ) {
        self.activation = activation
        self.retryActivation = retryActivation
        super.init(frame: .zero)

        accessibilityIdentifier = "AgentActivityEventHeader"
        accessibilityLabel = [title, subtitle, Self.accessibilityState(for: state)]
            .compactMap { $0 }
            .joined(separator: ", ")
        accessibilityValue =
            hasDetails
            ? (isExpanded ? AgentStrings.collapse : AgentStrings.expand)
            : nil
        accessibilityTraits = hasDetails ? [.button] : [.staticText]
        isAccessibilityElement = true
        isEnabled = hasDetails
        let isCapsule = style == .capsule

        let iconView = UIImageView(image: icon)
        iconView.preferredSymbolConfiguration = .init(textStyle: .body, scale: .medium)
        iconView.tintColor = iconTint
        iconView.contentMode = .scaleAspectFit
        iconView.accessibilityIdentifier = "AgentActivityEventIcon"
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
        ])

        let titleLabel = UILabel()
        titleLabel.font =
            isCapsule
            ? UIFontMetrics(forTextStyle: textStyle).scaledFont(
                for: .systemFont(ofSize: 16, weight: .semibold)
            )
            : .preferredFont(forTextStyle: textStyle)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = titleColor
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.text = title
        titleLabel.accessibilityIdentifier = "AgentActivityEventTitle"

        let subtitleLabel = UILabel()
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = subtitleColor
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        subtitleLabel.accessibilityIdentifier = "AgentActivityEventSubtitle"

        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.alignment = .fill
        labels.spacing = 2
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let disclosure = UIImageView(
            image: UIImage(systemName: isExpanded ? "chevron.up" : "chevron.down")
        )
        disclosure.preferredSymbolConfiguration = .init(textStyle: .caption1, scale: .small)
        disclosure.tintColor = titleColor
        disclosure.contentMode = .scaleAspectFit
        disclosure.accessibilityIdentifier = "AgentActivityEventDisclosure"
        disclosure.isHidden = !hasDetails
        disclosure.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            disclosure.widthAnchor.constraint(equalToConstant: 18),
            disclosure.heightAnchor.constraint(equalToConstant: 18),
        ])

        let trailing = makeTrailingView(
            for: state,
            hasDetails: hasDetails,
            disclosure: disclosure,
            accentColor: accentColor,
            destructiveColor: destructiveColor,
            isCapsule: isCapsule
        )
        let stack = UIStackView(arrangedSubviews: [iconView, labels, trailing])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = isCapsule ? 10 : 8
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        var constraints = [
            heightAnchor.constraint(greaterThanOrEqualToConstant: isCapsule ? 56 : 36),
            stack.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: isCapsule ? 14 : 0),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: isCapsule ? 7 : 0),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: isCapsule ? -7 : 0),
        ]
        if isCapsule, retryActivation != nil {
            let retryButton = UIButton(type: .system)
            var configuration = UIButton.Configuration.plain()
            configuration.title = AgentStrings.retry
            configuration.baseForegroundColor = destructiveColor
            configuration.contentInsets = .init(top: 8, leading: 8, bottom: 8, trailing: 8)
            retryButton.configuration = configuration
            retryButton.addAction(
                UIAction { [weak self] _ in self?.retryActivation?() },
                for: .touchUpInside
            )
            retryButton.accessibilityIdentifier = "AgentActivityEventRetry"
            retryButton.translatesAutoresizingMaskIntoConstraints = false
            addSubview(retryButton)
            constraints += [
                stack.trailingAnchor.constraint(equalTo: retryButton.leadingAnchor),
                retryButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                retryButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            ]
            accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: AgentStrings.retry) { [weak self] _ in
                    guard let self, let retryActivation = self.retryActivation else { return false }
                    retryActivation()
                    return true
                }
            ]
        } else {
            constraints.append(
                stack.trailingAnchor.constraint(
                    equalTo: trailingAnchor, constant: isCapsule ? -12 : 0)
            )
        }
        NSLayoutConstraint.activate(constraints)

        addAction(UIAction { [weak self] _ in self?.activation() }, for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func makeTrailingView(
        for state: AgentBlockState,
        hasDetails: Bool,
        disclosure: UIImageView,
        accentColor: UIColor,
        destructiveColor: UIColor,
        isCapsule: Bool
    ) -> UIView {
        guard isCapsule else { return disclosure }
        let views: [UIView]
        switch state {
        case .queued:
            views = [stateIcon("clock", color: .tertiaryLabel), disclosure]
        case .streaming, .running:
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.color = accentColor
            indicator.startAnimating()
            indicator.accessibilityIdentifier = "AgentActivityEventProgress"
            views = [indicator, disclosure]
        case .waitingForApproval:
            views = [stateIcon("exclamationmark.shield", color: accentColor), disclosure]
        case .succeeded:
            views = [stateIcon("checkmark.circle.fill", color: .systemGreen), disclosure]
        case .failed:
            views = [stateIcon("exclamationmark.circle", color: destructiveColor), disclosure]
        case .cancelled:
            views = [stateIcon("xmark.circle", color: .tertiaryLabel), disclosure]
        }
        disclosure.isHidden = !hasDetails
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.setContentHuggingPriority(.required, for: .horizontal)
        return stack
    }

    private func stateIcon(_ name: String, color: UIColor) -> UIImageView {
        let view = UIImageView(image: UIImage(systemName: name))
        view.preferredSymbolConfiguration = .init(pointSize: 18, weight: .semibold)
        view.tintColor = color
        view.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 22),
            view.heightAnchor.constraint(equalToConstant: 22),
        ])
        return view
    }

    private static func accessibilityState(for state: AgentBlockState) -> String {
        switch state {
        case .queued: AgentStrings.queued
        case .streaming: AgentStrings.streaming
        case .running: AgentStrings.running
        case .waitingForApproval: AgentStrings.waitingForApproval
        case .succeeded: AgentStrings.succeeded
        case .failed(let failure): "\(AgentStrings.failed): \(failure.message)"
        case .cancelled: AgentStrings.cancelled
        }
    }

    override var isHighlighted: Bool {
        didSet {
            guard isEnabled else { return }
            alpha = isHighlighted ? 0.55 : 1
        }
    }
}

@MainActor
final class AgentMarkdownContentView: UIView {
    private let stack = UIStackView()
    private let bodyTextStyle: UIFont.TextStyle
    private let bodyColor: UIColor
    private let secondaryColor: UIColor
    private let accentColor: UIColor
    private let codePointSize: CGFloat
    private let availableWidth: CGFloat

    init(source: String, context: AgentBlockRenderContext) {
        self.bodyTextStyle = context.theme.typography.body
        self.bodyColor = context.theme.colors.primaryText
        self.secondaryColor = context.theme.colors.secondaryText
        self.accentColor = context.theme.colors.accent
        self.codePointSize = context.theme.typography.codePointSize
        self.availableWidth = max(1, context.availableWidth)
        super.init(frame: .zero)

        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        stack.addArrangedSubview(makeTextView(source))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func apply(_ document: AgentMarkdownRenderDocument) {
        removeRenderedViews()
        for block in document.blocks {
            stack.addArrangedSubview(makeView(for: block))
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func makeView(for block: AgentMarkdownRenderBlock) -> UIView {
        switch block {
        case .heading(let level, let content):
            let label = UILabel()
            label.font = .preferredFont(forTextStyle: headingTextStyle(level: level))
            label.adjustsFontForContentSizeCategory = true
            label.textColor = bodyColor
            label.numberOfLines = 0
            label.text = AgentMarkdownPlainTextRenderer.inline(content)
            return label

        case .codeBlock(let language, let code):
            let view = makeTextView([language, code].compactMap { $0 }.joined(separator: "\n"))
            view.font = UIFontMetrics(forTextStyle: .body).scaledFont(
                for: .monospacedSystemFont(ofSize: codePointSize, weight: .regular)
            )
            view.backgroundColor = .tertiarySystemFill
            view.layer.cornerRadius = 8
            view.textContainerInset = .init(top: 8, left: 8, bottom: 8, right: 8)
            return view

        case .thematicBreak:
            let separator = UIView()
            separator.backgroundColor = .separator
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive =
                true
            return separator

        case .table(let table):
            return AgentMarkdownTableView(
                table: table,
                availableWidth: availableWidth,
                bodyTextStyle: bodyTextStyle,
                bodyColor: bodyColor,
                secondaryColor: secondaryColor
            )

        default:
            return makeTextView(AgentMarkdownPlainTextRenderer.render(block))
        }
    }

    private func makeTextView(_ text: String) -> AgentSelectableTextView {
        let view = AgentSelectableTextView()
        view.font = .preferredFont(forTextStyle: bodyTextStyle)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = bodyColor
        view.linkTextAttributes = [.foregroundColor: accentColor]
        view.text = text
        return view
    }

    private func headingTextStyle(level: Int) -> UIFont.TextStyle {
        switch level {
        case 1: .title2
        case 2: .title3
        default: .headline
        }
    }

    private func removeRenderedViews() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}

@MainActor
final class AgentMarkdownTableView: UIScrollView {
    private let renderedHeight: CGFloat

    init(
        table: AgentMarkdownTable,
        availableWidth: CGFloat,
        bodyTextStyle: UIFont.TextStyle,
        bodyColor: UIColor,
        secondaryColor: UIColor
    ) {
        let rows = [table.header] + table.rows
        let columnCount = max(1, rows.map(\.count).max() ?? 0)
        let columnWidth = max(120, floor(availableWidth / CGFloat(columnCount)))
        let font = UIFont.preferredFont(forTextStyle: bodyTextStyle)
        let headerFont = UIFont.preferredFont(forTextStyle: .headline)
        let rowHeights = rows.enumerated().map { index, row in
            Self.rowHeight(
                row: row,
                columnCount: columnCount,
                columnWidth: columnWidth,
                font: index == 0 ? headerFont : font
            )
        }
        self.renderedHeight = max(44, rowHeights.reduce(0, +))
        super.init(frame: .zero)

        accessibilityIdentifier = "AgentMarkdownTable"
        showsHorizontalScrollIndicator = columnWidth * CGFloat(columnCount) > availableWidth
        alwaysBounceHorizontal = showsHorizontalScrollIndicator
        alwaysBounceVertical = false
        isDirectionalLockEnabled = true
        delaysContentTouches = false

        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 0
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            grid.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            grid.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            grid.widthAnchor.constraint(equalToConstant: columnWidth * CGFloat(columnCount)),
        ])

        let headerTitles = table.header.map(AgentMarkdownPlainTextRenderer.inline)
        for (rowIndex, row) in rows.enumerated() {
            let rowView = UIStackView()
            rowView.axis = .horizontal
            rowView.spacing = 0
            rowView.distribution = .fill
            rowView.heightAnchor.constraint(equalToConstant: rowHeights[rowIndex]).isActive = true

            for columnIndex in 0..<columnCount {
                let text =
                    columnIndex < row.count
                    ? AgentMarkdownPlainTextRenderer.inline(row[columnIndex])
                    : ""
                let cell = Self.makeCell(
                    text: text,
                    columnTitle: columnIndex < headerTitles.count
                        ? headerTitles[columnIndex] : "",
                    alignment: columnIndex < table.alignments.count
                        ? table.alignments[columnIndex] : .unspecified,
                    isHeader: rowIndex == 0,
                    width: columnWidth,
                    font: rowIndex == 0 ? headerFont : font,
                    bodyColor: bodyColor,
                    secondaryColor: secondaryColor
                )
                rowView.addArrangedSubview(cell)
            }
            grid.addArrangedSubview(rowView)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: CGSize {
        .init(width: UIView.noIntrinsicMetric, height: renderedHeight)
    }

    private static func rowHeight(
        row: [[AgentMarkdownInline]],
        columnCount: Int,
        columnWidth: CGFloat,
        font: UIFont
    ) -> CGFloat {
        let contentHeight =
            (0..<columnCount).map { index -> CGFloat in
                let text =
                    index < row.count
                    ? AgentMarkdownPlainTextRenderer.inline(row[index])
                    : ""
                let rect = (text as NSString).boundingRect(
                    with: .init(width: columnWidth - 24, height: .greatestFiniteMagnitude),
                    options: [.usesFontLeading, .usesLineFragmentOrigin],
                    attributes: [.font: font],
                    context: nil
                )
                return ceil(rect.height) + 20
            }.max() ?? 44
        return max(44, contentHeight)
    }

    private static func makeCell(
        text: String,
        columnTitle: String,
        alignment: AgentMarkdownTable.Alignment,
        isHeader: Bool,
        width: CGFloat,
        font: UIFont,
        bodyColor: UIColor,
        secondaryColor: UIColor
    ) -> UIView {
        let container = UIView()
        container.backgroundColor =
            isHeader
            ? UIColor.secondarySystemBackground
            : UIColor.systemBackground
        container.layer.borderWidth = 1 / UIScreen.main.scale
        container.layer.borderColor = UIColor.separator.cgColor
        container.widthAnchor.constraint(equalToConstant: width).isActive = true
        container.accessibilityIdentifier = "AgentMarkdownTableCell"
        container.isAccessibilityElement = true
        container.accessibilityLabel =
            columnTitle.isEmpty
            ? text : "\(columnTitle): \(text)"
        container.accessibilityTraits = isHeader ? [.header] : [.staticText]

        let label = UILabel()
        label.font = font
        label.adjustsFontForContentSizeCategory = true
        label.textColor = isHeader ? bodyColor : secondaryColor
        label.numberOfLines = 0
        label.text = text
        switch alignment {
        case .center: label.textAlignment = .center
        case .trailing: label.textAlignment = .right
        case .leading, .unspecified: label.textAlignment = .natural
        }
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])
        return container
    }
}

@MainActor
final class AgentInlineImagePreviewView: UIView {
    let targetSize: CGSize
    var onTap: (@MainActor () -> Void)?

    private let imageView = UIImageView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let messageLabel = UILabel()

    init(size: CGSize, tintColor: UIColor, alternativeText: String) {
        self.targetSize = size
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 10
        layer.borderWidth = 1 / UIScreen.main.scale
        layer.borderColor = UIColor.separator.cgColor
        clipsToBounds = true
        accessibilityIdentifier = "AgentInlineImagePreview"
        accessibilityLabel = alternativeText
        isAccessibilityElement = true
        accessibilityTraits = [.image, .button]

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        imageView.accessibilityIdentifier = "AgentInlineImagePreviewImage"
        addSubview(imageView)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.color = tintColor
        activityIndicator.hidesWhenStopped = true
        addSubview(activityIndicator)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .preferredFont(forTextStyle: .caption1)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = tintColor
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 2
        messageLabel.accessibilityIdentifier = "AgentInlineImagePreviewMessage"
        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size.width),
            heightAnchor.constraint(equalToConstant: size.height),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))
        showMessage(AgentStrings.imageProvidedByHost)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func showLoading() {
        imageView.image = nil
        imageView.isHidden = true
        messageLabel.text = AgentStrings.loadingImage
        messageLabel.isHidden = false
        activityIndicator.startAnimating()
    }

    func show(image: UIImage, alternativeText: String) {
        activityIndicator.stopAnimating()
        messageLabel.isHidden = true
        imageView.image = image
        imageView.isHidden = false
        accessibilityLabel = alternativeText
    }

    func showMessage(_ message: String) {
        activityIndicator.stopAnimating()
        imageView.image = nil
        imageView.isHidden = true
        messageLabel.text = message
        messageLabel.isHidden = false
    }

    override func accessibilityActivate() -> Bool {
        onTap?()
        return onTap != nil
    }

    @objc private func didTap() {
        onTap?()
    }
}

@MainActor
final class AgentSelectableTextView: UITextView {
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        isEditable = false
        isScrollEnabled = false
        isSelectable = true
        backgroundColor = .clear
        textContainerInset = .zero
        self.textContainer.lineFragmentPadding = 0
        dataDetectorTypes = [.link]
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

@MainActor
final class AgentDefaultBlockRenderer: AgentTableBlockRenderer {
    let supportedKinds: Set<AgentBlockKind>
    private let parser = AgentMarkdownParser()
    private let cache = AgentMarkdownDocumentCache()

    init(supportedKinds: Set<AgentBlockKind>) { self.supportedKinds = supportedKinds }

    func register(in collectionView: UICollectionView) {
        collectionView.register(
            AgentBlockCell.self,
            forCellWithReuseIdentifier: AgentBlockCell.reuseIdentifier
        )
    }

    func dequeueConfiguredCell(
        from collectionView: UICollectionView,
        at indexPath: IndexPath,
        context: AgentBlockRenderContext
    ) -> UICollectionViewCell {
        guard
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: AgentBlockCell.reuseIdentifier,
                for: indexPath
            ) as? AgentBlockCell
        else {
            return UICollectionViewCell()
        }
        cell.configure(context: context, parser: parser, cache: cache)
        return cell
    }

    func register(in tableView: UITableView) {
        tableView.register(
            AgentTableBlockCell.self,
            forCellReuseIdentifier: AgentTableBlockCell.reuseIdentifier
        )
    }

    func dequeueConfiguredCell(
        from tableView: UITableView,
        at indexPath: IndexPath,
        context: AgentBlockRenderContext
    ) -> UITableViewCell {
        guard
            let cell = tableView.dequeueReusableCell(
                withIdentifier: AgentTableBlockCell.reuseIdentifier,
                for: indexPath
            ) as? AgentTableBlockCell
        else { return UITableViewCell() }
        cell.configure(context: context, parser: parser, cache: cache)
        return cell
    }
}

private enum AgentMarkdownPlainTextRenderer {
    static func render(_ document: AgentMarkdownRenderDocument) -> String {
        document.blocks.map(render).joined(separator: "\n\n")
    }

    static func render(_ block: AgentMarkdownRenderBlock) -> String {
        switch block {
        case .paragraph(let content): inline(content)
        case .heading(_, let content): inline(content)
        case .blockQuote(let blocks): blocks.map(render).map { "> \($0)" }.joined(separator: "\n")
        case .orderedList(let start, let items):
            items.enumerated().map {
                "\(start + $0.offset). \($0.element.blocks.map(render).joined(separator: " "))"
            }.joined(separator: "\n")
        case .unorderedList(let items):
            items.map { item in
                let prefix = item.isChecked.map { $0 ? "☑︎" : "☐" } ?? "•"
                return "\(prefix) \(item.blocks.map(render).joined(separator: " "))"
            }.joined(separator: "\n")
        case .thematicBreak: "────────"
        case .codeBlock(let language, let code):
            [language, code].compactMap { $0 }.joined(separator: "\n")
        case .table(let table):
            ([table.header] + table.rows).map { row in row.map(inline).joined(separator: "  |  ") }
                .joined(separator: "\n")
        case .image(_, let alternativeText): "[\(alternativeText)]"
        case .unsupported(let raw): raw
        }
    }

    static func inline(_ content: [AgentMarkdownInline]) -> String {
        content.map { value in
            switch value {
            case .text(let text), .code(let text), .unsupported(let text): text
            case .emphasis(let nested), .strong(let nested), .strikethrough(let nested):
                inline(nested)
            case .link(_, _, let nested): inline(nested)
            case .image(_, let alternativeText): "[\(alternativeText)]"
            case .softBreak: " "
            case .hardBreak: "\n"
            }
        }.joined()
    }
}

extension JSONEncoder {
    fileprivate static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension UIView {
    fileprivate func findSubview<T: UIView>(of type: T.Type) -> T? {
        if let match = self as? T { return match }
        for subview in subviews {
            if let match = subview.findSubview(of: type) { return match }
        }
        return nil
    }
}
