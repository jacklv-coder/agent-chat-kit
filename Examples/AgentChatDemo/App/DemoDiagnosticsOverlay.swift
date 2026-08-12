import AgentChatTesting
import UIKit

@MainActor
final class DemoDiagnosticsOverlay: UILabel {
    private let playbackController: AgentScenarioPlaybackController
    private weak var scrollView: UIScrollView?
    private var displayLink: CADisplayLink?
    private var refreshTimer: Timer?
    private var frameCount = 0
    private var framesPerSecond = 0
    private var lastFrameSample = CACurrentMediaTime()
    private var lastContentSize: CGSize = .zero
    private var contentSizeJumpCount = 0

    init(
        playbackController: AgentScenarioPlaybackController,
        scrollView: UIScrollView?
    ) {
        self.playbackController = playbackController
        self.scrollView = scrollView
        super.init(frame: .zero)
        font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        textColor = .label
        backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        layer.borderWidth = 1 / UIScreen.main.scale
        layer.borderColor = UIColor.separator.cgColor
        clipsToBounds = true
        textAlignment = .center
        numberOfLines = 1
        accessibilityIdentifier = "AgentChatDemoDiagnostics"
        directionalLayoutMargins = .init(top: 5, leading: 9, bottom: 5, trailing: 9)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isHidden: Bool {
        didSet { updateSamplingState() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateSamplingState()
    }

    override func drawText(in rect: CGRect) {
        super.drawText(
            in: rect.inset(
                by: UIEdgeInsets(
                    top: directionalLayoutMargins.top,
                    left: directionalLayoutMargins.leading,
                    bottom: directionalLayoutMargins.bottom,
                    right: directionalLayoutMargins.trailing
                )))
    }

    override var intrinsicContentSize: CGSize {
        let base = super.intrinsicContentSize
        return .init(
            width: base.width + directionalLayoutMargins.leading
                + directionalLayoutMargins.trailing,
            height: base.height + directionalLayoutMargins.top + directionalLayoutMargins.bottom
        )
    }

    private func startSampling() {
        let displayLink = CADisplayLink(target: self, selector: #selector(frameDidRender))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
        refreshTimer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(refresh),
            userInfo: nil,
            repeats: true
        )
        refresh()
    }

    private func updateSamplingState() {
        if window == nil || isHidden {
            stopSampling()
        } else if displayLink == nil {
            startSampling()
        }
    }

    private func stopSampling() {
        displayLink?.invalidate()
        displayLink = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @objc private func frameDidRender() {
        frameCount += 1
        let now = CACurrentMediaTime()
        let elapsed = now - lastFrameSample
        guard elapsed >= 0.5 else { return }
        framesPerSecond = Int((Double(frameCount) / elapsed).rounded())
        frameCount = 0
        lastFrameSample = now
    }

    @objc private func refresh() {
        if let scrollView {
            let contentSize = scrollView.contentSize
            let isInteracting = scrollView.isDragging || scrollView.isDecelerating
            if isInteracting, lastContentSize != .zero,
                abs(contentSize.height - lastContentSize.height) > 2
            {
                contentSizeJumpCount += 1
            }
            lastContentSize = contentSize
        }
        Task { [weak self, playbackController] in
            let state = await playbackController.state()
            guard let self else { return }
            let mode =
                state.isPaused
                ? "paused" : (state.rate == 0 ? "instant" : "\(state.rate.formatted())×")
            self.text =
                "FPS \(self.framesPerSecond) · events \(state.emittedEventCount) · jumps \(self.contentSizeJumpCount) · \(mode)"
            self.invalidateIntrinsicContentSize()
        }
    }
}
