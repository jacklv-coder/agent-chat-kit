import UIKit

@MainActor
struct AgentTimelineLayoutConfiguration {
    var compactSideInset: CGFloat
    var maximumContentWidth: CGFloat
    var blockSpacing: CGFloat
    var sectionTopInset: CGFloat
    var sectionBottomInset: CGFloat
    var estimatedItemHeight: CGFloat

    func sideInset(for width: CGFloat) -> CGFloat {
        max(compactSideInset, (width - maximumContentWidth) / 2)
    }
}
