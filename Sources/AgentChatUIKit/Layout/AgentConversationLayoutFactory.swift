import UIKit

@MainActor
enum AgentConversationLayoutFactory {
    static func makeLayout(
        configuration: AgentTimelineLayoutConfiguration
    ) -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(configuration.estimatedItemHeight)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(configuration.estimatedItemHeight)
            )
            let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = configuration.blockSpacing
            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(28)
            )
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            section.boundarySupplementaryItems = [header]
            let width = environment.container.effectiveContentSize.width
            let sideInset = configuration.sideInset(for: width)
            section.contentInsets = NSDirectionalEdgeInsets(
                top: configuration.sectionTopInset,
                leading: sideInset,
                bottom: configuration.sectionBottomInset,
                trailing: sideInset
            )
            return section
        }
    }
}
