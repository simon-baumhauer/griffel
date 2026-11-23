import AppKit

/// Die Oberfläche von Notepad++ als Daten (scripts/oberflaeche.py): Menüs,
/// Kürzel, Tab-Kontextmenü, Suchen-Dialog und Texte der deutschen Fassung.
struct Oberflaeche: Decodable {
    struct Kuerzel: Decodable {
        let taste: String
        let ctrl: Bool
        let alt: Bool
        let shift: Bool
    }

    indirect enum Eintrag: Decodable {
        case befehl(id: String, titel: String, kuerzel: Kuerzel?, anders: String?)
        case untermenue(titel: String, kennung: String?, eintraege: [Eintrag])
        case trenner

        private enum Schluessel: String, CodingKey { case art, id, titel, kuerzel, anders, kennung, eintraege }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Schluessel.self)
            switch try c.decode(String.self, forKey: .art) {
            case "befehl":
                self = .befehl(
                    id: try c.decode(String.self, forKey: .id), titel: try c.decode(String.self, forKey: .titel),
                    kuerzel: try c.decodeIfPresent(Kuerzel.self, forKey: .kuerzel),
                    anders: try c.decodeIfPresent(String.self, forKey: .anders))
            case "untermenue":
                self = .untermenue(
                    titel: try c.decode(String.self, forKey: .titel),
                    kennung: try c.decodeIfPresent(String.self, forKey: .kennung),
                    eintraege: try c.decode([Eintrag].self, forKey: .eintraege))
            default:
                self = .trenner
            }
        }
    }

    struct Menue: Decodable {
        let titel: String
        let kennung: String?
        let eintraege: [Eintrag]
    }

    struct Element: Decodable {
        let art: String
        let id: String
        let text: String
        let x: Int
        let y: Int
        let b: Int
        let h: Int
        var stil: String? = nil
        var liste: [String]? = nil
    }

    /// Ein Dialog aus einer .rc-Datei von Notepad++ (Gehe zu, Ausführen, Block-Editor …).
    struct Dialog: Decodable {
        let titel: String
        let groesse: [Int]
        let elemente: [Element]
        /// Bei den Seiten von «Optionen»: der Name des Abschnitts in german.xml (Global, Tabbar …).
        var kennung: String? = nil
    }

    struct Suchen: Decodable {
        let titel: [String: String?]
        let groesse: [Int]
        let elemente: [Element]
    }

    let menues: [Menue]
    let tabmenue: [Eintrag]
    let suchen: Suchen
    var dialoge: [String: Dialog]?
    /// Die Seiten von «Optionen» in der Reihenfolge von Notepad++.
    var optionen: [Dialog]?

    /// Der deutsche Text eines Elements auf einer Seite von «Optionen».
    func optionenText(_ id: String, _ vorgabe: String) -> String {
        for seite in optionen ?? [] { if let e = seite.elemente.first(where: { $0.id == id }) { return Mac.text(e.text) } }
        return vorgabe
    }
    let texte: [String: String]

    static let gemeinsam: Oberflaeche = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Sprachdaten/oberflaeche.json"),
            let daten = try? Data(contentsOf: url),
            let o = try? JSONDecoder().decode(Oberflaeche.self, from: daten)
        else {
            NSLog("NoteMac++: oberflaeche.json fehlt im Bündel")
            return Oberflaeche(
                menues: [], tabmenue: [], suchen: Suchen(titel: [:], groesse: [411, 197], elemente: []), texte: [:])
        }
        return o
    }()

    /// Ein Text der deutschen Fassung, mit $STR_REPLACE1$ … ersetzt.
    func text(_ schluessel: String, _ ersatz: String...) -> String {
        var t = texte[schluessel] ?? schluessel
        for (i, e) in ersatz.enumerated() {
            t = t.replacingOccurrences(of: "$STR_REPLACE\(i + 1)$", with: e)
                .replacingOccurrences(of: "$INT_REPLACE\(i + 1)$", with: e)
            if i == 0 {
                t = t.replacingOccurrences(of: "$STR_REPLACE$", with: e).replacingOccurrences(of: "$INT_REPLACE$", with: e)
            }
        }
        return t
    }

    /// Titel eines Befehls aus dem Hauptmenü, für Werkzeugleiste und Kontextmenüs.
    func titel(_ id: String) -> String {
        Self.titelIndex[id] ?? id
    }

    /// Kürzel eines Befehls aus dem Hauptmenü (Notepad++-Schreibweise).
    func kuerzel(_ id: String) -> Kuerzel? { Self.kuerzelIndex[id] }

    private static let kuerzelIndex: [String: Kuerzel] = {
        var index: [String: Kuerzel] = [:]
        func lauf(_ liste: [Eintrag]) {
            for e in liste {
                switch e {
                case .befehl(let id, _, let k, _): if let k, index[id] == nil { index[id] = k }
                case .untermenue(_, _, let kinder): lauf(kinder)
                case .trenner: break
                }
            }
        }
        for m in gemeinsam.menues { lauf(m.eintraege) }
        return index
    }()

    private static let titelIndex: [String: String] = {
        var index: [String: String] = [:]
        func lauf(_ liste: [Eintrag]) {
            for e in liste {
                switch e {
                case .befehl(let id, let titel, _, _): if index[id] == nil { index[id] = Mac.text(titel) }
                case .untermenue(_, _, let k): lauf(k)
                case .trenner: break
                }
            }
        }
        for m in gemeinsam.menues { lauf(m.eintraege) }
        lauf(gemeinsam.tabmenue)
        return index
    }()
}

/// Wörter, die in Notepad++ zu Windows gehören, auf dem Mac richtig benannt;
/// und wo Notepad++ sich selbst meint, steht NoteMac++.
enum Mac {
    private static let ersatz: [(String, String)] = [
        ("Eingabeaufforderung/Kommandozeile", "Terminal"),
        ("in der Kommandozeile", "im Terminal"),
        ("Kommandozeile hier öffnen", "Terminal hier öffnen"),
        ("Explorer", "Finder"),
        ("STRG + ", "⌘ + "),
        ("Strg+", "⌘+"),
        ("in Windows", "in macOS"),
        ("Notepad++", "NoteMac++"),
        ("Papierkorb", "Papierkorb"),
    ]

    static func text(_ t: String) -> String {
        var r = t
        for (alt, neu) in ersatz { r = r.replacingOccurrences(of: alt, with: neu) }
        return r
    }
}

/// Die Symbole von Notepad++ (PowerEditor/src/icons), im Bündel unter Symbole/.
enum Symbole {
    private static var zwischenspeicher: [String: NSImage] = [:]
    private static let ordner = Bundle.main.resourceURL?.appendingPathComponent("Symbole", isDirectory: true)

    /// Ein Symbol der Werkzeugleiste. Satz «standard» (klassisch, BMP), «fluent» oder
    /// «fluentGefuellt»; dunkel nimmt die dunklen Fluent-Symbole.
    /// Ein Symbol der Werkzeugleiste. Satz «standard» (klassisch, BMP, nur hell),
    /// «fluent», «fluentGross», «fluentGefuellt», «fluentGefuelltGross» wie die Optionen
    /// von Notepad++; gross heisst 32 statt 16 Pixel.
    static func werkzeug(_ name: String, satz: String, dunkel: Bool, aus: Bool = false) -> NSImage? {
        if satz == "standard", !dunkel {
            return bmp("standard/toolbar/\(name).bmp")
        }
        let art = satz.contains("Gefuellt") ? "filled" : "regular"
        let groesse: CGFloat = satz.hasSuffix("Gross") ? 32 : 16
        let fluent = fluentNamen[name] ?? name
        return ico("\(dunkel ? "dark" : "light")/toolbar/\(art)/\(fluent)_\(aus ? "dis" : "off").ico", groesse: groesse)
            ?? ico("\(dunkel ? "dark" : "light")/toolbar/\(art)/\(fluent)_off.ico", groesse: groesse)
    }

    static func symbolGroesse(_ satz: String) -> CGFloat { satz.hasSuffix("Gross") ? 32 : 16 }


    /// Klassisch heissen manche Symbole anders als bei Fluent.
    private static let fluentNamen: [String: String] = [
        "newFile": "new", "openFile": "open", "saveFile": "save", "saveAll": "saveall", "closeFile": "close",
        "closeAll": "closeall", "findReplace": "findrep", "startRecord": "startrecord", "stopRecord": "stoprecord",
        "playRecord": "playrecord", "playRecord_m": "playrecord_m", "saveRecord": "saverecord",
    ]

    /// Tab-Symbole: saved, unsaved, readonly, closeTabButton … (hell: standard, dunkel: dark).
    static func tab(_ name: String, dunkel: Bool) -> NSImage? {
        ico("\(dunkel ? "dark" : "standard")/tabbar/\(name).ico") ?? ico("standard/tabbar/\(name).ico")
    }

    /// Das Bild als einfarbige Fläche in der Markierungsfarbe von Windows (0078D7):
    /// halb darübergelegt wie ILD_SELECTED, mit dem Notepad++ inaktive Tabs zeichnet.
    static func abgeblendet(_ bild: NSImage) -> NSImage {
        let schluessel = "abgeblendet:\(ObjectIdentifier(bild).hashValue)"
        if let b = zwischenspeicher[schluessel] { return b }
        let neu = NSImage(size: bild.size, flipped: false) { r in
            bild.draw(in: r)
            NSColor(rgb: 0x0078D7).setFill()
            r.fill(using: .sourceAtop)
            return true
        }
        zwischenspeicher[schluessel] = neu
        return neu
    }

    static func ico(_ pfad: String, groesse: CGFloat? = nil) -> NSImage? {
        if let g = groesse {
            let schluessel = pfad + "@\(Int(g))"
            if let b = zwischenspeicher[schluessel] { return b }
            guard let basis = ico(pfad), let kopie = basis.copy() as? NSImage else { return nil }
            kopie.size = NSSize(width: g, height: g)
            zwischenspeicher[schluessel] = kopie
            return kopie
        }
        if let b = zwischenspeicher[pfad] { return b }
        guard let url = ordner?.appendingPathComponent(pfad), let daten = try? Data(contentsOf: url) else { return nil }
        // macOS liest manche ICO-Dateien von Notepad++ nicht (etwa 11 × 11 Pixel als PNG
        // eingebettet, die Schliessen-Kreuze der Tabs); die Bilder darin sind gewöhnliche
        // PNG oder BMP und lassen sich einzeln lesen.
        guard let bild = NSImage(data: daten) ?? icoEinzeln(daten) else { return nil }
        // Die natürliche Grösse, höchstens 16 Punkt (Notepad++ zeichnet bei 100 % ohne Skalierung).
        let kleinste = bild.representations.map { min($0.pixelsWide, $0.pixelsHigh) }.filter { $0 > 0 }.min() ?? 16
        let seite = CGFloat(min(16, kleinste))
        bild.size = NSSize(width: seite, height: seite)
        zwischenspeicher[pfad] = bild
        return bild
    }

    /// Liest die Bilder einer ICO-Datei einzeln (Verzeichnis: 6 Byte Kopf, je Bild 16 Byte).
    static func icoEinzeln(_ d: Data) -> NSImage? {
        let b = [UInt8](d)
        guard b.count > 6, b[0] == 0, b[1] == 0, b[2] == 1 else { return nil }
        let anzahl = Int(b[4]) | Int(b[5]) << 8
        let bild = NSImage()
        for i in 0..<anzahl {
            let e = 6 + i * 16
            guard e + 16 <= b.count else { break }
            func u32(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 }
            let groesse = u32(e + 8), versatz = u32(e + 12)
            guard versatz + groesse <= b.count, groesse > 8 else { continue }
            let teil = d.subdata(in: versatz..<versatz + groesse)
            if teil.starts(with: [0x89, 0x50, 0x4E, 0x47]), let rep = NSBitmapImageRep(data: teil) {
                bild.addRepresentation(rep)
            }
        }
        return bild.representations.isEmpty ? nil : bild
    }


    /// Klassische BMP-Symbole: Die Farbe der linken oberen Ecke ist transparent,
    /// wie in der Bildliste von Notepad++.
    static func bmp(_ pfad: String) -> NSImage? {
        if let b = zwischenspeicher[pfad] { return b }
        guard let url = ordner?.appendingPathComponent(pfad),
            let quelle = CGImageSourceCreateWithURL(url as CFURL, nil),
            let roh = CGImageSourceCreateImageAtIndex(quelle, 0, nil)
        else { return nil }
        let b = roh.width
        let h = roh.height
        var pixel = [UInt8](repeating: 0, count: b * h * 4)
        guard let kontext = CGContext(
            data: &pixel, width: b, height: h, bitsPerComponent: 8, bytesPerRow: b * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        kontext.draw(roh, in: CGRect(x: 0, y: 0, width: b, height: h))
        // Zeile 0 im Speicher ist die obere Zeile des Bildes.
        let schluessel = Array(pixel[0..<3])
        for i in stride(from: 0, to: pixel.count, by: 4) where Array(pixel[i..<i + 3]) == schluessel {
            pixel[i] = 0; pixel[i + 1] = 0; pixel[i + 2] = 0; pixel[i + 3] = 0
        }
        guard let fertig = kontext.makeImage() else { return nil }
        let bild = NSImage(cgImage: fertig, size: NSSize(width: 16, height: 16 * CGFloat(h) / CGFloat(max(b, 1))))
        zwischenspeicher[pfad] = bild
        return bild
    }
}
