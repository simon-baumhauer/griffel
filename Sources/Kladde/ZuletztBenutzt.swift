import AppKit

/// Das Untermenü «Zuletzt benutzt». Die Liste führt macOS
/// (NSDocumentController); gefüllt wird das Menü jedes Mal, wenn es aufgeht.
final class ZuletztBenutzt: NSObject, NSMenuDelegate {
    static let gemeinsam = ZuletztBenutzt()

    func menue() -> NSMenuItem {
        let eintrag = NSMenuItem(title: "Zuletzt benutzt", action: nil, keyEquivalent: "")
        let menue = NSMenu(title: "Zuletzt benutzt")
        menue.delegate = self
        eintrag.submenu = menue
        return eintrag
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let dateien = NSDocumentController.shared.recentDocumentURLs
        // Gleiche Namen aus verschiedenen Ordnern: der Ordner steht dahinter.
        let mehrfach = Dictionary(grouping: dateien, by: \.lastPathComponent).filter { $1.count > 1 }.keys
        for datei in dateien {
            var titel = datei.lastPathComponent
            if mehrfach.contains(titel) { titel += " — " + datei.deletingLastPathComponent().lastPathComponent }
            let eintrag = NSMenuItem(title: titel, action: #selector(oeffne(_:)), keyEquivalent: "")
            eintrag.target = self
            eintrag.representedObject = datei
            eintrag.toolTip = datei.path
            let bild = NSWorkspace.shared.icon(forFile: datei.path)
            bild.size = NSSize(width: 16, height: 16)
            eintrag.image = bild
            menu.addItem(eintrag)
        }
        if !dateien.isEmpty { menu.addItem(.separator()) }
        let leeren = NSMenuItem(
            title: "Einträge löschen", action: #selector(NSDocumentController.clearRecentDocuments(_:)),
            keyEquivalent: "")
        leeren.isEnabled = !dateien.isEmpty
        menu.addItem(leeren)
    }

    @objc private func oeffne(_ sender: NSMenuItem) {
        guard let datei = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: datei, display: true) { _, _, fehler in
            if let fehler { NSApp.presentError(fehler) }
        }
    }
}
