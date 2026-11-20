import XCTest

@testable import KladdeKern

final class SucheTests: XCTestCase {
    private func muster(
        _ text: String, ersetzung: String = "", modus: SuchOptionen.Modus = .normal,
        grossKlein: Bool = false, ganzesWort: Bool = false, punkt: Bool = false, umbruch: Bool = true
    ) throws -> Suchmuster {
        var o = SuchOptionen()
        o.text = text
        o.ersetzung = ersetzung
        o.modus = modus
        o.grossKlein = grossKlein
        o.ganzesWort = ganzesWort
        o.punktFindetZeilenende = punkt
        o.umbruch = umbruch
        return try Suchmuster(o)
    }

    // MARK: Finden

    func testNormalIstWoertlichUndOhneGrossKlein() throws {
        let text = Suchtext("Preis: 3.50 (CHF) und 3x50")
        let treffer = try muster("3.50").alle(in: text)
        XCTAssertEqual(treffer.map(\.bereich), [7..<11])
        XCTAssertEqual(try muster("chf").alle(in: text).count, 1)
        XCTAssertEqual(try muster("chf", grossKlein: true).alle(in: text).count, 0)
    }

    func testBytesNachUmlautenUndEmoji() throws {
        // «ü» hat 2 Bytes, «😀» 4 Bytes (2 UTF-16-Einheiten).
        let text = Suchtext("Grüezi 😀 Zürich")
        let treffer = try muster("zürich").alle(in: text)
        XCTAssertEqual(treffer.map(\.bereich), [13..<20])
        XCTAssertEqual(String(decoding: text.utf8[13..<20], as: UTF8.self), "Zürich")
    }

    func testGanzesWort() throws {
        let text = Suchtext("bern Bern_x Bernau bern2 (Bern) übern")
        XCTAssertEqual(try muster("bern", ganzesWort: true).alle(in: text).count, 2)
    }

    func testErweitert() throws {
        let text = Suchtext("a\tb\r\nc\\d")
        XCTAssertEqual(try muster("\\t", modus: .erweitert).alle(in: text).map(\.bereich), [1..<2])
        XCTAssertEqual(try muster("\\r\\n", modus: .erweitert).alle(in: text).map(\.bereich), [3..<5])
        XCTAssertEqual(try muster("c\\\\d", modus: .erweitert).alle(in: text).map(\.bereich), [5..<8])
        XCTAssertEqual(try muster("\\x62", modus: .erweitert).alle(in: text).map(\.bereich), [2..<3])
        XCTAssertThrowsError(try muster("\\x6", modus: .erweitert))
    }

    func testRegexZeilenankerUndPunkt() throws {
        let text = Suchtext("eins\nzwei\r\ndrei")
        XCTAssertEqual(try muster("^\\w+$", modus: .regulaer).alle(in: text).count, 3)
        XCTAssertEqual(try muster("eins.zwei", modus: .regulaer).alle(in: text).count, 0)
        XCTAssertEqual(try muster("eins.zwei", modus: .regulaer, punkt: true).alle(in: text).count, 1)
        XCTAssertEqual(try muster("(?<=zwei\\r\\n)drei", modus: .regulaer).alle(in: text).map(\.bereich), [11..<15])
    }

    func testUngueltigerAusdruck() {
        XCTAssertThrowsError(try muster("(offen", modus: .regulaer)) { fehler in
            XCTAssertEqual(fehler as? Suchfehler, Suchfehler(meldung: "Ungültiger Ausdruck"))
        }
        XCTAssertThrowsError(try muster(""))
    }

    func testBereichSiehtUeberDieGrenze() throws {
        // Im Bereich ab Byte 4 liegt «bc»; \b davor gilt nicht, weil davor «a» steht.
        let text = Suchtext("abc bc")
        let treffer = try muster("\\bbc", modus: .regulaer).alle(in: text, bereich: 1..<6)
        XCTAssertEqual(treffer.map(\.bereich), [4..<6])
    }

    // MARK: Weitersuchen

    func testWeiterUndUmbruch() throws {
        let text = Suchtext("x a x a x")
        let m = try muster("x")
        XCTAssertEqual(m.naechster(in: text, ab: 1)?.treffer.bereich, 4..<5)
        let umgebrochen = m.naechster(in: text, ab: 9)
        XCTAssertEqual(umgebrochen?.treffer.bereich, 0..<1)
        XCTAssertEqual(umgebrochen?.umgebrochen, true)
        XCTAssertNil(try muster("x", umbruch: false).naechster(in: text, ab: 9))
    }

    func testRueckwaerts() throws {
        let text = Suchtext("x a x a x")
        let m = try muster("x")
        XCTAssertEqual(m.naechster(in: text, ab: 8, rueckwaerts: true)?.treffer.bereich, 4..<5)
        let umgebrochen = m.naechster(in: text, ab: 0, rueckwaerts: true)
        XCTAssertEqual(umgebrochen?.treffer.bereich, 8..<9)
        XCTAssertEqual(umgebrochen?.umgebrochen, true)
    }

    func testLeererTrefferBleibtNichtStehen() throws {
        let text = Suchtext("a\nb\nc")
        let m = try muster("^", modus: .regulaer)
        let erster = m.naechster(in: text, ab: 0)!.treffer
        XCTAssertEqual(erster.bereich, 0..<0)
        let zweiter = m.naechster(in: text, ab: 0, ausser: 0)!.treffer
        XCTAssertEqual(zweiter.bereich, 2..<2)
    }

    // MARK: Ersetzen

    func testErsetzenMitGruppen() throws {
        let text = Suchtext("Baumhauer, Simon\nMuster, Hans")
        let m = try muster("^(\\w+), (\\w+)$", ersetzung: "$2 \\1 (${1})", modus: .regulaer)
        let neu = m.ersetzeAlle(in: text)
        XCTAssertEqual(neu.anzahl, 2)
        XCTAssertEqual(String(decoding: neu.utf8, as: UTF8.self), "Simon Baumhauer (Baumhauer)\nHans Muster (Muster)")
    }

    func testErsetzenGrossKlein() throws {
        let text = Suchtext("zürich bern")
        let m = try muster("(\\w)(\\w+)", ersetzung: "\\u$1\\U$2\\E!", modus: .regulaer)
        XCTAssertEqual(String(decoding: m.ersetzeAlle(in: text).utf8, as: UTF8.self), "ZÜRICH! BERN!")
        let klein = try muster("\\w+", ersetzung: "\\L$0", modus: .regulaer)
        XCTAssertEqual(String(decoding: klein.ersetzeAlle(in: Suchtext("ABC Äöü")).utf8, as: UTF8.self), "abc äöü")
    }

    func testErsetzenEscapesUndWoertlich() throws {
        let regex = try muster(",", ersetzung: "\\t\\$1\\\\", modus: .regulaer)
        XCTAssertEqual(String(decoding: regex.ersetzeAlle(in: Suchtext("a,b")).utf8, as: UTF8.self), "a\t$1\\b")
        // Im Modus Normal ist $1 einfach Text.
        let normal = try muster(",", ersetzung: "$1")
        XCTAssertEqual(String(decoding: normal.ersetzeAlle(in: Suchtext("a,b")).utf8, as: UTF8.self), "a$1b")
        let erweitert = try muster(";", ersetzung: "\\r\\n", modus: .erweitert)
        XCTAssertEqual(String(decoding: erweitert.ersetzeAlle(in: Suchtext("a;b")).utf8, as: UTF8.self), "a\r\nb")
    }

    func testErsetzenHaeltUmlauteBytegenau() throws {
        let text = Suchtext("Grüezi Zürich, grüezi Bern")
        let m = try muster("grüezi", ersetzung: "Hoi")
        XCTAssertEqual(String(decoding: m.ersetzeAlle(in: text).utf8, as: UTF8.self), "Hoi Zürich, Hoi Bern")
    }

    // MARK: Zeilen

    func testZeilen() {
        let text = Suchtext("eins\r\nzwei\nü\rvier")
        XCTAssertEqual(text.zeile(bei: 0).nummer, 1)
        XCTAssertEqual(text.zeile(bei: 2).bereich, 0..<4)
        XCTAssertEqual(text.zeile(bei: 6).nummer, 2)
        XCTAssertEqual(text.zeile(bei: 6).bereich, 6..<10)
        XCTAssertEqual(text.zeile(bei: 11).bereich, 11..<13)
        XCTAssertEqual(text.zeile(bei: 14).nummer, 4)
    }
}
