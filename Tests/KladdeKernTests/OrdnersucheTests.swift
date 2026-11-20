import XCTest

@testable import KladdeKern

final class OrdnersucheTests: XCTestCase {
    private var ordner: URL!

    override func setUpWithError() throws {
        ordner = FileManager.default.temporaryDirectory.appendingPathComponent("kladde-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: ordner)
    }

    private func lege(_ pfad: String, _ daten: Data) throws {
        let url = ordner.appendingPathComponent(pfad)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try daten.write(to: url)
    }

    private func lege(_ pfad: String, _ text: String) throws { try lege(pfad, Data(text.utf8)) }

    private func namen(_ suche: Ordnersuche) -> [String] {
        suche.dateien().map(suche.relativerPfad)
    }

    private func muster(_ text: String, ersetzung: String = "", modus: SuchOptionen.Modus = .normal) throws -> Suchmuster {
        var o = SuchOptionen()
        o.text = text
        o.ersetzung = ersetzung
        o.modus = modus
        return try Suchmuster(o)
    }

    // MARK: Filter

    func testFilter() {
        let f = Dateifilter("*.swift *.MD; !*Tests.swift !\\build !+\\.git")
        XCTAssertEqual(f.einschliessen, ["*.swift", "*.MD"])
        XCTAssertEqual(f.ausschliessen, ["*Tests.swift"])
        XCTAssertEqual(f.ordnerAus, ["build", ".git"])
        XCTAssertTrue(f.nimmtDatei("Editor.swift"))
        XCTAssertTrue(f.nimmtDatei("readme.md"))
        XCTAssertFalse(f.nimmtDatei("SucheTests.swift"))
        XCTAssertFalse(f.nimmtDatei("bild.png"))
        XCTAssertFalse(f.nimmtOrdner("Build"))
        XCTAssertTrue(f.nimmtOrdner("Sources"))
        XCTAssertTrue(Dateifilter("").nimmtDatei("Makefile"))
        XCTAssertTrue(Dateifilter("*.*").nimmtDatei("Makefile"), "«*.*» nimmt wie unter Windows auch Dateien ohne Punkt")
    }

    func testDateienMitFilterUnterordnernUndVersteckten() throws {
        try lege("a.txt", "x")
        try lege("b.swift", "x")
        try lege("unter/c.txt", "x")
        try lege("build/d.txt", "x")
        try lege(".versteckt/e.txt", "x")
        try lege(".f.txt", "x")

        XCTAssertEqual(namen(Ordnersuche(ordner: ordner, filter: Dateifilter("*.txt !\\build"))), ["a.txt", "unter/c.txt"])
        XCTAssertEqual(namen(Ordnersuche(ordner: ordner, filter: Dateifilter("*.txt"), unterordner: false)), ["a.txt"])
        XCTAssertEqual(
            namen(Ordnersuche(ordner: ordner, filter: Dateifilter("*.txt"), versteckte: true)),
            [".f.txt", ".versteckt/e.txt", "a.txt", "build/d.txt", "unter/c.txt"])
    }

    // MARK: Suchen

    func testDurchsuchenUeberspringtBinaeres() throws {
        try lege("treffer.txt", "eins Bern zwei\nBern")
        try lege("leer.txt", "nichts")
        try lege("binaer.dat", Data([0x42, 0x65, 0x72, 0x6E, 0x00, 0x01]))
        try lege("latin.txt", Data([0x5A, 0xFC, 0x72, 0x69, 0x63, 0x68, 0x20, 0x42, 0x65, 0x72, 0x6E]))  // «Zürich Bern»

        var funde: [String] = []
        let stand = Ordnersuche(ordner: ordner, filter: Dateifilter("")).durchsuche(try muster("bern")) { fund in
            funde.append("\(fund.url.lastPathComponent):\(fund.treffer.count)")
        }
        XCTAssertEqual(funde, ["latin.txt:1", "treffer.txt:2"])
        XCTAssertEqual(stand.geprueft, 4)
        XCTAssertEqual(stand.uebersprungen, 1)
        XCTAssertEqual(stand.dateienMitTreffern, 2)
        XCTAssertEqual(stand.treffer, 3)
    }

    func testAbbrechen() throws {
        for i in 0..<5 { try lege("d\(i).txt", "x") }
        var gefragt = 0
        let stand = Ordnersuche(ordner: ordner, filter: Dateifilter("")).durchsuche(
            try muster("x"), abbrechen: { gefragt += 1; return gefragt > 2 }, fund: { _ in })
        XCTAssertTrue(stand.abgebrochen)
        XCTAssertEqual(stand.geprueft, 2)
    }

    // MARK: Ersetzen

    func testErsetzenHaeltZeichensatzUndRechte() throws {
        // Windows-1252 mit CRLF, ausführbar.
        try lege("skript.cmd", Data([0x5A, 0xFC, 0x72, 0x69, 0x63, 0x68, 0x0D, 0x0A, 0x42, 0x65, 0x72, 0x6E, 0x0D, 0x0A]))
        let url = ordner.appendingPathComponent("skript.cmd")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)

        let anzahl = try Ordnersuche.ersetze(in: url, mit: try muster("Zürich", ersetzung: "Genève"))
        XCTAssertEqual(anzahl, 1)
        let daten = try Data(contentsOf: url)
        XCTAssertEqual(Array(daten), [0x47, 0x65, 0x6E, 0xE8, 0x76, 0x65, 0x0D, 0x0A, 0x42, 0x65, 0x72, 0x6E, 0x0D, 0x0A])
        let rechte = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(rechte, 0o755)
    }

    func testErsetzenOhneTrefferSchreibtNicht() throws {
        try lege("a.txt", "unverändert")
        let url = ordner.appendingPathComponent("a.txt")
        let vorher = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(try Ordnersuche.ersetze(in: url, mit: try muster("fehlt", ersetzung: "x")), 0)
        let nachher = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        XCTAssertEqual(vorher, nachher)
    }

    func testErsetzenNichtDarstellbarWirft() throws {
        try lege("latin.txt", Data([0x5A, 0xFC, 0x72, 0x69, 0x63, 0x68]))
        let url = ordner.appendingPathComponent("latin.txt")
        XCTAssertThrowsError(try Ordnersuche.ersetze(in: url, mit: try muster("Zürich", ersetzung: "😀")))
        XCTAssertEqual(Array(try Data(contentsOf: url)), [0x5A, 0xFC, 0x72, 0x69, 0x63, 0x68], "Datei bleibt, wie sie war")
    }
}
