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
    }

    struct Suchen: Decodable {
        let titel: [String: String?]
        let groesse: [Int]
        let elemente: [Element]
    }

    let menues: [Menue]
    let tabmenue: [Eintrag]
    let suchen: Suchen
    let texte: [String: String]

    static let gemeinsam: Oberflaeche = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Sprachdaten/oberflaeche.json"),
            let daten = try? Data(contentsOf: url),
            let o = try? JSONDecoder().decode(Oberflaeche.self, from: daten)
        else {
            NSLog("Kladde: oberflaeche.json fehlt im Bündel")
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
/// und wo Notepad++ sich selbst meint, steht Kladde.
enum Mac {
    private static let ersatz: [(String, String)] = [
        ("Eingabeaufforderung/Kommandozeile", "Terminal"),
        ("in der Kommandozeile", "im Terminal"),
        ("Kommandozeile hier öffnen", "Terminal hier öffnen"),
        ("Explorer", "Finder"),
        ("in Windows", "in macOS"),
        ("Notepad++", "Kladde"),
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
    static func werkzeug(_ name: String, satz: String, dunkel: Bool, aus: Bool = false) -> NSImage? {
        if satz == "standard", !dunkel {
            return bmp("standard/toolbar/\(name).bmp")
        }
        let art = satz == "fluentGefuellt" ? "filled" : "regular"
        let fluent = fluentNamen[name] ?? name
        return ico("\(dunkel ? "dark" : "light")/toolbar/\(art)/\(fluent)_\(aus ? "dis" : "off").ico")
            ?? ico("\(dunkel ? "dark" : "light")/toolbar/\(art)/\(fluent)_off.ico")
    }

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

    static func ico(_ pfad: String) -> NSImage? {
        if let b = zwischenspeicher[pfad] { return b }
        guard let url = ordner?.appendingPathComponent(pfad), let bild = NSImage(contentsOf: url) else { return nil }
        // Die kleinste passende Grösse zuerst: 16 Punkt.
        bild.size = NSSize(width: 16, height: 16)
        zwischenspeicher[pfad] = bild
        return bild
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
