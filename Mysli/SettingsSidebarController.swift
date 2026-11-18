import Cocoa

@MainActor
final class SettingsSidebarController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let tableView: NSTableView
    let searchField = NSSearchField()
    var catalog: [SettingsSearchDestination] = []
    private var rows = SettingsPage.allCases.map(SettingsSidebarRow.page)
    private var selectedPage: SettingsPage = .general
    private var reloading = false
    private let resultStatus = SettingsLayout.label("", size: 11, secondary: true)
    private(set) var isSearching = false
    var resultItems: [SettingsSearchItem] { rows.compactMap(\.item) }
    var onSelect: ((SettingsSidebarRow) -> Void)?
    var onSearchChanged: (() -> Void)?

    init() {
        let navigationTable = SettingsNavigationTable()
        tableView = navigationTable
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
        tableView.target = self
        tableView.action = #selector(activateResult)
        navigationTable.onReturn = { [weak self] in
            self?.handle(#selector(NSResponder.insertNewline(_:))) ?? false
        }
        searchField.placeholderString = "Search Settings"
        searchField.setAccessibilityLabel("Search Settings")
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.maximumRecents = 0
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(refreshSearchResults)
        resultStatus.isHidden = true
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let header = Self.brandHeader()
        let search = SettingsLayout.stack([searchField, resultStatus], spacing: 8)
        searchField.widthAnchor.constraint(equalTo: search.widthAnchor).isActive = true
        resultStatus.widthAnchor.constraint(equalTo: search.widthAnchor).isActive = true
        for child in [header, search, scroll] {
            child.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(child)
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            search.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            search.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        tableView.reloadData()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func select(_ page: SettingsPage) {
        selectedPage = page
        guard !isSearching else { return }
        guard tableView.selectedRow != page.rawValue else { return }
        tableView.selectRowIndexes(IndexSet(integer: page.rawValue), byExtendingSelection: false)
        tableView.scrollRowToVisible(page.rawValue)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !reloading else { return }
        let row = tableView.selectedRow
        guard rows.indices.contains(row), case .page = rows[row] else { return }
        onSelect?(rows[row])
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = rows[row].item
        let identifier = NSUserInterfaceItemIdentifier(item == nil ? "pageCell" : "searchCell")
        let cell: SettingsNavigationCell
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? SettingsNavigationCell {
            cell = reused
        } else {
            cell = SettingsNavigationCell()
            cell.identifier = identifier
            let icon = NSImageView()
            icon.setAccessibilityElement(false)
            let label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: NSFont.systemFontSize)
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            cell.imageView = icon
            cell.textField = label
            let copy = SettingsLayout.stack([label], spacing: 2)
            if item != nil {
                let pageName = cell.pageLabel
                pageName.font = .systemFont(ofSize: 11)
                pageName.textColor = .secondaryLabelColor
                pageName.lineBreakMode = .byTruncatingTail
                SettingsLayout.add(pageName, to: copy)
            }
            label.widthAnchor.constraint(equalTo: copy.widthAnchor).isActive = true
            for child in [icon, copy] {
                child.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(child)
            }
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 20),
                icon.heightAnchor.constraint(equalToConstant: 20),
                copy.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                copy.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                copy.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        let page = rows[row].page
        cell.imageView?.image = page.icon(size: 20)
        cell.textField?.stringValue = item?.title ?? page.title
        if let item {
            cell.pageLabel.stringValue = switch item.kind {
            case .setting: page.title
            case .page: "Settings page"
            case .guide: "\(page.title) · Guide"
            }
            cell.toolTip = "\(page.title) > \(item.title)"
            cell.setAccessibilityLabel("\(item.title), \(cell.pageLabel.stringValue)")
        }
        return cell
    }

    func clearSearch() {
        guard isSearching || !searchField.stringValue.isEmpty else { return }
        searchField.stringValue = ""
        refreshSearchResults()
    }

    @objc func refreshSearchResults() {
        let searching = !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let available = catalog.filter { $0.isAvailable() }
        let results = SettingsSearch.matches(searchField.stringValue, in: available.map(\.item)).map { available[$0] }
        let nextRows = searching ? results.map(SettingsSidebarRow.result) : SettingsPage.allCases.map(SettingsSidebarRow.page)
        reloading = true
        tableView.allowsEmptySelection = true
        tableView.deselectAll(nil)
        tableView.rowSizeStyle = searching ? .custom : .medium
        tableView.rowHeight = searching ? 46 : 24
        isSearching = searching
        rows = nextRows
        tableView.reloadData()
        tableView.setAccessibilityLabel(isSearching ? "Settings search results" : "Settings pages")
        let row = isSearching ? (rows.isEmpty ? nil : 0) : selectedPage.rawValue
        if let row {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        }
        tableView.allowsEmptySelection = isSearching
        resultStatus.isHidden = !isSearching
        resultStatus.stringValue = rows.isEmpty ? "No results. Try another word."
            : "\(rows.count) \(rows.count == 1 ? "result" : "results")"
        reloading = false
        onSearchChanged?()
        NSAccessibility.post(element: tableView, notification: .layoutChanged)
    }

    @objc private func activateResult() {
        let row = tableView.selectedRow
        guard rows.indices.contains(row), case .result = rows[row] else { return }
        onSelect?(rows[row])
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        handle(commandSelector)
    }

    private func handle(_ command: Selector) -> Bool {
        guard isSearching else { return false }
        switch command {
        case #selector(NSResponder.insertNewline(_:)):
            activateResult()
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveUp(_:)):
            guard !rows.isEmpty else { return true }
            let step = command == #selector(NSResponder.moveDown(_:)) ? 1 : -1
            let row = min(max(tableView.selectedRow + step, 0), rows.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        default: return false
        }
        return true
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

@MainActor
enum SettingsSidebarRow {
    case page(SettingsPage)
    case result(SettingsSearchDestination)

    var page: SettingsPage {
        switch self {
        case .page(let page): page
        case .result(let destination): destination.item.page
        }
    }

    var item: SettingsSearchItem? {
        guard case .result(let destination) = self else { return nil }
        return destination.item
    }
}

private final class SettingsNavigationCell: NSTableCellView {
    let pageLabel = NSTextField(labelWithString: "")
}

private final class SettingsNavigationTable: NSTableView {
    var onReturn: (() -> Bool)?

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers
        if (key == "\r" || key == "\u{3}"), onReturn?() == true { return }
        super.keyDown(with: event)
    }
}
