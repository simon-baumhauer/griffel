import XCTest

@testable import KladdeKern

final class TextdateiTests: XCTestCase {
    func testErkennung() {
        XCTAssertEqual(Textdatei(daten: Data("ä\n".utf8)).kodierung, .utf8)
        XCTAssertEqual(Textdatei(daten: Data([0xEF, 0xBB, 0xBF, 0x61])).kodierung, .utf8MitBOM)
        XCTAssertEqual(Textdatei(daten: Data([0xFF, 0xFE, 0x61, 0x00])).kodierung, .utf16LE)
        XCTAssertEqual(Textdatei(daten: Data([0xFE, 0xFF, 0x00, 0x61])).kodierung, .utf16BE)
        let latin = Textdatei(daten: Data([0x5A, 0xFC, 0x72, 0x80]))
        XCTAssertEqual(latin.kodierung, .windows1252)
        XCTAssertEqual(String(decoding: latin.utf8, as: UTF8.self), "Zür€")
    }

    func testZeilenende() {
        XCTAssertEqual(Textdatei(daten: Data("a\r\nb".utf8)).zeilenende, .crlf)
        XCTAssertEqual(Textdatei(daten: Data("a\rb".utf8)).zeilenende, .cr)
        XCTAssertEqual(Textdatei(daten: Data("a\nb".utf8)).zeilenende, .lf)
        XCTAssertEqual(Textdatei(daten: Data("ab".utf8)).zeilenende, .lf)
    }

    func testHinUndZurueck() throws {
        for kodierung in Textdatei.Kodierung.allCases {
            var datei = Textdatei()
            datei.utf8 = Data("Grüezi €\r\n".utf8)
            datei.kodierung = kodierung
            let gelesen = Textdatei(daten: try datei.kodiert())
            XCTAssertEqual(gelesen.kodierung, kodierung, kodierung.name)
            XCTAssertEqual(gelesen.utf8, datei.utf8, kodierung.name)
        }
    }

    func testNichtDarstellbar() {
        var datei = Textdatei()
        datei.utf8 = Data("😀".utf8)
        datei.kodierung = .windows1252
        XCTAssertThrowsError(try datei.kodiert())
    }

    func testErzwungen() {
        // UTF-16-Marke als Windows-1252 gelesen: zwei Zeichen ÿþ, dann Bytes.
        let daten = Data([0xFF, 0xFE, 0x61, 0x00])
        let als1252 = Textdatei(daten: daten, als: .windows1252)
        XCTAssertEqual(String(decoding: als1252.utf8, as: UTF8.self), "ÿþa\0")
        XCTAssertEqual(Textdatei(daten: daten, als: .utf16LE).utf8, Data("a".utf8))
    }
}
