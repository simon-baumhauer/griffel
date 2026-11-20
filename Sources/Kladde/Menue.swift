import AppKit

/// Helfer für Menüs. Die Menüleiste selbst baut Befehlsmenue aus den Daten von Notepad++.
enum Menue {
    /// «Normaler Text» oben, darunter die Sprachen nach dem Anfangsbuchstaben in
    /// Untermenüs, wie im Menü «Sprache» von Notepad++. Jeder Aufruf baut neue
    /// Einträge (ein Eintrag gehört immer nur einem Menü).
    static func sprachEintraege() -> [NSMenuItem] {
        let alle = Sprachdaten.gemeinsam.sprachen.filter { $0.imMenue && !$0.istNormalerText }
        let gruppen = Dictionary(grouping: alle) { String($0.kurz.prefix(1)).uppercased() }
        var eintraege = [spracheEintrag(Sprachdaten.gemeinsam.normal, titel: "Normaler Text"), .separator()]
        for buchstabe in gruppen.keys.sorted() {
            let sprachen = gruppen[buchstabe]!.sorted { $0.kurz.localizedCaseInsensitiveCompare($1.kurz) == .orderedAscending }
            let kopf = NSMenuItem(title: buchstabe, action: nil, keyEquivalent: "")
            let unter = NSMenu(title: buchstabe)
            sprachen.map { spracheEintrag($0, titel: $0.kurz) }.forEach(unter.addItem)
            kopf.submenu = unter
            eintraege.append(kopf)
        }
        return eintraege
    }

    private static func spracheEintrag(_ sprache: Sprache, titel: String) -> NSMenuItem {
        let eintrag = NSMenuItem(title: titel, action: #selector(Dokument.spracheWaehlen(_:)), keyEquivalent: "")
        eintrag.representedObject = sprache.name
        eintrag.toolTip = sprache.lang
        return eintrag
    }

    /// Eine Funktionstaste (NSF1FunctionKey …) als Zeichen für keyEquivalent.
    static func taste(_ funktionstaste: Int) -> String {
        String(Character(Unicode.Scalar(UInt32(funktionstaste))!))
    }
}
