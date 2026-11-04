import XCTest
@testable import Mysli

@MainActor
final class EnabledMenuSectionTests: XCTestCase {
    func testGroupStartsDisabledAndKeepsItsOwnHiddenItemsWhenEnabled() {
        let menu = NSMenu()
        let content = VisibilityTestSection()
        content.item.isHidden = true
        var enabled = false
        let section = EnabledMenuSection(content, isEnabled: { enabled })
        section.buildMenuSection(into: menu)
        XCTAssertNil(content.item.menu)
        enabled = true
        section.menuWillOpen()
        XCTAssertTrue(content.item.menu === menu)
        XCTAssertTrue(content.item.isHidden)
    }

    func testDisabledGroupStaysOutOfTheMenuEvenWhenItsItemsChange() {
        let menu = NSMenu()
        let content = VisibilityTestSection()
        var enabled = true
        let section = EnabledMenuSection(content, isEnabled: { enabled })
        section.buildMenuSection(into: menu)
        let footer = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        menu.addItem(footer)
        XCTAssertTrue(content.item.menu === menu)

        enabled = false
        section.menuWillOpen()
        content.item.isHidden = false
        XCTAssertNil(content.item.menu)
        section.menuTick()
        XCTAssertEqual(content.ticks, 0)

        enabled = true
        section.menuWillOpen()
        XCTAssertTrue(content.item.menu === menu)
        XCTAssertLessThan(menu.index(of: content.item), menu.index(of: footer))
        section.menuTick()
        XCTAssertEqual(content.ticks, 1)
    }
}

@MainActor
private final class VisibilityTestSection: MenuSection {
    let item = NSMenuItem(title: "Tool action", action: nil, keyEquivalent: "")
    var ticks = 0
    func buildMenuSection(into menu: NSMenu) { menu.addItem(item) }
    func menuWillOpen() {}
    func menuTick() { ticks += 1 }
}
