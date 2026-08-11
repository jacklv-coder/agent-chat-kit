import AgentChatKit
import UIKit

@MainActor
final class DemoImagePreviewViewController: UIViewController, UIScrollViewDelegate {
    private let reference: AgentResourceReference
    private let alternativeText: String
    private let provider: any AgentImageProviding
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()
    private var loadTask: Task<Void, Never>?

    init(
        reference: AgentResourceReference,
        alternativeText: String,
        provider: any AgentImageProviding
    ) {
        self.reference = reference
        self.alternativeText = alternativeText
        self.provider = provider
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit { loadTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = alternativeText
        view.backgroundColor = .black
        navigationController?.navigationBar.tintColor = .white
        navigationController?.navigationBar.barStyle = .black
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closePreview)
        )

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.backgroundColor = .black
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.accessibilityIdentifier = "DemoFullScreenImagePreview"
        imageView.accessibilityLabel = alternativeText
        imageView.isAccessibilityElement = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)

        activityIndicator.color = .white
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)

        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            imageView.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        loadImage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    private func loadImage() {
        activityIndicator.startAnimating()
        messageLabel.text = nil
        let size = CGSize(width: 1_600, height: 1_200)
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await provider.image(
                    for: reference,
                    targetSize: size,
                    scale: UIScreen.main.scale
                )
                try Task.checkCancellation()
                imageView.image = image
                activityIndicator.stopAnimating()
            } catch is CancellationError {
                return
            } catch {
                activityIndicator.stopAnimating()
                messageLabel.text = "Image unavailable"
            }
        }
    }

    @objc private func closePreview() { dismiss(animated: true) }
}
