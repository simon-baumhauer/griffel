import Foundation

/// Wie eine Sprache in Scintilla eingerichtet wird: Lexer, Farben, Listen
/// von Schlüsselwörtern und Eigenschaften. Nachgebaut aus defineDocType und
/// den set…Lexer-Funktionen in ScintillaEditView.cpp/.h von Notepad++.
///
/// Die meisten Sprachen folgen dem Grundschema: Liste n der Sprache
/// (instre1 = 0, instre2 = 1, type1 = 2 …) geht an Scintilla-Liste n. Davon
/// weichen die C-Familie, JavaScript, TypeScript, Objective-C, Tcl, XML,
/// HTML samt PHP/ASP/JSP und JSON ab; die stehen unten einzeln.
struct Sprachregel {
    /// Name des Lexers in Lexilla.
    var lexer: String
    /// Welche Abschnitte des Farbschemas gelten, in dieser Reihenfolge.
    var farben: [String]
    /// Scintilla-Liste ← Schlüsselwörter einer Klasse einer Sprache.
    var listen: [(liste: Int, sprache: String, klasse: String)]
    var eigenschaften: [(String, String)]

    static let klassen = ["instre1", "instre2", "type1", "type2", "type3", "type4", "type5", "type6", "type7"]

    private static let faltung = [("fold", "1"), ("fold.compact", "0"), ("fold.comment", "1")]
    private static let cFaltung = faltung + [
        ("fold.cpp.comment.explicit", "0"), ("fold.preprocessor", "1"), ("lexer.cpp.track.preprocessor", "0"),
    ]
    /// Doxygen-Wörter: Notepad++ nimmt für alle C-artigen Sprachen die von C++.
    private static let doxygen = (liste: 2, sprache: "cpp", klasse: "type2")

    static func fuer(_ sprache: Sprache) -> Sprachregel {
        let name = sprache.name
        func eigene(_ paare: [(Int, String)]) -> [(liste: Int, sprache: String, klasse: String)] {
            paare.map { (liste: $0.0, sprache: name, klasse: $0.1) }
        }

        switch name {
        case "c", "cpp", "java", "rc", "cs", "actionscript", "swift", "go":
            var listen = eigene([(0, "instre1"), (1, "type1"), (3, "instre2")])
            if name != "rc" { listen.append(doxygen) }
            var eigenschaften = cFaltung
            if name == "go" { eigenschaften.append(("lexer.cpp.backquoted.strings", "1")) }
            return Sprachregel(lexer: "cpp", farben: [name], listen: listen, eigenschaften: eigenschaften)

        case "javascript.js":
            return Sprachregel(
                lexer: "cpp", farben: [name],
                listen: eigene([(0, "instre1"), (1, "type1"), (3, "instre2")]) + [doxygen],
                eigenschaften: cFaltung)

        case "typescript":
            return Sprachregel(
                lexer: "cpp", farben: [name], listen: eigene([(0, "instre1"), (1, "type1")]) + [doxygen],
                eigenschaften: cFaltung + [("lexer.cpp.backquoted.strings", "1")])

        case "objc":
            return Sprachregel(
                lexer: "objc", farben: [name],
                listen: eigene([(0, "instre1"), (1, "type1"), (3, "instre2"), (4, "type2")]) + [doxygen],
                eigenschaften: cFaltung)

        case "tcl":
            return Sprachregel(
                lexer: "tcl", farben: [name],
                listen: eigene([
                    (0, "instre1"), (1, "type1"), (2, "instre2"), (3, "type2"), (4, "type3"),
                    (5, "type4"), (6, "type5"), (7, "type6"), (8, "type7"),
                ]),
                eigenschaften: faltung)

        case "xml":
            return Sprachregel(
                lexer: "xml", farben: [name], listen: eigene([(5, "instre1")]),
                eigenschaften: [
                    ("lexer.xml.allow.scripts", "0"), ("fold", "1"), ("fold.compact", "0"),
                    ("fold.html", "1"), ("fold.hypertext.comment", "1"),
                ])

        case "html", "php", "asp", "jsp":
            // Ein Lexer für alles, mit eingebettetem JavaScript, PHP und VBScript.
            return Sprachregel(
                lexer: "hypertext", farben: ["html", "javascript", "php", "asp"],
                listen: [
                    (liste: 0, sprache: "html", klasse: "instre1"),
                    (liste: 5, sprache: "html", klasse: "instre2"),
                    (liste: 1, sprache: "javascript", klasse: "instre1"),
                    (liste: 4, sprache: "php", klasse: "instre1"),
                    (liste: 2, sprache: "vb", klasse: "instre1"),
                ],
                eigenschaften: [
                    ("asp.default.language", "2"), ("fold", "1"), ("fold.compact", "0"),
                    ("fold.html", "1"), ("fold.hypertext.comment", "1"),
                ])

        case "json", "json5":
            var eigenschaften = [("fold", "1"), ("fold.compact", "0"), ("lexer.json.escape.sequence", "1")]
            if name == "json5" { eigenschaften.append(("lexer.json.allow.comments", "1")) }
            return Sprachregel(
                lexer: "json", farben: ["json"],
                listen: [(liste: 0, sprache: "json", klasse: "instre1"), (liste: 1, sprache: "json", klasse: "instre2")],
                eigenschaften: eigenschaften)

        default:
            var eigenschaften = faltung
            switch name {
            case "python":
                eigenschaften += [
                    ("fold.quotes.python", "1"), ("lexer.python.decorator.attributes", "1"),
                    ("lexer.python.identifier.attributes", "1"),
                ]
            case "sql":
                eigenschaften.append(("sql.backslash.escapes", "1"))
            default:
                break
            }
            return Sprachregel(
                lexer: sprache.lexer, farben: [name],
                listen: eigene(klassen.enumerated().map { ($0.offset, $0.element) }),
                eigenschaften: eigenschaften)
        }
    }

    /// Die Wörter einer Liste: die aus langs.model.xml und die, die das
    /// Farbschema für dieselbe Klasse dazugibt (concatToBuildKeywordList).
    static func woerter(sprache name: String, klasse: String, schema: Farbschema) -> String {
        let ausSprache = Sprachdaten.gemeinsam.sprache(name)?.woerter[klasse] ?? ""
        let ausSchema = schema.lexer[name]?.compactMap { $0.klasse == klasse ? $0.woerter : nil } ?? []
        return ([ausSprache] + ausSchema).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
