import AgentChatKit
import UIKit

struct DemoImageProvider: AgentImageProviding {
    func image(
        for reference: AgentResourceReference,
        targetSize: CGSize,
        scale: CGFloat
    ) async throws -> UIImage {
        try Task.checkCancellation()
        return await MainActor.run {
            Self.renderPreview(reference: reference, targetSize: targetSize, scale: scale)
        }
    }

    @MainActor
    private static func renderPreview(
        reference: AgentResourceReference,
        targetSize: CGSize,
        scale: CGFloat
    ) -> UIImage {
        let pixelWidth = max(targetSize.width * max(scale, 1), 640)
        let size = CGSize(width: pixelWidth, height: pixelWidth * 0.68)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemBackground.setFill()
            context.fill(.init(origin: .zero, size: size))

            let margin = size.width * 0.055
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size.width * 0.045, weight: .bold),
                .foregroundColor: UIColor.label,
            ]
            NSString(string: "AgentChatKit · Image Detail").draw(
                at: .init(x: margin, y: margin),
                withAttributes: titleAttributes
            )

            let subtitle: String
            switch reference {
            case .localIdentifier(let identifier):
                subtitle = identifier
            case .remoteURL(let url):
                subtitle = url.lastPathComponent
            case .runtimeURI(let uri):
                subtitle = uri
            }
            NSString(string: subtitle).draw(
                at: .init(x: margin, y: margin * 2.2),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(
                        ofSize: size.width * 0.019,
                        weight: .regular
                    ),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            )

            let cardRect = CGRect(
                x: margin,
                y: size.height * 0.31,
                width: size.width - margin * 2,
                height: size.height * 0.55
            )
            UIColor.secondarySystemBackground.setFill()
            UIBezierPath(roundedRect: cardRect, cornerRadius: size.width * 0.025).fill()

            let rows = [
                ("terminal", "Ran xcodebuild …"),
                ("photo.on.rectangle", "Viewed 1 image"),
                ("pencil", "Edited DemoScenario.swift"),
                ("wrench", "Read Computer Use skill"),
            ]
            let rowHeight = cardRect.height / CGFloat(rows.count)
            for (index, row) in rows.enumerated() {
                let rowY = cardRect.minY + CGFloat(index) * rowHeight
                let iconRect = CGRect(
                    x: cardRect.minX + margin * 0.55,
                    y: rowY + rowHeight * 0.32,
                    width: rowHeight * 0.28,
                    height: rowHeight * 0.28
                )
                UIImage(systemName: row.0)?
                    .withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
                    .draw(in: iconRect)
                NSString(string: row.1).draw(
                    at: .init(x: iconRect.maxX + margin * 0.35, y: rowY + rowHeight * 0.3),
                    withAttributes: [
                        .font: UIFont.systemFont(
                            ofSize: size.width * 0.027,
                            weight: .medium
                        ),
                        .foregroundColor: UIColor.secondaryLabel,
                    ]
                )
            }
        }
    }
}
