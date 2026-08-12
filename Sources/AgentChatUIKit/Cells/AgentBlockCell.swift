import AgentChatCore
import AgentChatMarkdown
import UIKit

private let agentDiffWasTruncatedMetadataKey = "agentchat.internal.diff-was-truncated"

private enum AgentMarkdownInlineSegment {
    case text([AgentMarkdownInline])
    case image(source: String?, alternativeText: String)
}

private func agentMarkdownInlineSegments(
    _ content: [AgentMarkdownInline]
) -> [AgentMarkdownInlineSegment] {
    var result: [AgentMarkdownInlineSegment] = []

    func appendText(_ values: [AgentMarkdownInline]) {
        guard !values.isEmpty else { return }
        if case .text(let existing) = result.last {
            result[result.count - 1] = .text(existing + values)
        } else {
            result.append(.text(values))
        }
    }

    func appendNested(
        _ nested: [AgentMarkdownInline],
        transform: ([AgentMarkdownInline]) -> AgentMarkdownInline
    ) {
        for segment in agentMarkdownInlineSegments(nested) {
            switch segment {
            case .text(let values):
                appendText([transform(values)])
            case .image(let source, let alternativeText):
                result.append(.image(source: source, alternativeText: alternativeText))
            }
        }
    }

    for value in content {
        switch value {
        case .image(let source, let alternativeText):
            result.append(.image(source: source, alternativeText: alternativeText))
        case .emphasis(let nested):
            appendNested(nested, transform: AgentMarkdownInline.emphasis)
        case .strong(let nested):
            appendNested(nested, transform: AgentMarkdownInline.strong)
        case .strikethrough(let nested):
            appendNested(nested, transform: AgentMarkdownInline.strikethrough)
        case .link(let destination, let title, let nested):
            appendNested(nested) {
                .link(destination: destination, title: title, content: $0)
            }
        case .text, .code, .softBreak, .hardBreak, .unsupported:
            appendText([value])
        }
    }
    return result
}

private struct AgentBlockPresentationIdentity: Hashable {
    let blockID: AgentBlockID
    let revision: Int64
    let width: Int
    let contentSizeCategory: String
    let themeVersion: Int
    let isExpanded: Bool
    let isResolvingApproval: Bool
    let canRetry: Bool
    let toolPresentationStyle: AgentToolPresentationStyle

    @MainActor
    init(context: AgentBlockRenderContext) {
        blockID = context.block.id
        revision = context.block.revision
        width = Int(context.availableWidth.rounded())
        contentSizeCategory = context.environment.contentSizeCategory
        themeVersion = context.theme.version
        isExpanded = context.environment.expandedBlockIDs.contains(context.block.id)
        isResolvingApproval = {
            guard case .approval(let approval) = context.block.content else { return false }
            return context.environment.resolvingApprovalIDs.contains(approval.approvalID)
        }()
        canRetry = context.environment.canRetry
        toolPresentationStyle = context.environment.toolPresentationStyle
    }
}

@MainActor
private final class AgentBlockContentView: UIView {
    var didChangeHeight: (() -> Void)?

    private let rootStack = UIStackView()
    private var asynchronousTask: Task<Void, Never>?
    private var representedBlockID: AgentBlockID?
    private var representedRevision: Int64?
    private var representedPresentation: AgentBlockPresentationIdentity?

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
        representedPresentation = nil
        didChangeHeight = nil
        removeArrangedSubviews()
        accessibilityLabel = nil
        accessibilityValue = nil
        accessibilityTraits = []
    }

    func configure(
        context: AgentBlockRenderContext,
        parser: AgentMarkdownParser,
        cache: AgentMarkdownDocumentCache,
        diffParser: AgentUnifiedDiffParser,
        preparedMarkdownDocument: AgentMarkdownRenderDocument? = nil,
        didPrepareMarkdown: ((AgentMarkdownRenderDocument) -> Void)? = nil
    ) {
        let presentation = AgentBlockPresentationIdentity(context: context)
        guard representedPresentation != presentation else { return }
        asynchronousTask?.cancel()
        removeArrangedSubviews()
        representedBlockID = context.block.id
        representedRevision = context.block.revision
        representedPresentation = presentation
        backgroundColor = .clear

        let card = makeCard(
            context: context,
            preparedMarkdownDocument: preparedMarkdownDocument
        )
        rootStack.addArrangedSubview(card)
        accessibilityLabel = accessibilityText(for: context.block)
        accessibilityValue = stateText(context.block.state)

        if case .markdown(let markdown) = context.block.content {
            if preparedMarkdownDocument != nil { return }
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
                didPrepareMarkdown?(document)
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

        if case .diff(let diff) = context.block.content,
            diff.files.isEmpty,
            let raw = diff.rawUnifiedDiff,
            !raw.isEmpty
        {
            let blockID = context.block.id
            let revision = context.block.revision
            asynchronousTask = Task { [weak self] in
                let result = await diffParser.parse(
                    raw,
                    cacheKey: .init(identifier: blockID.rawValue, revision: revision)
                )
                guard !Task.isCancelled, let self,
                    self.representedBlockID == blockID,
                    self.representedRevision == revision
                else { return }
                var parsedDiff = diff
                parsedDiff.files = result.files
                var parsedBlock = context.block
                parsedBlock.content = .diff(parsedDiff)
                if result.wasTruncated {
                    parsedBlock.metadata[agentDiffWasTruncatedMetadataKey] = .bool(true)
                }
                let parsedContext = AgentBlockRenderContext(
                    conversationID: context.conversationID,
                    turn: context.turn,
                    block: parsedBlock,
                    availableWidth: context.availableWidth,
                    theme: context.theme,
                    environment: context.environment,
                    imageProvider: context.imageProvider,
                    actionSink: context.actionSink
                )
                self.removeArrangedSubviews()
                self.rootStack.addArrangedSubview(
                    self.makeCard(
                        context: parsedContext,
                        preparedMarkdownDocument: nil
                    )
                )
                self.accessibilityLabel = self.accessibilityText(for: parsedBlock)
                self.accessibilityValue = self.stateText(parsedBlock.state)
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

    private func makeCard(
        context: AgentBlockRenderContext,
        preparedMarkdownDocument: AgentMarkdownRenderDocument?
    ) -> UIView {
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
            populate(
                stack,
                context: context,
                preparedMarkdownDocument: preparedMarkdownDocument
            )
            return wrapper
        }

        populate(
            stack,
            context: context,
            preparedMarkdownDocument: preparedMarkdownDocument
        )
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
            stack.addArrangedSubview(
                actionButton(title: AgentStrings.copyRaw, context: context) {
                    context.actionSink.send(.copy(context.block.id))
                }
            )

        case .command(let value):
            stack.addArrangedSubview(detailSectionLabel(AgentStrings.command, context: context))
            stack.addArrangedSubview(codeTextView(value.command, context: context))
            stack.addArrangedSubview(
                actionButton(title: AgentStrings.copyCommand, context: context) {
                    UIPasteboard.general.string = value.command
                }
            )
            if let directory = value.workingDirectory {
                stack.addArrangedSubview(detailLabel(directory, context: context))
            }
            if !value.output.text.isEmpty {
                stack.addArrangedSubview(detailSectionLabel(AgentStrings.output, context: context))
                stack.addArrangedSubview(codeTextView(value.output.text, context: context))
                stack.addArrangedSubview(
                    actionButton(title: AgentStrings.copyOutput, context: context) {
                        UIPasteboard.general.string = value.output.text
                    }
                )
            }
            if value.output.wasTruncated {
                stack.addArrangedSubview(
                    detailLabel(AgentStrings.outputTruncated, context: context))
                stack.addArrangedSubview(
                    actionButton(title: AgentStrings.openFullOutput, context: context) {
                        context.actionSink.send(
                            .custom(
                                kind: "agentchat.open-full-command-output",
                                payload: .object(["blockID": .string(context.block.id.rawValue)])
                            )
                        )
                    }
                )
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
            stack.addArrangedSubview(
                actionButton(title: AgentStrings.open, context: context) {
                    context.actionSink.send(.openFile(.localIdentifier(value.path)))
                }
            )

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

    private func populate(
        _ stack: UIStackView,
        context: AgentBlockRenderContext,
        preparedMarkdownDocument: AgentMarkdownRenderDocument?
    ) {
        switch context.block.content {
        case .userText(let value):
            stack.addArrangedSubview(bodyLabel(value.text, context: context))
            for attachment in value.attachments {
                stack.addArrangedSubview(detailLabel("📎 \(attachment.name)", context: context))
            }

        case .markdown(let value):
            let view = AgentMarkdownContentView(
                source: value.markdown,
                document: preparedMarkdownDocument,
                context: context
            )
            view.didChangeHeight = { [weak self] in self?.didChangeHeight?() }
            stack.addArrangedSubview(view)

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
            let summary = "\(value.files.count) files · +\(additions) −\(deletions)"
            let wasTruncated =
                context.block.metadata[agentDiffWasTruncatedMetadataKey] == .bool(true)
            stack.addArrangedSubview(
                detailLabel(
                    wasTruncated ? "\(summary) · \(AgentStrings.outputTruncated)" : summary,
                    context: context
                )
            )
            let isExpanded = context.environment.expandedBlockIDs.contains(context.block.id)
            if isExpanded {
                for file in value.files.prefix(12) {
                    let path = file.newPath ?? file.oldPath ?? AgentStrings.changes
                    stack.addArrangedSubview(
                        detailLabel(
                            "\(path)  +\(file.additions) −\(file.deletions)",
                            context: context
                        )
                    )
                }
            }
            if isExpanded, let raw = value.rawUnifiedDiff {
                stack.addArrangedSubview(codeTextView(String(raw.prefix(8_000)), context: context))
            }
            stack.addArrangedSubview(
                actionButton(
                    title: isExpanded ? AgentStrings.collapse : AgentStrings.expand,
                    context: context
                ) {
                    context.actionSink.send(.toggleExpanded(context.block.id))
                }
            )
            stack.addArrangedSubview(
                actionButton(title: AgentStrings.openFullDiff, context: context) {
                    context.actionSink.send(
                        .custom(
                            kind: "agentchat.open-full-diff",
                            payload: .object(["blockID": .string(context.block.id.rawValue)])
                        )
                    )
                }
            )

        case .approval(let value):
            stack.addArrangedSubview(titleLabel(value.title, context: context))
            if let message = value.message {
                stack.addArrangedSubview(bodyLabel(message, context: context))
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
            if let mediaType = value.mediaType {
                stack.addArrangedSubview(detailLabel(mediaType, context: context))
            }
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

    private func bodyLabel(_ text: String, context: AgentBlockRenderContext) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: context.theme.typography.body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = context.theme.colors.primaryText
        label.numberOfLines = 0
        label.text = text
        return label
    }

    private func codeTextView(_ text: String, context: AgentBlockRenderContext) -> UITextView {
        let view = AgentSelectableTextView()
        view.adjustsFontForContentSizeCategory = true
        view.textColor = context.theme.colors.primaryText
        view.linkTextAttributes = [.foregroundColor: context.theme.colors.accent]
        view.text = text
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
        button.isPointerInteractionEnabled = true
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
final class AgentBlockCell: UICollectionViewCell, UIPointerInteractionDelegate {
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
        addInteraction(UIPointerInteraction(delegate: self))
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
        cache: AgentMarkdownDocumentCache,
        diffParser: AgentUnifiedDiffParser,
        preparedMarkdownDocument: AgentMarkdownRenderDocument? = nil,
        didPrepareMarkdown: ((AgentMarkdownRenderDocument) -> Void)? = nil
    ) {
        blockContentView.configure(
            context: context,
            parser: parser,
            cache: cache,
            diffParser: diffParser,
            preparedMarkdownDocument: preparedMarkdownDocument,
            didPrepareMarkdown: didPrepareMarkdown
        )
        accessibilityLabel = blockContentView.accessibilityLabel
        accessibilityValue = blockContentView.accessibilityValue
        accessibilityTraits = blockContentView.accessibilityTraits
    }

    func waitForPendingRendering() async {
        await blockContentView.waitForPendingRendering()
    }

    func pointerInteraction(
        _ interaction: UIPointerInteraction,
        styleFor region: UIPointerRegion
    ) -> UIPointerStyle? {
        UIPointerStyle(effect: .highlight(UITargetedPreview(view: contentView)), shape: nil)
    }
}

@MainActor
final class AgentTableBlockCell: UITableViewCell, UIPointerInteractionDelegate {
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
        addInteraction(UIPointerInteraction(delegate: self))
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
        cache: AgentMarkdownDocumentCache,
        diffParser: AgentUnifiedDiffParser,
        preparedMarkdownDocument: AgentMarkdownRenderDocument? = nil,
        didPrepareMarkdown: ((AgentMarkdownRenderDocument) -> Void)? = nil
    ) {
        let sideInset = context.theme.metrics.pageInset
        leadingConstraint.constant = sideInset
        trailingConstraint.constant = -sideInset
        widthConstraint.constant = -sideInset * 2
        maximumWidthConstraint.constant = context.theme.metrics.maximumContentWidth
        blockContentView.configure(
            context: context,
            parser: parser,
            cache: cache,
            diffParser: diffParser,
            preparedMarkdownDocument: preparedMarkdownDocument,
            didPrepareMarkdown: didPrepareMarkdown
        )
        accessibilityLabel = nil
        accessibilityValue = nil
        accessibilityTraits = []
    }

    func waitForPendingRendering() async {
        await blockContentView.waitForPendingRendering()
    }

    func pointerInteraction(
        _ interaction: UIPointerInteraction,
        styleFor region: UIPointerRegion
    ) -> UIPointerStyle? {
        UIPointerStyle(effect: .highlight(UITargetedPreview(view: contentView)), shape: nil)
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
    private let fontTraits: UITraitCollection
    private let imageProvider: (any AgentImageProviding)?
    private let actionSink: AgentBlockActionSink
    private let blockID: AgentBlockID
    private let isCodeExpanded: Bool
    var didChangeHeight: (() -> Void)?

    init(
        source: String,
        document: AgentMarkdownRenderDocument? = nil,
        context: AgentBlockRenderContext
    ) {
        self.bodyTextStyle = context.theme.typography.body
        self.bodyColor = context.theme.colors.primaryText
        self.secondaryColor = context.theme.colors.secondaryText
        self.accentColor = context.theme.colors.accent
        self.codePointSize = context.theme.typography.codePointSize
        self.availableWidth = max(1, context.availableWidth)
        self.fontTraits = UITraitCollection(
            preferredContentSizeCategory: UIContentSizeCategory(
                rawValue: context.environment.contentSizeCategory
            )
        )
        self.imageProvider = context.imageProvider
        self.actionSink = context.actionSink
        self.blockID = context.block.id
        self.isCodeExpanded = context.environment.expandedBlockIDs.contains(context.block.id)
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
        if let document {
            addRenderedViews(document)
        } else {
            stack.addArrangedSubview(makeTextView(source))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func apply(_ document: AgentMarkdownRenderDocument) {
        removeRenderedViews()
        addRenderedViews(document)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func addRenderedViews(_ document: AgentMarkdownRenderDocument) {
        for block in document.blocks {
            stack.addArrangedSubview(makeView(for: block))
        }
    }

    private func makeView(
        for block: AgentMarkdownRenderBlock,
        availableWidth nestedAvailableWidth: CGFloat? = nil
    ) -> UIView {
        let contentWidth = max(1, nestedAvailableWidth ?? availableWidth)
        switch block {
        case .paragraph(let content):
            return makeInlineContentView(
                content,
                font: preferredFont(forTextStyle: bodyTextStyle),
                availableWidth: contentWidth
            )

        case .heading(let level, let content):
            return makeInlineContentView(
                content,
                font: preferredFont(forTextStyle: headingTextStyle(level: level)),
                availableWidth: contentWidth
            )

        case .codeBlock(let language, let code):
            let view = AgentMarkdownCodeBlockView(
                language: language,
                code: code,
                availableWidth: contentWidth,
                pointSize: codePointSize,
                contentSizeCategory: fontTraits.preferredContentSizeCategory,
                textColor: bodyColor,
                secondaryColor: secondaryColor,
                accentColor: accentColor,
                isExpanded: isCodeExpanded
            )
            view.didChangeExpansion = { [actionSink, blockID] _ in
                actionSink.send(.toggleExpanded(blockID))
            }
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
                availableWidth: contentWidth,
                bodyTextStyle: bodyTextStyle,
                contentSizeCategory: fontTraits.preferredContentSizeCategory,
                bodyColor: bodyColor,
                secondaryColor: secondaryColor,
                accentColor: accentColor,
                imageProvider: imageProvider,
                actionSink: actionSink
            )

        case .image(let source, let alternativeText):
            return AgentMarkdownImageView(
                source: source,
                alternativeText: alternativeText,
                availableWidth: contentWidth,
                tintColor: secondaryColor,
                provider: imageProvider,
                actionSink: actionSink
            )

        case .blockQuote(let blocks):
            if blockContainsImage(block) {
                return makeBlockQuoteView(blocks, availableWidth: contentWidth)
            }
            return makeAttributedTextView(
                AgentMarkdownAttributedStringRenderer.block(
                    block,
                    font: preferredFont(forTextStyle: bodyTextStyle),
                    color: bodyColor,
                    secondaryColor: secondaryColor,
                    accentColor: accentColor
                )
            )

        case .orderedList(let start, let items):
            if blockContainsImage(block) {
                return makeListView(
                    items,
                    prefixes: items.indices.map { "\(start + $0)." },
                    availableWidth: contentWidth
                )
            }
            return makeAttributedTextView(
                AgentMarkdownAttributedStringRenderer.block(
                    block,
                    font: preferredFont(forTextStyle: bodyTextStyle),
                    color: bodyColor,
                    secondaryColor: secondaryColor,
                    accentColor: accentColor
                )
            )

        case .unorderedList(let items):
            if blockContainsImage(block) {
                return makeListView(
                    items,
                    prefixes: items.map { item in
                        item.isChecked.map { $0 ? "☑︎" : "☐" } ?? "•"
                    },
                    availableWidth: contentWidth
                )
            }
            return makeAttributedTextView(
                AgentMarkdownAttributedStringRenderer.block(
                    block,
                    font: preferredFont(forTextStyle: bodyTextStyle),
                    color: bodyColor,
                    secondaryColor: secondaryColor,
                    accentColor: accentColor
                )
            )

        case .unsupported:
            return makeAttributedTextView(
                AgentMarkdownAttributedStringRenderer.block(
                    block,
                    font: preferredFont(forTextStyle: bodyTextStyle),
                    color: bodyColor,
                    secondaryColor: secondaryColor,
                    accentColor: accentColor
                )
            )
        }
    }

    private func makeInlineContentView(
        _ content: [AgentMarkdownInline],
        font: UIFont,
        availableWidth: CGFloat
    ) -> UIView {
        let segments = agentMarkdownInlineSegments(content)
        guard
            segments.contains(where: { segment in
                if case .image = segment { return true }
                return false
            })
        else {
            return makeAttributedTextView(attributedText(for: content, font: font))
        }

        // UIKit text attachments cannot be resolved asynchronously through the host image
        // provider. Preserve mixed Markdown in source order by rendering text runs and image
        // previews as adjacent vertical segments instead of reducing inline images to alt text.
        let paragraph = UIStackView()
        paragraph.axis = .vertical
        paragraph.spacing = 8

        for segment in segments {
            switch segment {
            case .text(let values):
                guard !values.isEmpty else { continue }
                paragraph.addArrangedSubview(
                    makeAttributedTextView(attributedText(for: values, font: font))
                )
            case .image(let source, let alternativeText):
                paragraph.addArrangedSubview(
                    AgentMarkdownImageView(
                        source: source,
                        alternativeText: alternativeText,
                        availableWidth: availableWidth,
                        tintColor: secondaryColor,
                        provider: imageProvider,
                        actionSink: actionSink
                    )
                )
            }
        }
        return paragraph
    }

    private func makeBlockQuoteView(
        _ blocks: [AgentMarkdownRenderBlock],
        availableWidth: CGFloat
    ) -> UIView {
        let bar = UIView()
        bar.backgroundColor = secondaryColor.withAlphaComponent(0.45)
        bar.layer.cornerRadius = 1
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.widthAnchor.constraint(equalToConstant: 2).isActive = true

        let nestedWidth = max(1, availableWidth - 10)
        let row = UIStackView(
            arrangedSubviews: [
                bar,
                makeNestedBlocksView(blocks, availableWidth: nestedWidth),
            ]
        )
        row.axis = .horizontal
        row.alignment = .fill
        row.spacing = 8
        return row
    }

    private func makeListView(
        _ items: [AgentMarkdownListItem],
        prefixes: [String],
        availableWidth: CGFloat
    ) -> UIView {
        let list = UIStackView()
        list.axis = .vertical
        list.spacing = 8
        for (index, item) in items.enumerated() {
            let prefix = UILabel()
            prefix.font = preferredFont(forTextStyle: bodyTextStyle)
            prefix.textColor = secondaryColor
            prefix.text = prefixes[index]
            prefix.adjustsFontForContentSizeCategory = true
            prefix.setContentHuggingPriority(.required, for: .horizontal)
            prefix.setContentCompressionResistancePriority(.required, for: .horizontal)
            let nestedWidth = max(1, availableWidth - prefix.intrinsicContentSize.width - 8)

            let row = UIStackView(
                arrangedSubviews: [
                    prefix,
                    makeNestedBlocksView(item.blocks, availableWidth: nestedWidth),
                ]
            )
            row.axis = .horizontal
            row.alignment = .top
            row.spacing = 8
            list.addArrangedSubview(row)
        }
        return list
    }

    private func makeNestedBlocksView(
        _ blocks: [AgentMarkdownRenderBlock],
        availableWidth: CGFloat
    ) -> UIView {
        let nested = UIStackView()
        nested.axis = .vertical
        nested.spacing = 6
        for block in blocks {
            nested.addArrangedSubview(makeView(for: block, availableWidth: availableWidth))
        }
        return nested
    }

    private func blockContainsImage(_ block: AgentMarkdownRenderBlock) -> Bool {
        switch block {
        case .paragraph(let content), .heading(_, let content):
            return inlineContainsImage(content)
        case .blockQuote(let blocks):
            return blocks.contains(where: blockContainsImage)
        case .orderedList(_, let items), .unorderedList(let items):
            return items.flatMap(\.blocks).contains(where: blockContainsImage)
        case .table(let table):
            return ([table.header] + table.rows).flatMap { $0 }.contains(
                where: inlineContainsImage)
        case .image:
            return true
        case .thematicBreak, .codeBlock, .unsupported:
            return false
        }
    }

    private func inlineContainsImage(_ content: [AgentMarkdownInline]) -> Bool {
        content.contains { value in
            switch value {
            case .image:
                return true
            case .emphasis(let nested), .strong(let nested), .strikethrough(let nested):
                return inlineContainsImage(nested)
            case .link(_, _, let nested):
                return inlineContainsImage(nested)
            case .text, .code, .softBreak, .hardBreak, .unsupported:
                return false
            }
        }
    }

    private func attributedText(
        for content: [AgentMarkdownInline],
        font: UIFont
    ) -> NSAttributedString {
        AgentMarkdownAttributedStringRenderer.inline(
            content,
            font: font,
            color: bodyColor,
            accentColor: accentColor
        )
    }

    private func makeTextView(_ text: String) -> AgentSelectableTextView {
        let view = AgentSelectableTextView()
        view.font = preferredFont(forTextStyle: bodyTextStyle)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = bodyColor
        view.linkTextAttributes = [.foregroundColor: accentColor]
        view.text = text
        view.onOpenURL = { [actionSink] url in actionSink.send(.openLink(url)) }
        return view
    }

    private func makeAttributedTextView(_ text: NSAttributedString) -> AgentSelectableTextView {
        let view = AgentSelectableTextView()
        view.adjustsFontForContentSizeCategory = true
        view.linkTextAttributes = [
            .foregroundColor: accentColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        view.attributedText = text
        view.onOpenURL = { [actionSink] url in actionSink.send(.openLink(url)) }
        return view
    }

    private func headingTextStyle(level: Int) -> UIFont.TextStyle {
        switch level {
        case 1: .title2
        case 2: .title3
        default: .headline
        }
    }

    private func preferredFont(forTextStyle style: UIFont.TextStyle) -> UIFont {
        UIFont.preferredFont(forTextStyle: style, compatibleWith: fontTraits)
    }

    private func removeRenderedViews() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}

@MainActor
enum AgentMarkdownAttributedStringRenderer {
    static func block(
        _ block: AgentMarkdownRenderBlock,
        font: UIFont,
        color: UIColor,
        secondaryColor: UIColor,
        accentColor: UIColor
    ) -> NSAttributedString {
        switch block {
        case .paragraph(let content), .heading(_, let content):
            return inline(content, font: font, color: color, accentColor: accentColor)
        case .blockQuote(let blocks):
            let result = NSMutableAttributedString()
            for (index, nested) in blocks.enumerated() {
                if index > 0 { result.append(NSAttributedString(string: "\n")) }
                result.append(
                    NSAttributedString(
                        string: "▌ ",
                        attributes: [.font: font, .foregroundColor: secondaryColor]
                    )
                )
                result.append(
                    Self.block(
                        nested,
                        font: font,
                        color: color,
                        secondaryColor: secondaryColor,
                        accentColor: accentColor
                    )
                )
            }
            return result
        case .orderedList(let start, let items):
            return list(
                items,
                prefixes: items.indices.map { "\(start + $0). " },
                font: font,
                color: color,
                secondaryColor: secondaryColor,
                accentColor: accentColor
            )
        case .unorderedList(let items):
            return list(
                items,
                prefixes: items.map { item in
                    item.isChecked.map { $0 ? "☑︎ " : "☐ " } ?? "• "
                },
                font: font,
                color: color,
                secondaryColor: secondaryColor,
                accentColor: accentColor
            )
        case .unsupported(let raw):
            return NSAttributedString(
                string: raw,
                attributes: [.font: font, .foregroundColor: secondaryColor]
            )
        case .thematicBreak, .codeBlock, .table, .image:
            return NSAttributedString(
                string: AgentMarkdownPlainTextRenderer.render(block),
                attributes: [.font: font, .foregroundColor: color]
            )
        }
    }

    static func inline(
        _ content: [AgentMarkdownInline],
        font: UIFont,
        color: UIColor,
        accentColor: UIColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for value in content {
            switch value {
            case .text(let text), .unsupported(let text):
                result.append(styled(text, font: font, color: color))
            case .emphasis(let nested):
                result.append(
                    inline(
                        nested,
                        font: font.withTraits(.traitItalic),
                        color: color,
                        accentColor: accentColor
                    )
                )
            case .strong(let nested):
                result.append(
                    inline(
                        nested,
                        font: font.withTraits(.traitBold),
                        color: color,
                        accentColor: accentColor
                    )
                )
            case .strikethrough(let nested):
                let value = NSMutableAttributedString(
                    attributedString: inline(
                        nested,
                        font: font,
                        color: color,
                        accentColor: accentColor
                    )
                )
                value.addAttribute(
                    .strikethroughStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: NSRange(location: 0, length: value.length)
                )
                result.append(value)
            case .code(let code):
                result.append(
                    NSAttributedString(
                        string: code,
                        attributes: [
                            .font: UIFont.monospacedSystemFont(
                                ofSize: max(11, font.pointSize * 0.92),
                                weight: .regular
                            ),
                            .foregroundColor: color,
                            .backgroundColor: UIColor.tertiarySystemFill,
                        ]
                    )
                )
            case .link(let destination, _, let nested):
                let link = NSMutableAttributedString(
                    attributedString: inline(
                        nested,
                        font: font,
                        color: accentColor,
                        accentColor: accentColor
                    )
                )
                if let destination, let url = URL(string: destination), link.length > 0 {
                    link.addAttribute(
                        .link,
                        value: url,
                        range: NSRange(location: 0, length: link.length)
                    )
                }
                result.append(link)
            case .image(_, let alternativeText):
                result.append(styled("[\(alternativeText)]", font: font, color: color))
            case .softBreak:
                result.append(styled(" ", font: font, color: color))
            case .hardBreak:
                result.append(styled("\n", font: font, color: color))
            }
        }
        return result
    }

    private static func list(
        _ items: [AgentMarkdownListItem],
        prefixes: [String],
        font: UIFont,
        color: UIColor,
        secondaryColor: UIColor,
        accentColor: UIColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, item) in items.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(styled(prefixes[index], font: font, color: secondaryColor))
            for (blockIndex, nested) in item.blocks.enumerated() {
                if blockIndex > 0 { result.append(NSAttributedString(string: "\n  ")) }
                result.append(
                    block(
                        nested,
                        font: font,
                        color: color,
                        secondaryColor: secondaryColor,
                        accentColor: accentColor
                    )
                )
            }
        }
        return result
    }

    private static func styled(_ text: String, font: UIFont, color: UIColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    }
}

extension UIFont {
    fileprivate func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard
            let descriptor = fontDescriptor.withSymbolicTraits(
                fontDescriptor.symbolicTraits.union(traits)
            )
        else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

@MainActor
final class AgentMarkdownCodeBlockView: UIView {
    static let collapsedLineCount = 16
    static let maximumRenderedCharacterCount = 32_000
    static let maximumRenderedLineCount = 500
    static let maximumMeasuredCharacterCount = 16_000
    static let maximumMeasuredLineCharacterCount = 512
    static let maximumContentWidth: CGFloat = 4_096

    var didChangeHeight: (() -> Void)?
    var didChangeExpansion: ((Bool) -> Void)?
    var copyHandler: (String) -> Void = { UIPasteboard.general.string = $0 }

    private let code: String
    private let lineCount: Int
    private let font: UIFont
    private let scrollView = UIScrollView()
    private let codeView = AgentSelectableTextView()
    private let toggleButton = UIButton(type: .system)
    private var viewportHeightConstraint: NSLayoutConstraint!
    private var isExpanded: Bool

    init(
        language: String?,
        code: String,
        availableWidth: CGFloat,
        pointSize: CGFloat,
        contentSizeCategory: UIContentSizeCategory,
        textColor: UIColor,
        secondaryColor: UIColor,
        accentColor: UIColor,
        isExpanded: Bool = false
    ) {
        let boundedCode = Self.boundedCode(code)
        let displayedCode = boundedCode.text
        self.code = code
        let fontTraits = UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
        self.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .monospacedSystemFont(ofSize: pointSize, weight: .regular),
            compatibleWith: fontTraits
        )
        let contentWidth = Self.contentWidth(
            for: displayedCode,
            availableWidth: availableWidth,
            font: self.font
        )
        self.lineCount = Self.visualLineCount(
            in: displayedCode,
            contentWidth: contentWidth,
            font: self.font
        )
        self.isExpanded = isExpanded
        super.init(frame: .zero)

        backgroundColor = .tertiarySystemFill
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        clipsToBounds = true
        accessibilityIdentifier = "AgentMarkdownCodeBlock"

        let languageLabel = UILabel()
        languageLabel.font = .preferredFont(
            forTextStyle: .caption1,
            compatibleWith: fontTraits
        )
        languageLabel.adjustsFontForContentSizeCategory = true
        languageLabel.textColor = secondaryColor
        let languageTitle = language.flatMap { $0.isEmpty ? nil : $0 } ?? AgentStrings.code
        languageLabel.text =
            boundedCode.wasTruncated
            ? "\(languageTitle) · \(AgentStrings.codeTruncated)"
            : languageTitle

        var copyConfiguration = UIButton.Configuration.plain()
        copyConfiguration.title = AgentStrings.copy
        copyConfiguration.image = UIImage(systemName: "doc.on.doc")
        copyConfiguration.imagePadding = 4
        copyConfiguration.baseForegroundColor = accentColor
        let copyButton = UIButton(configuration: copyConfiguration)
        copyButton.isPointerInteractionEnabled = true
        copyButton.accessibilityIdentifier = "AgentMarkdownCodeCopyButton"
        copyButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                self.copyHandler(self.code)
            }, for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [languageLabel, UIView(), copyButton])
        header.axis = .horizontal
        header.alignment = .center
        header.layoutMargins = .init(top: 2, left: 10, bottom: 2, right: 4)
        header.isLayoutMarginsRelativeArrangement = true
        header.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true

        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.isDirectionalLockEnabled = true
        scrollView.accessibilityIdentifier = "AgentMarkdownCodeScrollView"

        codeView.font = font
        codeView.textColor = textColor
        codeView.text = displayedCode
        codeView.textContainerInset = .init(top: 8, left: 10, bottom: 8, right: 10)
        codeView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(codeView)
        NSLayoutConstraint.activate([
            codeView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            codeView.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            codeView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            codeView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            codeView.widthAnchor.constraint(equalToConstant: contentWidth),
            codeView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        toggleButton.configuration = .plain()
        toggleButton.isPointerInteractionEnabled = true
        toggleButton.configuration?.title =
            isExpanded ? AgentStrings.showLess : AgentStrings.showMore
        toggleButton.configuration?.image = UIImage(
            systemName: isExpanded ? "chevron.up" : "chevron.down"
        )
        toggleButton.configuration?.imagePadding = 5
        toggleButton.configuration?.baseForegroundColor = accentColor
        toggleButton.accessibilityIdentifier = "AgentMarkdownCodeDisclosureButton"
        toggleButton.isHidden = lineCount <= Self.collapsedLineCount
        toggleButton.addAction(
            UIAction { [weak self] _ in self?.toggleExpanded() }, for: .touchUpInside)
        toggleButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true

        let stack = UIStackView(arrangedSubviews: [header, scrollView, toggleButton])
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        viewportHeightConstraint = scrollView.heightAnchor.constraint(
            equalToConstant: Self.viewportHeight(
                lineCount: isExpanded ? lineCount : min(lineCount, Self.collapsedLineCount),
                font: font
            )
        )
        viewportHeightConstraint.isActive = true
        accessibilityValue = isExpanded ? AgentStrings.collapse : AgentStrings.expand
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    static func renderedLineCount(
        for code: String,
        availableWidth: CGFloat,
        font: UIFont
    ) -> Int {
        let displayedCode = boundedCode(code).text
        return visualLineCount(
            in: displayedCode,
            contentWidth: contentWidth(
                for: displayedCode,
                availableWidth: availableWidth,
                font: font
            ),
            font: font
        )
    }

    static func height(lineCount: Int, font: UIFont) -> CGFloat {
        let visible = min(max(1, lineCount), collapsedLineCount)
        return 36 + viewportHeight(lineCount: visible, font: font)
            + (lineCount > collapsedLineCount ? 36 : 0)
    }

    private static func viewportHeight(lineCount: Int, font: UIFont) -> CGFloat {
        ceil(CGFloat(max(1, lineCount)) * font.lineHeight) + 16
    }

    private static func boundedCode(_ code: String) -> (text: String, wasTruncated: Bool) {
        let characterEnd =
            code.index(
                code.startIndex,
                offsetBy: maximumRenderedCharacterCount,
                limitedBy: code.endIndex
            ) ?? code.endIndex
        var displayEnd = characterEnd
        var lineCount = 1
        var index = code.startIndex
        while index < characterEnd {
            if code[index] == "\n" {
                lineCount += 1
                if lineCount > maximumRenderedLineCount {
                    displayEnd = index
                    break
                }
            }
            code.formIndex(after: &index)
        }
        guard displayEnd < code.endIndex else { return (code, false) }
        return (String(code[..<displayEnd]) + "\n…", true)
    }

    private static func contentWidth(
        for code: String,
        availableWidth: CGFloat,
        font: UIFont
    ) -> CGFloat {
        let measurementSample = String(code.prefix(maximumMeasuredCharacterCount))
        let longestLineWidth =
            measurementSample.split(separator: "\n", omittingEmptySubsequences: false)
            .map {
                (String($0.prefix(maximumMeasuredLineCharacterCount)) as NSString)
                    .size(withAttributes: [.font: font]).width
            }
            .max() ?? 0
        return max(
            max(1, availableWidth),
            min(maximumContentWidth, ceil(longestLineWidth) + 24)
        )
    }

    private static func visualLineCount(
        in code: String,
        contentWidth: CGFloat,
        font: UIFont
    ) -> Int {
        let textStorage = NSTextStorage(string: code, attributes: [.font: font])
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: CGSize(
                width: max(1, contentWidth - 20),
                height: .greatestFiniteMagnitude
            )
        )
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        var count = 0
        layoutManager.enumerateLineFragments(
            forGlyphRange: layoutManager.glyphRange(for: textContainer)
        ) { _, _, _, _, _ in
            count += 1
        }
        if layoutManager.extraLineFragmentRect.height > 0 { count += 1 }
        return max(1, count)
    }

    private func toggleExpanded() {
        isExpanded.toggle()
        viewportHeightConstraint.constant = Self.viewportHeight(
            lineCount: isExpanded ? lineCount : min(lineCount, Self.collapsedLineCount),
            font: font
        )
        toggleButton.configuration?.title =
            isExpanded ? AgentStrings.showLess : AgentStrings.showMore
        toggleButton.configuration?.image = UIImage(
            systemName: isExpanded ? "chevron.up" : "chevron.down"
        )
        accessibilityValue = isExpanded ? AgentStrings.collapse : AgentStrings.expand
        invalidateIntrinsicContentSize()
        if let didChangeExpansion {
            didChangeExpansion(isExpanded)
        } else {
            didChangeHeight?()
        }
    }
}

@MainActor
final class AgentMarkdownImageView: UIView {
    private var loadTask: Task<Void, Never>?

    init(
        source: String?,
        alternativeText: String,
        availableWidth: CGFloat,
        tintColor: UIColor,
        provider: (any AgentImageProviding)?,
        actionSink: AgentBlockActionSink
    ) {
        super.init(frame: .zero)
        let width = min(max(1, availableWidth), 560)
        let preview = AgentInlineImagePreviewView(
            size: .init(width: width, height: max(140, width * 0.5625)),
            tintColor: tintColor,
            alternativeText: alternativeText
        )
        let row = UIStackView(arrangedSubviews: [preview, UIView()])
        row.axis = .horizontal
        row.alignment = .top
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        guard let reference = Self.reference(for: source) else {
            preview.showMessage(AgentStrings.imageUnavailable)
            return
        }
        preview.onTap = {
            actionSink.send(
                .previewImage(reference: reference, alternativeText: alternativeText)
            )
        }
        guard let provider else {
            preview.showMessage(AgentStrings.imageProvidedByHost)
            return
        }
        preview.showLoading()
        loadTask = Task { [weak preview] in
            do {
                let image = try await provider.image(
                    for: reference,
                    targetSize: preview?.targetSize ?? .zero,
                    scale: UIScreen.main.scale
                )
                try Task.checkCancellation()
                preview?.show(image: image, alternativeText: alternativeText)
            } catch is CancellationError {
                return
            } catch {
                preview?.showMessage(AgentStrings.imageUnavailable)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func waitForLoad() async { await loadTask?.value }

    deinit { loadTask?.cancel() }

    private static func reference(for source: String?) -> AgentResourceReference? {
        guard let source, !source.isEmpty else { return nil }
        if let url = URL(string: source), let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme)
        {
            return .remoteURL(url)
        }
        if source.hasPrefix("runtime://") { return .runtimeURI(source) }
        return .localIdentifier(source)
    }
}

@MainActor
final class AgentMarkdownTableView: UIScrollView {
    private let renderedHeight: CGFloat

    init(
        table: AgentMarkdownTable,
        availableWidth: CGFloat,
        bodyTextStyle: UIFont.TextStyle,
        contentSizeCategory: UIContentSizeCategory,
        bodyColor: UIColor,
        secondaryColor: UIColor,
        accentColor: UIColor,
        imageProvider: (any AgentImageProviding)?,
        actionSink: AgentBlockActionSink
    ) {
        let rows = [table.header] + table.rows
        let columnCount = max(1, rows.map(\.count).max() ?? 0)
        let columnWidth = max(120, floor(availableWidth / CGFloat(columnCount)))
        let fontTraits = UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
        let font = UIFont.preferredFont(forTextStyle: bodyTextStyle, compatibleWith: fontTraits)
        let headerFont = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: fontTraits)
        let rowHeights = rows.enumerated().map { index, row in
            Self.rowHeight(
                row: row,
                columnCount: columnCount,
                columnWidth: columnWidth,
                font: index == 0 ? headerFont : font,
                accentColor: accentColor
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
                let content = columnIndex < row.count ? row[columnIndex] : []
                let cell = Self.makeCell(
                    content: content,
                    columnTitle: columnIndex < headerTitles.count
                        ? headerTitles[columnIndex] : "",
                    alignment: columnIndex < table.alignments.count
                        ? table.alignments[columnIndex] : .unspecified,
                    isHeader: rowIndex == 0,
                    width: columnWidth,
                    font: rowIndex == 0 ? headerFont : font,
                    bodyColor: bodyColor,
                    secondaryColor: secondaryColor,
                    accentColor: accentColor,
                    imageProvider: imageProvider,
                    actionSink: actionSink
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

    static func height(
        for table: AgentMarkdownTable,
        availableWidth: CGFloat,
        bodyTextStyle: UIFont.TextStyle,
        contentSizeCategory: UIContentSizeCategory
    ) -> CGFloat {
        let rows = [table.header] + table.rows
        let columnCount = max(1, rows.map(\.count).max() ?? 0)
        let columnWidth = max(120, floor(availableWidth / CGFloat(columnCount)))
        let fontTraits = UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
        let font = UIFont.preferredFont(forTextStyle: bodyTextStyle, compatibleWith: fontTraits)
        let headerFont = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: fontTraits)
        return max(
            44,
            rows.enumerated().reduce(CGFloat.zero) { result, value in
                result
                    + rowHeight(
                        row: value.element,
                        columnCount: columnCount,
                        columnWidth: columnWidth,
                        font: value.offset == 0 ? headerFont : font,
                        accentColor: .link
                    )
            }
        )
    }

    private static func rowHeight(
        row: [[AgentMarkdownInline]],
        columnCount: Int,
        columnWidth: CGFloat,
        font: UIFont,
        accentColor: UIColor
    ) -> CGFloat {
        let contentHeight =
            (0..<columnCount).map { index -> CGFloat in
                let content = index < row.count ? row[index] : []
                return inlineContentHeight(
                    content,
                    width: max(1, columnWidth - 24),
                    font: font,
                    accentColor: accentColor
                ) + 20
            }.max() ?? 44
        return max(44, contentHeight)
    }

    private static func inlineContentHeight(
        _ content: [AgentMarkdownInline],
        width: CGFloat,
        font: UIFont,
        accentColor: UIColor
    ) -> CGFloat {
        let segments = agentMarkdownInlineSegments(content)
        let heights = segments.map { segment -> CGFloat in
            switch segment {
            case .text(let values):
                let attributed = AgentMarkdownAttributedStringRenderer.inline(
                    values,
                    font: font,
                    color: .label,
                    accentColor: accentColor
                )
                return ceil(
                    attributed.boundingRect(
                        with: .init(width: width, height: .greatestFiniteMagnitude),
                        options: [.usesFontLeading, .usesLineFragmentOrigin],
                        context: nil
                    ).height
                )
            case .image:
                let previewWidth = min(max(1, width), 560)
                return max(140, previewWidth * 0.5625)
            }
        }
        return heights.reduce(0, +) + CGFloat(max(0, heights.count - 1)) * 6
    }

    private static func makeCell(
        content: [AgentMarkdownInline],
        columnTitle: String,
        alignment: AgentMarkdownTable.Alignment,
        isHeader: Bool,
        width: CGFloat,
        font: UIFont,
        bodyColor: UIColor,
        secondaryColor: UIColor,
        accentColor: UIColor,
        imageProvider: (any AgentImageProviding)?,
        actionSink: AgentBlockActionSink
    ) -> UIView {
        let plainText = AgentMarkdownPlainTextRenderer.inline(content)
        let segments = agentMarkdownInlineSegments(content)
        let attributedSegments = segments.compactMap { segment -> NSAttributedString? in
            guard case .text(let values) = segment else { return nil }
            return AgentMarkdownAttributedStringRenderer.inline(
                values,
                font: font,
                color: isHeader ? bodyColor : secondaryColor,
                accentColor: accentColor
            )
        }
        let hasImage = segments.contains { segment in
            if case .image = segment { return true }
            return false
        }
        let hasLink = attributedSegments.contains { attributed in
            var found = false
            attributed.enumerateAttribute(
                .link,
                in: NSRange(location: 0, length: attributed.length)
            ) { value, _, stop in
                guard value != nil else { return }
                found = true
                stop.pointee = true
            }
            return found
        }
        let hasInteractiveContent = hasImage || hasLink

        let container = UIView()
        container.backgroundColor =
            isHeader
            ? UIColor.secondarySystemBackground
            : UIColor.systemBackground
        container.layer.borderWidth = 1 / UIScreen.main.scale
        container.layer.borderColor = UIColor.separator.cgColor
        container.widthAnchor.constraint(equalToConstant: width).isActive = true
        container.accessibilityIdentifier = "AgentMarkdownTableCell"
        container.isAccessibilityElement = !hasInteractiveContent
        container.accessibilityLabel =
            columnTitle.isEmpty
            ? plainText : "\(columnTitle): \(plainText)"
        container.accessibilityTraits = isHeader ? [.header] : [.staticText]

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 6
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        var textSegmentIndex = 0
        for segment in segments {
            switch segment {
            case .text:
                let attributed = attributedSegments[textSegmentIndex]
                textSegmentIndex += 1
                let textView = AgentSelectableTextView()
                textView.adjustsFontForContentSizeCategory = true
                textView.attributedText = attributed
                textView.linkTextAttributes = [
                    .foregroundColor: accentColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ]
                textView.onOpenURL = { url in actionSink.send(.openLink(url)) }
                textView.isAccessibilityElement = hasInteractiveContent
                if hasInteractiveContent, textSegmentIndex == 1, !columnTitle.isEmpty {
                    textView.accessibilityLabel = "\(columnTitle): \(attributed.string)"
                }
                if isHeader { textView.accessibilityTraits.insert(.header) }
                switch alignment {
                case .center: textView.textAlignment = .center
                case .trailing: textView.textAlignment = .right
                case .leading, .unspecified: textView.textAlignment = .natural
                }
                contentStack.addArrangedSubview(textView)
            case .image(let source, let alternativeText):
                contentStack.addArrangedSubview(
                    AgentMarkdownImageView(
                        source: source,
                        alternativeText: alternativeText,
                        availableWidth: max(1, width - 24),
                        tintColor: secondaryColor,
                        provider: imageProvider,
                        actionSink: actionSink
                    )
                )
            }
        }
        if segments.isEmpty {
            let empty = AgentSelectableTextView()
            empty.font = font
            empty.text = ""
            empty.isAccessibilityElement = false
            contentStack.addArrangedSubview(empty)
        }
        container.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -12),
            contentStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            contentStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
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
final class AgentSelectableTextView: UITextView, UITextViewDelegate {
    var onOpenURL: ((URL) -> Void)?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        isEditable = false
        isScrollEnabled = false
        isSelectable = true
        backgroundColor = .clear
        textContainerInset = .zero
        self.textContainer.lineFragmentPadding = 0
        dataDetectorTypes = [.link]
        delegate = self
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func textView(
        _ textView: UITextView,
        primaryActionFor textItem: UITextItem,
        defaultAction: UIAction
    ) -> UIAction? {
        guard textItem.range.location < textStorage.length else { return defaultAction }
        let value = textStorage.attribute(.link, at: textItem.range.location, effectiveRange: nil)
        let link: URL?
        if let url = value as? URL {
            link = url
        } else if let string = value as? String {
            link = URL(string: string)
        } else {
            link = nil
        }
        guard let link else { return defaultAction }
        return UIAction { [weak self] _ in self?.onOpenURL?(link) }
    }
}

@MainActor
final class AgentDefaultBlockRenderer: AgentTableBlockRenderer {
    let supportedKinds: Set<AgentBlockKind>
    private let parser = AgentMarkdownParser()
    private let cache = AgentMarkdownDocumentCache()
    private let diffParser = AgentUnifiedDiffParser()
    private let preparedMarkdownCache = AgentPreparedMarkdownCache()

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
        let key = markdownKeyIfNeeded(for: context)
        let document = key.flatMap { preparedMarkdownCache.document(for: $0) }
        cell.configure(
            context: context,
            parser: parser,
            cache: cache,
            diffParser: diffParser,
            preparedMarkdownDocument: document,
            didPrepareMarkdown: { [weak self] document in
                guard let self, let key else { return }
                self.preparedMarkdownCache.insert(document, for: key)
            }
        )
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
        let document = preparedMarkdownDocument(for: context)
        let key = markdownKeyIfNeeded(for: context)
        cell.configure(
            context: context,
            parser: parser,
            cache: cache,
            diffParser: diffParser,
            preparedMarkdownDocument: document,
            didPrepareMarkdown: { [weak self] document in
                guard let self, let key else { return }
                self.preparedMarkdownCache.insert(document, for: key)
            }
        )
        return cell
    }

    private func preparedMarkdownDocument(
        for context: AgentBlockRenderContext
    ) -> AgentMarkdownRenderDocument? {
        guard case .markdown = context.block.content else { return nil }
        let key = markdownKey(for: context)
        return preparedMarkdownCache.document(for: key)
    }

    private func markdownKeyIfNeeded(
        for context: AgentBlockRenderContext
    ) -> AgentMarkdownCacheKey? {
        guard case .markdown = context.block.content else { return nil }
        return markdownKey(for: context)
    }

    private func markdownKey(for context: AgentBlockRenderContext) -> AgentMarkdownCacheKey {
        AgentMarkdownCacheKey(
            blockID: context.block.id,
            revision: context.block.revision,
            width: Int(context.availableWidth.rounded()),
            contentSizeCategory: context.environment.contentSizeCategory,
            themeVersion: context.theme.version
        )
    }
}

extension AgentDefaultBlockRenderer: AgentTableBlockLayoutProviding {
    func tableRowHeight(for context: AgentBlockRenderContext) -> CGFloat {
        switch context.block.content {
        case .userText(let value):
            return AgentTableBlockLayoutCalculator.userTextHeight(value, context: context)
        case .markdown:
            guard let document = preparedMarkdownDocument(for: context) else {
                return UITableView.automaticDimension
            }
            // A disclosure changes the code viewport without changing the block revision.
            // Let UITableView read Auto Layout for these rows instead of pinning them to
            // the cached collapsed calculation.
            guard
                !AgentTableBlockLayoutCalculator.markdownRequiresSelfSizing(
                    document,
                    context: context
                )
            else {
                return UITableView.automaticDimension
            }
            return AgentTableBlockLayoutCalculator.markdownHeight(document, context: context)
        default:
            return UITableView.automaticDimension
        }
    }
}

extension AgentDefaultBlockRenderer: AgentBlockRendererCacheManaging {
    func removeCachedData() {
        preparedMarkdownCache.removeAll()
        Task { await cache.removeAll() }
        Task { await diffParser.removeAllCachedResults() }
    }
}

enum AgentMarkdownPlainTextRenderer {
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

    static func containsLink(in block: AgentMarkdownRenderBlock) -> Bool {
        switch block {
        case .paragraph(let content), .heading(_, let content):
            return containsLink(in: content)
        case .blockQuote(let blocks):
            return blocks.contains(where: containsLink)
        case .orderedList(_, let items), .unorderedList(let items):
            return items.flatMap(\.blocks).contains(where: containsLink)
        case .table(let table):
            return ([table.header] + table.rows).flatMap { $0 }.contains(where: containsLink)
        case .thematicBreak, .codeBlock, .image, .unsupported:
            return false
        }
    }

    private static func containsLink(in content: [AgentMarkdownInline]) -> Bool {
        content.contains { value in
            switch value {
            case .link:
                return true
            case .emphasis(let nested), .strong(let nested), .strikethrough(let nested):
                return containsLink(in: nested)
            case .text, .code, .image, .softBreak, .hardBreak, .unsupported:
                return false
            }
        }
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
