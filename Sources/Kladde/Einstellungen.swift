import AppKit

/// Einstellungen der Darstellung, für alle Fenster gleich. Wer sie ändert,
/// meldet es mit `geaendert`; jeder Editor richtet sich dann neu ein.
enum Einstellungen {
    static let geaendert = Notification.Name("KladdeDarstellungGeaendert")

    private static let ablage = UserDefaults.standard

    /// Name eines Farbschemas, oder leer: «Standard» bei hellem, «DarkModeDefault»
    /// bei dunklem macOS.
    static var farbschema: String {
        get { ablage.string(forKey: "Farbschema") ?? "" }
        set { ablage.set(newValue, forKey: "Farbschema"); melde() }
    }

    static var leerzeichenZeigen: Bool {
        get { ablage.bool(forKey: "LeerzeichenZeigen") }
        set { ablage.set(newValue, forKey: "LeerzeichenZeigen"); melde() }
    }

    static var zeilenendenZeigen: Bool {
        get { ablage.bool(forKey: "ZeilenendenZeigen") }
        set { ablage.set(newValue, forKey: "ZeilenendenZeigen"); melde() }
    }

    /// Senkrechte Linien je Einrückungsstufe; wie in Notepad++ von Anfang an an.
    static var einrueckungshilfen: Bool {
        get { ablage.object(forKey: "Einrueckungshilfen") as? Bool ?? true }
        set { ablage.set(newValue, forKey: "Einrueckungshilfen"); melde() }
    }

    static func schemaName(fuer erscheinung: NSAppearance) -> String {
        if !farbschema.isEmpty { return farbschema }
        return erscheinung.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "DarkModeDefault" : "Standard"
    }

    private static func melde() {
        NotificationCenter.default.post(name: geaendert, object: nil)
    }
}

/// Ziel der Menüeinträge, die für alle Fenster gelten (Farbschema, Symbole).
final class DarstellungsMenue: NSObject, NSMenuItemValidation {
    static let gemeinsam = DarstellungsMenue()

    @objc func farbschemaWaehlen(_ sender: NSMenuItem) {
        Einstellungen.farbschema = sender.representedObject as? String ?? ""
    }

    @objc func leerzeichenUmschalten(_ sender: Any?) { Einstellungen.leerzeichenZeigen.toggle() }
    @objc func zeilenendenUmschalten(_ sender: Any?) { Einstellungen.zeilenendenZeigen.toggle() }
    @objc func einrueckungshilfenUmschalten(_ sender: Any?) { Einstellungen.einrueckungshilfen.toggle() }

    /// Wie «Alle Zeichen anzeigen» in Notepad++: beides an, oder beides aus.
    @objc func alleZeichenUmschalten(_ sender: Any?) {
        let an = !(Einstellungen.leerzeichenZeigen && Einstellungen.zeilenendenZeigen)
        Einstellungen.leerzeichenZeigen = an
        Einstellungen.zeilenendenZeigen = an
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let an: Bool
        switch menuItem.action {
        case #selector(farbschemaWaehlen(_:)):
            an = (menuItem.representedObject as? String ?? "") == Einstellungen.farbschema
        case #selector(leerzeichenUmschalten(_:)):
            an = Einstellungen.leerzeichenZeigen
        case #selector(zeilenendenUmschalten(_:)):
            an = Einstellungen.zeilenendenZeigen
        case #selector(alleZeichenUmschalten(_:)):
            an = Einstellungen.leerzeichenZeigen && Einstellungen.zeilenendenZeigen
        case #selector(einrueckungshilfenUmschalten(_:)):
            an = Einstellungen.einrueckungshilfen
        default:
            return true
        }
        menuItem.state = an ? .on : .off
        return true
    }
}
