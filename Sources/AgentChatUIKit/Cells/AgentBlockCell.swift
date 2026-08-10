import AgentChatCore
import AgentChatMarkdown
import UIKit

@MainActor
final class AgentBlockCell: UICollectionViewCell {
    static let reuseIdentifier = "AgentBlockCell"

    private let rootStack = UIStackView()
    private var asynchronousTask: Task<Void, Never>?
    private var representedBlockID: AgentBlockID?
    private var representedRevision: Int64?

    override init(frame: CGRect) {
        super.init(frame: frame)
        rootStack.axis = .vertical
        rootStack.spacing = 8
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        asynchronousTask?.cancel()
        asynchronousTask = nil
        representedBlockID = nil
        representedRevision = nil
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
            guard let textView = card.findSubview(of: UITextView.self) else { return }
            let blockID = context.block.id
            let revision = context.block.revision
            asynchronousTask = Task { [weak self, weak textView] in
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
                let rendered = AgentMarkdownPlainTextRenderer.render(document)
                guard let self,
                    self.representedBlockID == blockID,
                    self.representedRevision == revision
                else { return }
                textView?.text = rendered
                textView?.invalidateIntrinsicContentSize()
            }
        }
    }

    private func makeCard(context: AgentBlockRenderContext) -> UIView {
        let container = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let isUser: Bool
        if case .userText = context.block.content { isUser = true } else { isUser = false }
        container.backgroundColor =
            isUser
            ? context.theme.colors.userBackground
            : background(for: context.block, theme: context.theme)
        container.layer.cornerRadius = isUser ? context.theme.metrics.cornerRadius : 10

        let inset: CGFloat = isUser ? 12 : 10
        let leading = stack.leadingAnchor.constraint(
            equalTo: container.leadingAnchor, constant: inset)
        let trailing = stack.trailingAnchor.constraint(
            equalTo: container.trailingAnchor, constant: -inset)
        NSLayoutConstraint.activate([
            leading, trailing,
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),
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

    private func populate(_ stack: UIStackView, context: AgentBlockRenderContext) {
        switch context.block.content {
        case .userText(let value):
            stack.addArrangedSubview(textView(value.text, context: context))
            for attachment in value.attachments {
                stack.addArrangedSubview(detailLabel("📎 \(attachment.name)", context: context))
            }

        case .markdown(let value):
            stack.addArrangedSubview(textView(value.markdown, context: context))

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
final class AgentDefaultBlockRenderer: AgentBlockRenderer {
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
}

private enum AgentMarkdownPlainTextRenderer {
    static func render(_ document: AgentMarkdownRenderDocument) -> String {
        document.blocks.map(render).joined(separator: "\n\n")
    }

    private static func render(_ block: AgentMarkdownRenderBlock) -> String {
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

    private static func inline(_ content: [AgentMarkdownInline]) -> String {
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
