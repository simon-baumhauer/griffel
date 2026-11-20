import Foundation

/// Der Filter von «In Dateien suchen» in Notepad++: Muster durch Leerzeichen
/// oder «;» getrennt. «*.swift *.md» nimmt nur diese, «!*.min.js» lässt Dateien
/// aus, «!\build» (oder «!+\build», «!/build») ganze Ordner, in jeder Tiefe.
/// Leer oder «*.*»: alle Dateien.
public struct Dateifilter: Equatable {
    public let einschliessen: [String]
    public let ausschliessen: [String]
    public let ordnerAus: [String]

    public init(_ text: String) {
        var ein: [String] = []
        var aus: [String] = []
        var ordner: [String] = []
        for teil in text.split(whereSeparator: { $0 == " " || $0 == ";" }).map(String.init) {
            if teil.hasPrefix("!") {
                var rest = String(teil.dropFirst())
                if rest.hasPrefix("+") { rest.removeFirst() }
                if rest.hasPrefix("\\") || rest.hasPrefix("/") {
                    ordner.append(String(rest.dropFirst()))
                } else if !rest.isEmpty {
                    aus.append(rest)
                }
            } else {
                ein.append(teil == "*.*" ? "*" : teil)
            }
        }
        einschliessen = ein
        ausschliessen = aus
        ordnerAus = ordner
    }

    public func nimmtDatei(_ name: String) -> Bool {
        if ausschliessen.contains(where: { Self.passt(name, $0) }) { return false }
        return einschliessen.isEmpty || einschliessen.contains { Self.passt(name, $0) }
    }

    public func nimmtOrdner(_ name: String) -> Bool {
        !ordnerAus.contains { Self.passt(name, $0) }
    }

    /// Wie unter Windows ohne Rücksicht auf Gross-/Kleinschreibung.
    static func passt(_ name: String, _ muster: String) -> Bool {
        fnmatch(muster, name, FNM_CASEFOLD) == 0
    }
}

/// Suchen und Ersetzen in allen Dateien eines Ordners. Läuft ohne Oberfläche;
/// die App ruft es im Hintergrund auf.
public struct Ordnersuche {
    public let ordner: URL
    public let filter: Dateifilter
    public let unterordner: Bool
    public let versteckte: Bool

    /// Grössere Dateien liest die Suche nicht.
    public static let hoechstensBytes = 64 * 1024 * 1024

    public init(ordner: URL, filter: Dateifilter, unterordner: Bool = true, versteckte: Bool = false) {
        // Aufgelöst, damit die Pfade der Dateien mit ihm beginnen (/tmp ist /private/tmp).
        self.ordner = ordner.resolvingSymlinksInPath()
        self.filter = filter
        self.unterordner = unterordner
        self.versteckte = versteckte
    }

    public struct Fund {
        public let url: URL
        public let text: Suchtext
        public let treffer: [Treffer]
    }

    public struct Stand: Equatable {
        public var geprueft = 0
        /// Zu gross, nicht lesbar oder binär.
        public var uebersprungen = 0
        public var dateienMitTreffern = 0
        public var treffer = 0
        public var abgebrochen = false
        public init() {}
    }

    /// Der Pfad einer gefundenen Datei ab dem Ordner, etwa «unter/c.txt».
    public func relativerPfad(_ url: URL) -> String {
        let basis = ordner.path.hasSuffix("/") ? ordner.path : ordner.path + "/"
        let pfad = url.resolvingSymlinksInPath().path
        return pfad.hasPrefix(basis) ? String(pfad.dropFirst(basis.count)) : pfad
    }

    /// Alle Dateien, die der Filter nimmt, nach Pfad sortiert.
    public func dateien() -> [URL] {
        let schluessel: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isHiddenKey, .isSymbolicLinkKey]
        guard
            let laeufer = FileManager.default.enumerator(
                at: ordner, includingPropertiesForKeys: schluessel,
                options: versteckte ? [] : [.skipsHiddenFiles])
        else { return [] }
        var liste: [URL] = []
        for case let url as URL in laeufer {
            let werte = try? url.resourceValues(forKeys: Set(schluessel))
            if werte?.isDirectory == true {
                if !unterordner || !filter.nimmtOrdner(url.lastPathComponent) { laeufer.skipDescendants() }
                continue
            }
            // Verknüpfungen nicht folgen: Sie führen leicht im Kreis oder aus dem Ordner.
            guard werte?.isRegularFile == true, werte?.isSymbolicLink != true else { continue }
            if filter.nimmtDatei(url.lastPathComponent) { liste.append(url) }
        }
        return liste.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Eine Datei als Text, oder nil, wenn sie zu gross oder binär ist.
    /// Binär heisst: ein Nullbyte in den ersten 8000 Bytes, ohne UTF-16-Marke.
    public static func lies(_ url: URL) -> Textdatei? {
        guard let groesse = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, groesse <= hoechstensBytes,
            let daten = try? Data(contentsOf: url)
        else { return nil }
        let utf16 = daten.starts(with: [0xFF, 0xFE]) || daten.starts(with: [0xFE, 0xFF])
        if !utf16, daten.prefix(8000).contains(0) { return nil }
        return Textdatei(daten: daten)
    }

    /// Geht die Dateien durch und meldet jede mit Treffern. `abbrechen` wird
    /// vor jeder Datei gefragt.
    public func durchsuche(
        _ muster: Suchmuster, abbrechen: () -> Bool = { false }, fund: (Fund) -> Void
    ) -> Stand {
        var stand = Stand()
        for url in dateien() {
            if abbrechen() {
                stand.abgebrochen = true
                break
            }
            stand.geprueft += 1
            guard let datei = Self.lies(url) else {
                stand.uebersprungen += 1
                continue
            }
            let text = Suchtext(utf8: datei.utf8)
            let treffer = muster.alle(in: text)
            guard !treffer.isEmpty else { continue }
            stand.dateienMitTreffern += 1
            stand.treffer += treffer.count
            fund(Fund(url: url, text: text, treffer: treffer))
        }
        return stand
    }

    /// Ersetzt in einer Datei auf der Platte, im Zeichensatz der Datei. Schreibt
    /// an Ort und Stelle (Rechte und Verknüpfungen bleiben) und nur bei Treffern.
    /// Antwort: wie viele Ersetzungen.
    @discardableResult
    public static func ersetze(in url: URL, mit muster: Suchmuster) throws -> Int {
        guard var datei = lies(url) else {
            throw Suchfehler(meldung: "\(url.lastPathComponent): zu gross oder keine Textdatei")
        }
        let (neu, anzahl) = muster.ersetzeAlle(in: Suchtext(utf8: datei.utf8))
        guard anzahl > 0 else { return 0 }
        datei.utf8 = neu
        try datei.kodiert().write(to: url)
        return anzahl
    }
}
