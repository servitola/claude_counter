import AppKit

extension StatusBarController {
    enum MenuTag: Int { case login = 1 }

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
    )
        -> NSMenuItem
    {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        menuItem.tag = tag
        return menuItem
    }

    @objc func openWindow() {
        UsageWindow.shared.show()
    }

    @objc func refresh() {
        scraper.scrape()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    @objc func toggleLogin() {
        do {
            try LoginItemManager.setEnabled(!LoginItemManager.isEnabled)
        } catch {
            AppLog.loginItem.error(
                "Toggle failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

// MARK: - StatusBarController + NSMenuDelegate

extension StatusBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if let menuItem = menu.item(withTag: MenuTag.login.rawValue) {
            menuItem.state = LoginItemManager.isEnabled ? .on : .off
        }
    }
}
