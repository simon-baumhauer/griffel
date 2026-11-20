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

    /// Leer: die Schrift des Farbschemas (wie in Notepad++, meist Courier New).
    static var schriftName: String {
        get { ablage.string(forKey: "Schrift") ?? "" }
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

    /// Symbole der Werkzeugleiste: «standard» (klassisch, Vorgabe von Notepad++ im
    /// hellen Modus), «fluent», «fluentGefuellt». Dunkel immer Fluent.
    static var symbolsatz: String {
        get { ablage.string(forKey: "Symbolsatz") ?? "standard" }
        set { ablage.set(newValue, forKey: "Symbolsatz"); melde() }
    }

    /// Zeichen am Ende umgebrochener Zeilen (Symbole anzeigen → Umbruchsymbol).
    static var umbruchSymbol: Bool {
        get { ablage.bool(forKey: "UmbruchSymbol") }
        set { ablage.set(newValue, forKey: "UmbruchSymbol"); melde() }
    }

    static var dokumentenlisteSichtbar: Bool {
        get { ablage.bool(forKey: "DokumentenlisteSichtbar") }
        set { ablage.set(newValue, forKey: "DokumentenlisteSichtbar"); melde() }
    }

    static var jsonViewerSichtbar: Bool {
        get { ablage.bool(forKey: "JSONViewerSichtbar") }
        set { ablage.set(newValue, forKey: "JSONViewerSichtbar"); melde() }
    }

    static var miniaturansichtSichtbar: Bool {
        get { ablage.bool(forKey: "MiniaturansichtSichtbar") }
        set { ablage.set(newValue, forKey: "MiniaturansichtSichtbar"); melde() }
    }

    static var arbeitsbereichSichtbar: Bool {
        get { ablage.bool(forKey: "ArbeitsbereichSichtbar") }
        set { ablage.set(newValue, forKey: "ArbeitsbereichSichtbar"); melde() }
    }

    /// Ordner in «Ordner als Arbeitsbereich».
    static var arbeitsbereichOrdner: [String] {
        get { ablage.stringArray(forKey: "ArbeitsbereichOrdner") ?? [] }
        set { ablage.set(newValue, forKey: "ArbeitsbereichOrdner"); melde() }
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

    private static func schalter(_ k: String, _ vorgabe: Bool) -> Bool { ablage.object(forKey: k) as? Bool ?? vorgabe }
    private static func setze(_ k: String, _ w: Any) { ablage.set(w, forKey: k); melde() }

    // MARK: Dateireiter (Tabs) — Vorgaben wie _tabStatus in Notepad++ (Parameters.h)

    static var tabsAusblenden: Bool { get { schalter("TabsAusblenden", false) } set { setze("TabsAusblenden", newValue) } }
    static var tabsSperren: Bool { get { schalter("TabsSperren", false) } set { setze("TabsSperren", newValue) } }
    static var tabDoppelklickSchliesst: Bool { get { schalter("TabDoppelklick", false) } set { setze("TabDoppelklick", newValue) } }
    static var letzterTabBeendet: Bool { get { schalter("LetzterTabBeendet", false) } set { setze("LetzterTabBeendet", newValue) } }
    /// Höchstens so viele Zeichen im Tab-Namen; 0 heisst unbegrenzt.
    static var tabNameMax: Int {
        get { min(max(ablage.integer(forKey: "TabNameMax"), 0), 200) }
        set { setze("TabNameMax", newValue) }
    }
    static var tabsVerkleinert: Bool { get { schalter("TabsVerkleinert", true) } set { setze("TabsVerkleinert", newValue) } }
    static var tabAlternativeSymbole: Bool { get { schalter("TabAltSymbole", false) } set { setze("TabAltSymbole", newValue) } }
    static var tabInaktivFarbe: Bool { get { schalter("TabInaktivFarbe", true) } set { setze("TabInaktivFarbe", newValue) } }
    static var tabBalken: Bool { get { schalter("TabBalken", true) } set { setze("TabBalken", newValue) } }
    static var tabSchliessen: Bool { get { schalter("TabSchliessen", true) } set { setze("TabSchliessen", newValue) } }
    static var tabPin: Bool { get { schalter("TabPin", true) } set { setze("TabPin", newValue) } }
    static var tabNurAngeheftete: Bool { get { schalter("TabNurAngeheftete", false) } set { setze("TabNurAngeheftete", newValue) } }
    static var tabKnoepfeInaktiv: Bool { get { schalter("TabKnoepfeInaktiv", false) } set { setze("TabKnoepfeInaktiv", newValue) } }

    private static func zahl(_ k: String, _ vorgabe: Int, _ b: ClosedRange<Int>) -> Int {
        min(max(ablage.object(forKey: k) as? Int ?? vorgabe, b.lowerBound), b.upperBound)
    }

    // MARK: Bearbeiten 1 und 2 (Vorgaben aus Parameters.h)

    /// Anzeige der aktuellen Zeile: 0 keine, 1 Hintergrund hervorheben, 2 Rahmen.
    static var aktuelleZeile: Int { get { zahl("AktuelleZeile", 1, 0...2) } set { setze("AktuelleZeile", newValue) } }
    static var aktuelleZeileRahmen: Int { get { zahl("AktuelleZeileRahmen", 1, 1...6) } set { setze("AktuelleZeileRahmen", newValue) } }
    /// Cursorbreite 0–3, 4 = Block.
    static var cursorBreite: Int { get { zahl("CursorBreite", 1, 0...4) } set { setze("CursorBreite", newValue) } }
    /// Blinkfrequenz in Millisekunden (50 schnell … 2500 langsam).
    static var cursorBlinken: Int { get { zahl("CursorBlinken", 600, 50...2500) } set { setze("CursorBlinken", newValue) } }
    /// Zeilenumbruch: 0 Standard, 1 Ausgerichtet, 2 Eingerückt.
    static var umbruchArt: Int { get { zahl("UmbruchArt", 1, 0...2) } set { setze("UmbruchArt", newValue) } }
    static var virtuellerRaum: Bool { get { schalter("VirtuellerRaum", false) } set { setze("VirtuellerRaum", newValue) } }
    static var zeileOhneAuswahl: Bool { get { schalter("ZeileOhneAuswahl", true) } set { setze("ZeileOhneAuswahl", newValue) } }
    static var ueberLetzteZeile: Bool { get { schalter("UeberLetzteZeile", true) } set { setze("UeberLetzteZeile", newValue) } }
    static var mehrfachBearbeitung: Bool { get { schalter("MehrfachBearbeitung", true) } set { setze("MehrfachBearbeitung", newValue) } }

    // MARK: Dunkler Modus

    /// 0 heller Modus, 1 dunkler Modus, 2 wie macOS.
    static var modus: Int { get { zahl("Modus", 2, 0...2) } set { setze("Modus", newValue) } }

    // MARK: Ränder/Rahmen/Umrandung

    /// Faltungsstil: 0 einfach, 1 Pfeile, 2 Kreise, 3 Kästchen, 4 kein.
    static var faltStil: Int { get { zahl("FaltStil", 3, 0...4) } set { setze("FaltStil", newValue) } }
    /// Spalten für senkrechte Kanten, durch Leerzeichen getrennt (etwa «80 120»).
    static var kanten: String { get { ablage.string(forKey: "Kanten") ?? "" } set { setze("Kanten", newValue) } }
    static var kanteHintergrund: Bool { get { schalter("KanteHintergrund", false) } set { setze("KanteHintergrund", newValue) } }
    static var aenderungenAmRand: Bool { get { schalter("AenderungenRand", true) } set { setze("AenderungenRand", newValue) } }
    static var aenderungenImText: Bool { get { schalter("AenderungenText", false) } set { setze("AenderungenText", newValue) } }
    static var zeilennummernDynamisch: Bool { get { schalter("ZeilennummernDynamisch", true) } set { setze("ZeilennummernDynamisch", newValue) } }
    static var randLinks: Int { get { zahl("RandLinks", 0, 0...9) } set { setze("RandLinks", newValue) } }
    static var randRechts: Int { get { zahl("RandRechts", 0, 0...9) } set { setze("RandRechts", newValue) } }
    static var lesezeichenRand: Bool { get { schalter("LesezeichenRand", true) } set { setze("LesezeichenRand", newValue) } }

    // MARK: Neues Dokument

    /// 0 Windows (CR LF), 1 Unix (LF), 2 Macintosh (CR). Auf dem Mac LF statt CR LF.
    static var neuZeilenende: Int { get { zahl("NeuZeilenende", 1, 0...2) } set { setze("NeuZeilenende", newValue) } }
    /// 0 ANSI, 1 UTF-8, 2 UTF-8 mit BOM, 3 UTF-16 BE, 4 UTF-16 LE.
    static var neuKodierung: Int { get { zahl("NeuKodierung", 1, 0...4) } set { setze("NeuKodierung", newValue) } }
    /// Name der Sprache neuer Dokumente; leer heisst «Normaler Text».
    static var neuSprache: String { get { ablage.string(forKey: "NeuSprache") ?? "" } set { setze("NeuSprache", newValue) } }

    // MARK: Einrückung, Hervorhebung, Suche, Sicherung, Autovervollständigung, Diverses

    static var rueckLoeschtEinzug: Bool { get { schalter("RueckLoeschtEinzug", false) } set { setze("RueckLoeschtEinzug", newValue) } }
    /// Automatische Einrückung: 0 keine, 1 normal, 2 erweitert (Vorgabe).
    static var autoEinzugArt: Int {
        get { autoEinzug ? zahl("AutoEinzugArt", 2, 1...2) : 0 }
        set { ablage.set(max(newValue, 1), forKey: "AutoEinzugArt"); autoEinzug = newValue > 0 }
    }
    static var smartGrossKlein: Bool { get { schalter("SmartGrossKlein", false) } set { setze("SmartGrossKlein", newValue) } }
    static var smartGanzesWort: Bool { get { schalter("SmartGanzesWort", true) } set { setze("SmartGanzesWort", newValue) } }
    static var suchfeldAusAuswahl: Bool { get { schalter("SuchfeldAusAuswahl", true) } set { setze("SuchfeldAusAuswahl", newValue) } }
    static var suchenFestbreite: Bool { get { schalter("SuchenFestbreite", false) } set { setze("SuchenFestbreite", newValue) } }
    static var zwischensicherung: Bool { get { schalter("Zwischensicherung", true) } set { setze("Zwischensicherung", newValue) } }
    static var zwischensicherungSekunden: Int { get { zahl("ZwischensicherungSekunden", 7, 1...3600) } set { setze("ZwischensicherungSekunden", newValue) } }
    static var vervollstaendigenAn: Bool { get { schalter("VervollstaendigenAn", vervollstaendigenAb > 0) } set { setze("VervollstaendigenAn", newValue) } }
    /// 0 Funktionen, 1 Wörter, 2 beides.
    static var vervollstaendigenArt: Int { get { zahl("VervollstaendigenArt", 2, 0...2) } set { setze("VervollstaendigenArt", newValue) } }
    static var aufrufhilfeAn: Bool { get { schalter("AufrufhilfeAn", true) } set { setze("AufrufhilfeAn", newValue) } }
    /// Welche Zeichen sich selbst schliessen: ( [ { " '.
    static func schliesst(_ zeichen: Character) -> Bool { schalter("Schliesst\(zeichen.unicodeScalars.first!.value)", klammernSchliessen) }
    static func setzeSchliesst(_ zeichen: Character, _ an: Bool) { setze("Schliesst\(zeichen.unicodeScalars.first!.value)", an) }
    static var kurzerTitel: Bool { get { schalter("KurzerTitel", false) } set { setze("KurzerTitel", newValue) } }

    // MARK: Symbolleiste und Statusleiste

    static var symbolleisteAusblenden: Bool { get { schalter("SymbolleisteAusblenden", false) } set { setze("SymbolleisteAusblenden", newValue) } }
    static var statusleisteAusblenden: Bool { get { schalter("StatusleisteAusblenden", false) } set { setze("StatusleisteAusblenden", newValue) } }
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
