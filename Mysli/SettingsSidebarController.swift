import Cocoa

@MainActor
final class SettingsSidebarController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    let tableView = NSTableView()
    var onSelect: ((SettingsPage) -> Void)?

    init() {
        super.init(nibName: nil, bundle: nil)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 210, height: 700))
        view = root
        tableView.style = .sourceList
        tableView.rowSizeStyle = .medium
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.allowsEmptySelection = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.setAccessibilityLabel("Settings pages")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page"))
        tableView.addTableColumn(column)
        tableView.dataSource = self
        tableView.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let header = Self.brandHeader()
        for child in [header, scroll] {
            child.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(child)
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        tableView.reloadData()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func select(_ page: SettingsPage) {
        guard tableView.selectedRow != page.rawValue else { return }
        tableView.selectRowIndexes(IndexSet(integer: page.rawValue), byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { SettingsPage.allCases.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard SettingsPage.allCases.indices.contains(row) else { return }
        onSelect?(SettingsPage.allCases[row])
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("pageCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let icon = NSImageView()
            icon.setAccessibilityElement(false)
            let label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: NSFont.systemFontSize)
            cell.imageView = icon
            cell.textField = label
            for child in [icon, label] {
                child.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(child)
            }
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 20),
                icon.heightAnchor.constraint(equalToConstant: 20),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        let page = SettingsPage.allCases[row]
        cell.imageView?.image = page.icon(size: 20)
        cell.textField?.stringValue = page.title
        return cell
    }

    private static func brandHeader() -> NSView {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.setAccessibilityElement(false)
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let name = SettingsLayout.label("Mysli", size: 15)
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        let words = SettingsLayout.stack(spacing: 2)
        SettingsLayout.add(name, to: words)
        SettingsLayout.add(SettingsLayout.label("A daily mix of Mac tools", size: 11, secondary: true), to: words)
        words.setHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [icon, words])
        header.distribution = .fill
        header.alignment = .centerY
        header.spacing = 10
        return header
    }
}
