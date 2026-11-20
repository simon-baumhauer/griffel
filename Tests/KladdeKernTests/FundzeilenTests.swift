import XCTest

@testable import KladdeKern

final class FundzeilenTests: XCTestCase {
    private func finde(_ suche: String, in inhalt: String, modus: SuchOptionen.Modus = .normal) throws -> [Fundzeile] {
        var o = SuchOptionen()
        o.text = suche
        o.modus = modus
        let text = Suchtext(inhalt)
        return Fundzeilen.aus(try Suchmuster(o).alle(in: text), in: text)
    }

    func testZeilenUndHervorhebungen() throws {
        let zeilen = try finde("ab", in: "xx ab ab\n\tnichts\nüb ab\r\nab")
        XCTAssertEqual(zeilen.map(\.nummer), [1, 3, 4])
        XCTAssertEqual(zeilen[0].text, "xx ab ab")
        XCTAssertEqual(zeilen[0].hervorhebungen, [NSRange(location: 3, length: 2), NSRange(location: 6, length: 2)])
        XCTAssertEqual(zeilen[0].bereiche, [3..<5, 6..<8])
        // «ü» ist ein UTF-16-Zeichen, aber zwei Bytes.
        XCTAssertEqual(zeilen[1].text, "üb ab")
        XCTAssertEqual(zeilen[1].hervorhebungen, [NSRange(location: 3, length: 2)])
        XCTAssertEqual(zeilen[2].text, "ab")
    }

    func testTabsWerdenLeerzeichen() throws {
        XCTAssertEqual(try finde("x", in: "\tx").first?.text, " x")
    }

    func testLangeZeileWirdAusschnitt() throws {
        let lang = String(repeating: "ä", count: 500) + "ZIEL" + String(repeating: "ö", count: 500)
        let zeile = try XCTUnwrap(try finde("ZIEL", in: lang).first)
        XCTAssertTrue(zeile.text.hasPrefix("…"))
        XCTAssertTrue(zeile.text.hasSuffix("…"))
        XCTAssertFalse(zeile.text.contains("\u{FFFD}"), "kein halbes Zeichen am Rand")
        let markiert = (zeile.text as NSString).substring(with: zeile.hervorhebungen[0])
        XCTAssertEqual(markiert, "ZIEL")
    }

    func testTrefferUeberZeilenGehoertZurErsten() throws {
        let zeilen = try finde("a\\nb", in: "xa\nby", modus: .regulaer)
        XCTAssertEqual(zeilen.count, 1)
        XCTAssertEqual(zeilen[0].nummer, 1)
        XCTAssertEqual(zeilen[0].hervorhebungen, [NSRange(location: 1, length: 1)])
    }
}
