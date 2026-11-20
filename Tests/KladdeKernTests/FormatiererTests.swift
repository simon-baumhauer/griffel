import XCTest
@testable import KladdeKern

final class FormatiererTests: XCTestCase {
    func testJSONFormatierenBehaeltReihenfolgeUndZahlen() throws {
        let roh = #"{"z":1.50,"a":[true,null,{"x":"a\"b"}],"leer":{},"l":[]}"#
        XCTAssertEqual(try JSONWerkzeug.formatiere(roh, einzug: "  "), """
            {
              "z": 1.50,
              "a": [
                true,
                null,
                {
                  "x": "a\\"b"
                }
              ],
              "leer": {},
              "l": []
            }
            """)
    }

    func testJSONKomprimieren() throws {
        XCTAssertEqual(try JSONWerkzeug.komprimiere("{ \"a\" : [ 1 , 2 ],\n \"b\": \"x y\" }"), #"{"a":[1,2],"b":"x y"}"#)
    }

    func testJSONFehlerNenntStelle() {
        XCTAssertThrowsError(try JSONWerkzeug.lies("{\n  \"a\": 1,\n  \"b\" 2\n}")) { f in
            let f = f as! Formatfehler
            XCTAssertEqual(f.zeile, 3)
            XCTAssertEqual(f.spalte, 7)
        }
        XCTAssertThrowsError(try JSONWerkzeug.lies("[1,]"))
        XCTAssertThrowsError(try JSONWerkzeug.lies("{\"a\":01}"))
        XCTAssertThrowsError(try JSONWerkzeug.lies("[1] x"))
    }

    func testXMLFormatieren() {
        let roh = #"<?xml version="1.0"?><a x="1>2"><b>Text</b><c/><!-- k --><d><e></e></d></a>"#
        XCTAssertEqual(XMLWerkzeug.formatiere(roh, einzug: "  "), """
            <?xml version="1.0"?>
            <a x="1>2">
              <b>Text</b>
              <c/>
              <!-- k -->
              <d>
                <e></e>
              </d>
            </a>
            """)
        XCTAssertEqual(XMLWerkzeug.linearisiere("<a>\n  <b> x </b>\n</a>\n"), "<a><b>x</b></a>")
    }

    func testXMLPruefen() {
        XCTAssertNil(XMLWerkzeug.pruefe("<a><b/></a>"))
        let f = XMLWerkzeug.pruefe("<a>\n<b></a>")
        XCTAssertEqual(f?.zeile, 2)
    }

    func testMIMEUndHex() {
        XCTAssertEqual(Kodierwerkzeug.base64("Grüezi"), "R3LDvGV6aQ==")
        XCTAssertEqual(Kodierwerkzeug.ausBase64("R3LDvGV6aQ"), "Grüezi")
        XCTAssertNil(Kodierwerkzeug.ausBase64("@@@"))
        XCTAssertEqual(Kodierwerkzeug.url("a b&c=ü"), "a%20b%26c%3D%C3%BC")
        XCTAssertEqual(Kodierwerkzeug.ausURL("a%20b+c"), "a b c")
        XCTAssertEqual(Kodierwerkzeug.hex("Hi"), "4869")
        XCTAssertEqual(Kodierwerkzeug.ausHex("48 69"), "Hi")
        XCTAssertNil(Kodierwerkzeug.ausHex("4"))
    }
}
