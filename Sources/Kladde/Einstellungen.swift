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

    // MARK: Schrift und Text

    static var schriftName: String {
        get { ablage.string(forKey: "Schrift") ?? "Menlo" }
        set { ablage.set(newValue, forKey: "Schrift"); melde() }
    }

    static var schriftGroesse: Int {
        get { (ablage.object(forKey: "Schriftgroesse") as? Int).map { min(max($0, 6), 72) } ?? 13 }
        set { ablage.set(newValue, forKey: "Schriftgroesse"); melde() }
    }

    static var tabbreite: Int {
        get { (ablage.object(forKey: "Tabbreite") as? Int).map { min(max($0, 1), 16) } ?? 4 }
        set { ablage.set(newValue, forKey: "Tabbreite"); melde() }
    }

    /// Tab-Taste fügt Leerzeichen ein (Notepad++: «Replace by space»).
    static var tabsAlsLeerzeichen: Bool {
        get { ablage.bool(forKey: "TabsAlsLeerzeichen") }
        set { ablage.set(newValue, forKey: "TabsAlsLeerzeichen"); melde() }
    }

    static var zeilennummern: Bool {
        get { ablage.object(forKey: "Zeilennummern") as? Bool ?? true }
        set { ablage.set(newValue, forKey: "Zeilennummern"); melde() }
    }

    /// Neue Zeilen erben die Einrückung der vorherigen; wie in Notepad++ an.
    static var autoEinzug: Bool {
        get { ablage.object(forKey: "AutoEinzug") as? Bool ?? true }
        set { ablage.set(newValue, forKey: "AutoEinzug"); melde() }
    }

    /// ( [ { " ' schliessen sich selbst; wie in Notepad++ aus.
    static var klammernSchliessen: Bool {
        get { ablage.bool(forKey: "KlammernSchliessen") }
        set { ablage.set(newValue, forKey: "KlammernSchliessen"); melde() }
    }

    static var smartHighlighting: Bool {
        get { ablage.object(forKey: "SmartHighlighting") as? Bool ?? true }
        set { ablage.set(newValue, forKey: "SmartHighlighting"); melde() }
    }

    /// Wörter und Funktionen vorschlagen, ab so vielen Zeichen; 0 heisst aus.
    static var vervollstaendigenAb: Int {
        get { (ablage.object(forKey: "VervollstaendigenAb") as? Int).map { min(max($0, 0), 9) } ?? 1 }
        set { ablage.set(newValue, forKey: "VervollstaendigenAb"); melde() }
    }

    /// Die Funktionsliste rechts im Fenster.
    static var funktionslisteSichtbar: Bool {
        get { ablage.bool(forKey: "FunktionslisteSichtbar") }
        set { ablage.set(newValue, forKey: "FunktionslisteSichtbar"); melde() }
    }

    /// Beim Beenden die Tabs merken und beim Start wieder öffnen.
    static var sitzungMerken: Bool {
        get { ablage.object(forKey: "SitzungMerken") as? Bool ?? true }
        set { ablage.set(newValue, forKey: "SitzungMerken"); melde() }
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
