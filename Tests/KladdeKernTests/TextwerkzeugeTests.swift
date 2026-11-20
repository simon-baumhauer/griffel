import XCTest

@testable import KladdeKern

final class TextwerkzeugeTests: XCTestCase {
    // MARK: Sortieren

    func testSortierenLexikografischUndOhneGrossKlein() {
        let zeilen = ["b", "B", "a", "Ä", "A"]
        XCTAssertEqual(Zeilenwerkzeug.sortiere(zeilen, .aufsteigend), ["A", "B", "a", "b", "Ä"])
        XCTAssertEqual(Zeilenwerkzeug.sortiere(zeilen, .absteigend), ["Ä", "b", "a", "B", "A"])
        // Stabil: «b» vor «B», «a» vor «A», wie sie standen.
        XCTAssertEqual(Zeilenwerkzeug.sortiere(["b", "B", "a", "A"], .ohneGrossKleinAuf), ["a", "A", "b", "B"])
    }

    func testSortierenNachZahlen() {
        let zeilen = ["10 Äpfel", "x", "-3", "2", "  7 Birnen", "2b"]
        XCTAssertEqual(Zeilenwerkzeug.sortiere(zeilen, .ganzzahlAuf), ["-3", "2", "2b", "  7 Birnen", "10 Äpfel", "x"])
        XCTAssertEqual(Zeilenwerkzeug.sortiere(zeilen, .ganzzahlAb), ["10 Äpfel", "  7 Birnen", "2", "2b", "-3", "x"])
        XCTAssertEqual(Zeilenwerkzeug.sortiere(["1.5", "1.25", "-0.5"], .dezimalPunktAuf), ["-0.5", "1.25", "1.5"])
        XCTAssertEqual(Zeilenwerkzeug.sortiere(["1,5", "1,25", "10"], .dezimalKommaAb), ["10", "1,5", "1,25"])
    }

    func testSortierenLaengeUmkehrenZufall() {
        XCTAssertEqual(Zeilenwerkzeug.sortiere(["ccc", "a", "bb", "d"], .laengeAuf), ["a", "d", "bb", "ccc"])
        XCTAssertEqual(Zeilenwerkzeug.sortiere(["1", "2", "3"], .umkehren), ["3", "2", "1"])
        XCTAssertEqual(Set(Zeilenwerkzeug.sortiere(["1", "2", "3"], .zufaellig)), ["1", "2", "3"])
    }

    // MARK: Doppelte, leere, Leerzeichen

    func testDoppelteUndLeere() {
        XCTAssertEqual(Zeilenwerkzeug.ohneDoppelte(["a", "b", "a", "c", "b"]), ["a", "b", "c"])
        XCTAssertEqual(Zeilenwerkzeug.ohneAufeinanderfolgendeDoppelte(["a", "a", "b", "a", "a"]), ["a", "b", "a"])
        XCTAssertEqual(Zeilenwerkzeug.ohneLeere(["a", "", " \t", "b"], auchNurLeerzeichen: false), ["a", " \t", "b"])
        XCTAssertEqual(Zeilenwerkzeug.ohneLeere(["a", "", " \t", "b"], auchNurLeerzeichen: true), ["a", "b"])
    }

    func testKuerzenUndTabs() {
        XCTAssertEqual(Zeilenwerkzeug.kuerze(["  a b \t", "\tc"], .ende), ["  a b", "\tc"])
        XCTAssertEqual(Zeilenwerkzeug.kuerze(["  a b \t"], .anfang), ["a b \t"])
        XCTAssertEqual(Zeilenwerkzeug.kuerze(["  a b \t"], .beide), ["a b"])
        XCTAssertEqual(Zeilenwerkzeug.tabsZuLeerzeichen(["\tx", "ab\tc"], breite: 4), ["    x", "ab  c"])
        XCTAssertEqual(Zeilenwerkzeug.fuehrendeLeerzeichenZuTabs(["         x  y", "  \t z"], breite: 4), ["\t\t x  y", "\t z"])
    }

    // MARK: Schreibung

    func testSchreibung() {
        XCTAssertEqual(Schreibung.gross.wende(an: "Grüezi straße"), "GRÜEZI STRASSE")
        XCTAssertEqual(Schreibung.woerterGross.wende(an: "hALLO wELT, o'neil"), "Hallo Welt, O'neil")
        XCTAssertEqual(Schreibung.woerterGrossBelassen.wende(an: "hALLO wELT"), "HALLO WELT")
        XCTAssertEqual(Schreibung.satzanfang.wende(an: "eRSTER sATZ. zWEITER? ja"), "Erster satz. Zweiter? Ja")
        XCTAssertEqual(Schreibung.umkehren.wende(an: "Äb1"), "äB1")
        XCTAssertEqual(Schreibung.zufaellig.wende(an: "abc").lowercased(), "abc")
    }

    // MARK: Kommentare

    func testZeilenkommentarUmschalten() {
        let code = ["    if x {", "", "        y()", "    }"]
        let an = Kommentar.zeilenUmschalten(code, zeichen: "//")
        XCTAssertEqual(an, ["    // if x {", "", "    //     y()", "    // }"])
        XCTAssertEqual(Kommentar.zeilenUmschalten(an, zeichen: "//"), code)
        // Gemischt: eine Zeile schon kommentiert → alle bekommen eins.
        XCTAssertEqual(Kommentar.zeilenUmschalten(["# a", "b"], zeichen: "#"), ["# # a", "# b"])
        XCTAssertEqual(Kommentar.zeilenUmschalten(["#a"], zeichen: "#"), ["a"])
    }

    func testBlockkommentarUmschalten() {
        XCTAssertEqual(Kommentar.blockUmschalten("x = 1", anfang: "/*", ende: "*/"), "/* x = 1 */")
        XCTAssertEqual(Kommentar.blockUmschalten("/* x = 1 */", anfang: "/*", ende: "*/"), "x = 1")
        XCTAssertEqual(Kommentar.blockUmschalten("  <!--a-->\n", anfang: "<!--", ende: "-->"), "  a\n")
    }

    // MARK: Spalteneditor

    func testZahlenfolge() {
        var f = Zahlenfolge()
        XCTAssertEqual(f.texte(3), ["1", "2", "3"])
        f.anfang = 8
        f.schritt = 2
        f.fuehrend = .nullen
        XCTAssertEqual(f.texte(3), ["08", "10", "12"])
        f.fuehrend = .leerzeichen
        XCTAssertEqual(f.texte(2), [" 8", "10"])
        f = Zahlenfolge()
        f.wiederholen = 2
        XCTAssertEqual(f.texte(5), ["1", "1", "2", "2", "3"])
        f = Zahlenfolge()
        f.anfang = 254
        f.basis = 16
        XCTAssertEqual(f.texte(3), ["FE", "FF", "100"])
        f.anfang = -2
        f.basis = 10
        f.fuehrend = .nullen
        f.schritt = 6
        XCTAssertEqual(f.texte(3), ["-2", "04", "10"])
        f = Zahlenfolge()
        f.basis = 2
        f.anfang = 1
        f.fuehrend = .nullen
        XCTAssertEqual(f.texte(4), ["001", "010", "011", "100"])
    }
}
