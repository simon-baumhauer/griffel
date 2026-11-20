import Foundation

/// Eine Sprache aus langs.model.xml von Notepad++, mit dem Lexer, den
/// Notepad++ für sie nimmt (scripts/sprachdaten.py bereitet beides auf).
struct Sprache: Decodable {
    let name: String
    let kurz: String
    let lang: String
    let lexer: String
    let imMenue: Bool
    let endungen: [String]
    let kommentarZeile: String?
    let kommentarAnfang: String?
    let kommentarEnde: String?
    /// Schlüsselwörter je Klasse: instre1, instre2, type1 … type7.
    let woerter: [String: String]

    var istNormalerText: Bool { name == "normal" }
    /// Eine benutzerdefinierte Sprache (UDL); ihr Name beginnt mit «udl:».
    var istBenutzersprache: Bool { name.hasPrefix(Sprache.udl) }
    static let udl = "udl:"
}

/// Ein Stil aus einem Farbschema von Notepad++. Farben als 0xRRGGBB;
/// schrift: 1 fett, 2 kursiv, 4 unterstrichen.
struct Stil: Decodable {
    let id: Int
    let vorne: Int?
    let hinten: Int?
    let schrift: Int?
    /// Nur beim Standardstil: Schriftart und -grösse (Punkt unter Windows).
    let schriftart: String?
    let groesse: Int?
    /// Die Schlüsselwortklasse, die dieser Stil einfärbt, und die Wörter, die
    /// das Schema selbst noch dazugibt (in Notepad++: «User-defined keywords»).
    let klasse: String?
    let woerter: String?
}

struct Farbschema: Decodable {
    let name: String
    /// Nach dem Namen aus GlobalStyles, etwa «Default Style» oder «Caret colour».
    let global: [String: Stil]
    /// Nach dem Namen der Sprache, wie in langs.model.xml.
    let lexer: [String: [Stil]]

    static let leer = Farbschema(name: "", global: [:], lexer: [:])
}

/// Alle Sprachen und Farbschemata, aus Contents/Resources/Sprachdaten.
final class Sprachdaten {
    static let gemeinsam = Sprachdaten()

    let sprachen: [Sprache]
    let farbschemaNamen: [String]
    let normal: Sprache

    private let nachName: [String: Sprache]
    private let nachEndung: [String: Sprache]
    private var geladen: [String: Farbschema] = [:]
    private let ordner: URL?

    private init() {
        ordner = Bundle.main.resourceURL?.appendingPathComponent("Sprachdaten", isDirectory: true)
        let dekoder = JSONDecoder()
        sprachen = ordner
            .flatMap { try? Data(contentsOf: $0.appendingPathComponent("sprachen.json")) }
            .flatMap { try? dekoder.decode([Sprache].self, from: $0) } ?? []
        farbschemaNamen = ordner
            .flatMap { try? Data(contentsOf: $0.appendingPathComponent("farbschemata.json")) }
            .flatMap { try? dekoder.decode([String].self, from: $0) } ?? []
        if sprachen.isEmpty {
            NSLog("Kladde: Sprachdaten fehlen im Bündel; es gibt nur normalen Text.")
        }

        nachName = Dictionary(sprachen.map { ($0.name, $0) }, uniquingKeysWith: { erste, _ in erste })
        // Wie Notepad++: Gehört eine Endung zu mehreren Sprachen, gilt die erste der Liste.
        var endungen: [String: Sprache] = [:]
        for sprache in sprachen where sprache.imMenue {
            for endung in sprache.endungen where endungen[endung.lowercased()] == nil {
                endungen[endung.lowercased()] = sprache
            }
        }
        nachEndung = endungen
        normal = nachName["normal"] ?? Sprache(
            name: "normal", kurz: "Normal text", lang: "Normal text file", lexer: "null", imMenue: true,
            endungen: [], kommentarZeile: nil, kommentarAnfang: nil, kommentarEnde: nil, woerter: [:])
        ladeBenutzersprachen()
    }

    func sprache(_ name: String) -> Sprache? {
        if name.hasPrefix(Sprache.udl) { return benutzersprachen[name].map(\.sprache) }
        return nachName[name]
    }

    // MARK: Funktionsliste und Autovervollständigung

    private var funktionslisten: [String: Funktionsliste?] = [:]
    private var wortschaetze: [String: Wortschatz] = [:]

    /// Die Funktionsliste von Notepad++ für eine Sprache, falls es eine gibt und ICU sie versteht.
    func funktionsliste(fuer sprache: Sprache) -> Funktionsliste? {
        if let bekannt = funktionslisten[sprache.name] { return bekannt }
        let liste = ordner.flatMap { o in
            try? Funktionsliste.lade(o.appendingPathComponent("funktionsliste/\(sprache.name).xml"))
        }
        funktionslisten[sprache.name] = liste
        return liste
    }

    /// Die Wörter und Funktionen der Sprache aus installer/APIs (für «javascript.js» gilt javascript.xml).
    func wortschatz(fuer sprache: Sprache) -> Wortschatz {
        if let bekannt = wortschaetze[sprache.name] { return bekannt }
        var schatz = Wortschatz.leer
        if let ordner {
            for name in [sprache.name, String(sprache.name.split(separator: ".").first ?? "")] where !name.isEmpty {
                if let geladen = try? Wortschatz.lade(ordner.appendingPathComponent("autovervollstaendigung/\(name).xml")) {
                    schatz = geladen
                    break
                }
            }
        }
        wortschaetze[sprache.name] = schatz
        return schatz
    }

    // MARK: Benutzerdefinierte Sprachen

    /// Wo die UDL-Dateien liegen, wie «userDefineLangs» bei Notepad++.
    /// Mit «-KladdeUDL /pfad» beim Start liegt er woanders (für Prüfläufe).
    static var benutzersprachenOrdner: URL {
        if let pfad = UserDefaults.standard.string(forKey: "KladdeUDL") { return URL(fileURLWithPath: pfad, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kladde/userDefineLangs", isDirectory: true)
    }

    struct Eigene {
        let udl: Benutzersprache
        let sprache: Sprache
    }

    /// Nach Name («udl:…»).
    private(set) var benutzersprachen: [String: Eigene] = [:]
    /// Dateien, die sich nicht laden liessen, mit Grund.
    private(set) var benutzerspracheFehler: [String] = []

    func benutzersprache(fuer sprache: Sprache) -> Benutzersprache? { benutzersprachen[sprache.name]?.udl }

    /// Liest alle XML-Dateien im Ordner neu ein.
    func ladeBenutzersprachen() {
        benutzersprachen = [:]
        benutzerspracheFehler = []
        let dateien = (try? FileManager.default.contentsOfDirectory(
            at: Self.benutzersprachenOrdner, includingPropertiesForKeys: nil)) ?? []
        for datei in dateien.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where datei.pathExtension.lowercased() == "xml" {
            do {
                for udl in try Benutzersprache.lade(datei) {
                    let zeichen = udl.kommentarzeichen
                    let sprache = Sprache(
                        name: Sprache.udl + udl.name, kurz: udl.name, lang: "Benutzerdefiniert: \(udl.name)",
                        lexer: "user", imMenue: false, endungen: udl.endungen,
                        kommentarZeile: zeichen.zeile, kommentarAnfang: zeichen.anfang, kommentarEnde: zeichen.ende,
                        woerter: [:])
                    benutzersprachen[sprache.name] = Eigene(udl: udl, sprache: sprache)
                }
            } catch {
                benutzerspracheFehler.append("\(datei.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    func farbschema(_ name: String) -> Farbschema {
        if let schema = geladen[name] { return schema }
        guard let ordner,
            let daten = try? Data(contentsOf: ordner.appendingPathComponent("farbschemata/\(name).json")),
            let schema = try? JSONDecoder().decode(Farbschema.self, from: daten)
        else {
            return name == "Standard" ? .leer : farbschema("Standard")
        }
        geladen[name] = schema
        return schema
    }

    // MARK: Erkennen

    /// Dateinamen ohne passende Endung, die Notepad++ trotzdem erkennt.
    private static let dateinamen: [String: String] = [
        "makefile": "makefile", "gnumakefile": "makefile", "cmakelists.txt": "cmake",
        "dockerfile": "bash", ".bashrc": "bash", ".zshrc": "bash", ".profile": "bash",
    ]

    /// Die Sprache einer Datei: zuerst nach dem Namen, dann nach der Endung,
    /// sonst nach der ersten Zeile (#! oder <?xml). Ohne Treffer: normaler Text.
    func erkenne(url: URL?, anfang: Data) -> Sprache {
        // Wie Notepad++: Endungen benutzerdefinierter Sprachen gehen vor.
        if let endung = url?.pathExtension.lowercased(), !endung.isEmpty,
            let eigene = benutzersprachen.values.sorted(by: { $0.sprache.name < $1.sprache.name })
                .first(where: { $0.udl.endungen.contains { $0.lowercased() == endung } })
        {
            return eigene.sprache
        }
        if let url {
            let name = url.lastPathComponent.lowercased()
            if let treffer = Self.dateinamen[name].flatMap(sprache) { return treffer }
            if let treffer = nachEndung[name] { return treffer }  // Endungen wie «makefile» in langs
            let endung = url.pathExtension.lowercased()
            if !endung.isEmpty, let treffer = nachEndung[endung] { return treffer }
        }
        return erkenneAmAnfang(anfang) ?? normal
    }

    /// Wie detectLanguageFromTextBeginning in Notepad++.
    private func erkenneAmAnfang(_ anfang: Data) -> Sprache? {
        let text = String(decoding: anfang.prefix(256), as: UTF8.self)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        let ersteZeile = text.prefix(while: { $0 != "\n" && $0 != "\r" }).lowercased()

        if ersteZeile.hasPrefix("#!") {
            let regeln: [(String, String)] = [
                ("python", "python"), ("perl", "perl"), ("ruby", "ruby"), ("php", "php"),
                ("node", "javascript.js"), ("lua", "lua"), ("tclsh", "tcl"), ("wish", "tcl"),
                ("pwsh", "powershell"), ("bash", "bash"), ("zsh", "bash"), ("/sh", "bash"), ("ksh", "bash"),
            ]
            for (wort, name) in regeln where ersteZeile.contains(wort) {
                return sprache(name)
            }
            return nil
        }
        let anfangKlein = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64).lowercased()
        if anfangKlein.hasPrefix("<?php") { return sprache("php") }
        if anfangKlein.hasPrefix("<?xml") { return sprache("xml") }
        if anfangKlein.hasPrefix("<!doctype html") || anfangKlein.hasPrefix("<html") { return sprache("html") }
        return nil
    }
}
