import AgentChatKit
import UIKit

@MainActor
final class DemoWeatherRenderer: AgentTableBlockRenderer {
    let supportedKinds: Set<AgentBlockKind> = ["demo.weather"]

    func register(in collectionView: UICollectionView) {
        collectionView.register(
            UICollectionViewListCell.self,
            forCellWithReuseIdentifier: "DemoWeatherCell"
        )
    }

    func dequeueConfiguredCell(
        from collectionView: UICollectionView,
        at indexPath: IndexPath,
        context: AgentBlockRenderContext
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "DemoWeatherCell",
            for: indexPath
        )
        guard let listCell = cell as? UICollectionViewListCell,
            case .custom(let custom) = context.block.content
        else { return cell }
        var content = UIListContentConfiguration.subtitleCell()
        content.image = UIImage(systemName: "cloud.sun.fill")
        content.text = custom.fallbackTitle
        content.secondaryText = "18°C · Hangzhou · custom renderer"
        listCell.contentConfiguration = content
        listCell.backgroundConfiguration = UIBackgroundConfiguration.listPlainCell()
        listCell.accessibilityLabel = "\(custom.fallbackTitle), 18 degrees Celsius, Hangzhou"
        return listCell
    }

    func register(in tableView: UITableView) {
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "DemoTableWeatherCell")
    }

    func dequeueConfiguredCell(
        from tableView: UITableView,
        at indexPath: IndexPath,
        context: AgentBlockRenderContext
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "DemoTableWeatherCell",
            for: indexPath
        )
        guard case .custom(let custom) = context.block.content else { return cell }
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: "cloud.sun.fill")
        content.text = custom.fallbackTitle
        content.secondaryText = "18°C · Hangzhou · custom renderer"
        cell.contentConfiguration = content
        cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
        cell.selectionStyle = .none
        cell.accessibilityLabel = "\(custom.fallbackTitle), 18 degrees Celsius, Hangzhou"
        return cell
    }
}
