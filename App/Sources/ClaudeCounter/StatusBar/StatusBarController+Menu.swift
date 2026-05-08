import AppKit

extension StatusBarController {
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(item("Open Usage Page", #selector(openWindow), key: "o"))
        menu.addItem(.separator())
        menu.addItem(item(
            "Launch at Login",
            #selector(toggleLogin),
            tag: MenuTag.login.rawValue
        ))
        menu.addItem(item("Refresh Now", #selector(refresh), key: "r"))
        menu.addItem(.separator())
        menu.addItem(item("Quit Claude Counter", #selector(quit), key: "q"))
        return menu
    }

    private func item(
        _ title: String,
        _ action: Selector,
        key: String = "",
        tag: Int = 0
    ) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        it.tag = tag
        return it
    }

    @objc func openWindow() { UsageWindow.shared.show() }

    @objc func refresh() { scraper.scrape() }

    @objc func quit() { NSApp.terminate(nil) }

    @objc func toggleLogin() {
        do {
            try LoginItemManager.setEnabled(!LoginItemManager.isEnabled)
        } catch {
            NSLog("[LoginItem] Failed: \(error.localizedDescription)")
        }
    }

    enum MenuTag: Int { case login = 1 }
}

extension StatusBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if let it = menu.item(withTag: MenuTag.login.rawValue) {
            it.state = LoginItemManager.isEnabled ? .on : .off
        }
    }
}
