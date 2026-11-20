import XCTest

@testable import KladdeKern

/// Funktionsliste, Autovervollständigung und benutzerdefinierte Sprachen.
final class SprachhilfenTests: XCTestCase {
    /// Die Daten von Notepad++, wenn scripts/extern-bauen.sh sie schon geholt hat.
    private var installer: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("extern/notepad-plus-plus/PowerEditor/installer")
    }

    // MARK: Funktionsliste

    func testUebersetzung() {
        XCTAssertEqual(Funktionsliste.uebersetze(#"^def\x20\K\w+"#), #"^def\x20(?<kladdeK0>)\w+"#)
        XCTAssertEqual(Funktionsliste.uebersetze(#"[\K]\<a\>"#), #"[\K]\ba\b"#, "In Zeichenklassen bleibt \\K stehen")
        XCTAssertEqual(Funktionsliste.uebersetze("(?'n'x)"), "(?<n>x)")
        XCTAssertEqual(Funktionsliste.uebersetze(#"[^[\]"]*"#), #"[^\[\]"]*"#)
        XCTAssertEqual(Funktionsliste.uebersetze(#"[[:alpha:]]x{2}y{"#), #"[[:alpha:]]x{2}y\{"#)
        XCTAssertEqual(Funktionsliste.uebersetze(#"(?<ID>\w+)=(?&ID)"#), #"(?<ID>\w+)=(?:\w+)"#)
        XCTAssertEqual(Funktionsliste.uebersetze(#"(?(DEFINE)(?<Z>\d))(?&Z)+"#), #"(?:\d)+"#)
        XCTAssertEqual(Funktionsliste.uebersetze("(?x) [# ]x # Kommentar (\n"), "(?x) [\\#\\x20]x \n")
        XCTAssertEqual(Funktionsliste.uebersetze(#"(?<A>a)\k'A'"#), #"(?<A>a)\k<A>"#)
    }

    private let python = Data(
        #"""
        <NotepadPlus><functionList>
          <parser displayName="Python" id="python_syntax" commentExpr="(?s:'''.*?''')|(?m-s:#.*?$)">
            <classRange mainExpr="^class\x20\K.*?(?=\n\S|\Z)">
              <className><nameExpr expr="\w+(?=\s*[\(|:])" /></className>
              <function mainExpr="\s(async )?def\x20\K.+?(?=(:\h*$|,\h*$|:\s*#))">
                <functionName><funcNameExpr expr=".*" /></functionName>
              </function>
            </classRange>
            <function mainExpr="^(async )?def\x20\K.+?(?=(:\h*$|,\h*$|:\s*#))">
              <functionName><nameExpr expr=".*" /></functionName>
            </function>
          </parser>
        </functionList></NotepadPlus>
        """#.utf8)

    func testPythonFunktionsliste() throws {
        let liste = try Funktionsliste.lade(xml: python)
        let code = """
            import os
            # def auskommentiert():
            def oben(a, b):
                return a

            class Kladde(Basis):
                def __init__(self):
                    pass

                async def lade(self, pfad):
                    pass
            '''
            def im_text():
            '''
            def unten():
                pass
            """
        let text = Suchtext(code)
        let eintraege = liste.eintraege(in: text)
        XCTAssertEqual(eintraege.map(\.name), ["oben(a, b)", "Kladde", "unten()"])
        XCTAssertEqual(eintraege[1].kinder.map(\.name), ["__init__(self)", "lade(self, pfad)"])
        // Die Stelle zeigt auf den Namen, nicht auf «def».
        let stelle = eintraege[0].stelle
        XCTAssertEqual(String(decoding: text.utf8[stelle..<(stelle + 4)], as: UTF8.self), "oben")
    }

    func testKlasseBisZurSchliessendenKlammer() throws {
        let xml = Data(
            #"""
            <NotepadPlus><functionList>
              <parser displayName="Mini" id="mini" commentExpr="//.*?$">
                <classRange mainExpr="^\s*class\s+\w+\s*\{" openSymbole="\{" closeSymbole="\}">
                  <className><nameExpr expr="class\s+\K\w+" /></className>
                  <function mainExpr="\bfunc\s+\w+">
                    <functionName><funcNameExpr expr="func\s+\K\w+" /></functionName>
                  </function>
                </classRange>
                <function mainExpr="^func\s+\w+">
                  <functionName><nameExpr expr="func\s+\K\w+" /></functionName>
                </function>
              </parser>
            </functionList></NotepadPlus>
            """#.utf8)
        let code = """
            func vorher
            class Ä {
              func eins { if x { } }
              // func kommentar
              func zwei
            }
            func nachher
            """
        let eintraege = try Funktionsliste.lade(xml: xml).eintraege(in: Suchtext(code))
        XCTAssertEqual(eintraege.map(\.name), ["vorher", "Ä", "nachher"])
        XCTAssertEqual(eintraege[1].kinder.map(\.name), ["eins", "zwei"])
    }

    /// Jede Funktionsliste von Notepad++ lässt sich laden; welche ICU nicht versteht, steht in der Meldung.
    func testAlleFunktionslistenVonNotepadPlusPlus() throws {
        let ordner = installer.appendingPathComponent("functionList")
        let dateien = (try? FileManager.default.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil)) ?? []
        try XCTSkipIf(dateien.isEmpty, "Quellcode von Notepad++ fehlt (scripts/extern-bauen.sh)")
        var geladen = 0
        var fehler: [String] = []
        for datei in dateien where datei.pathExtension == "xml" && datei.lastPathComponent != "overrideMap.xml" {
            do {
                _ = try Funktionsliste.lade(datei)
                geladen += 1
            } catch {
                fehler.append("\(datei.lastPathComponent): \(error.localizedDescription)")
            }
        }
        print("Funktionslisten: \(geladen) geladen, \(fehler.count) nicht:\n" + fehler.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(geladen, 40)
    }

    func testEchteFunktionslisteCpp() throws {
        let datei = installer.appendingPathComponent("functionList/cpp.xml")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: datei.path))
        let code = """
            #include <stdio.h>
            /* int versteckt() { } */
            namespace n {
            class Punkt {
            public:
                int x() const { return 1; }
                void setze(int a);
            };
            }
            void Punkt::setze(int a) { }
            static int hilfe(int a, char **b)
            {
                return 0;
            }
            int main(void) { return hilfe(0, 0); }
            """
        let eintraege = try Funktionsliste.lade(datei).eintraege(in: Suchtext(code))
        let alle = eintraege.flatMap { [$0.name] + $0.kinder.map { "  " + $0.name } }
        XCTAssertTrue(alle.contains { $0.contains("hilfe") }, "\(alle)")
        XCTAssertTrue(alle.contains { $0.contains("main") }, "\(alle)")
        XCTAssertFalse(alle.contains { $0.contains("versteckt") }, "\(alle)")
    }

    // MARK: Autovervollständigung

    func testWortschatz() throws {
        let xml = Data(
            """
            <NotepadPlus><AutoComplete>
              <Environment ignoreCase="yes" startFunc="(" stopFunc=")" paramSeparator="," additionalWordChar="." />
              <KeyWord name="print" func="yes">
                <Overload retVal="None" descr="Gibt aus."><Param name="wert" /><Param name="ende=&quot;\\n&quot;" /></Overload>
              </KeyWord>
              <KeyWord name="pass" />
              <KeyWord name="Pfad" />
            </AutoComplete></NotepadPlus>
            """.utf8)
        let w = try Wortschatz.lade(xml: xml)
        XCTAssertTrue(w.ohneGrossKlein)
        XCTAssertEqual(w.wortzeichen, ".")
        XCTAssertEqual(w.vorschlaege(fuer: "p", ausText: ["pfirsich", "Paket"]), ["Paket", "pass", "Pfad", "pfirsich", "print"])
        XCTAssertEqual(w.vorschlaege(fuer: "print", ausText: []), [], "das Wort selbst schlägt sie nicht vor")
        let hilfe = try XCTUnwrap(w.aufrufhilfe(fuer: "print", aktiv: 1))
        XCTAssertEqual(hilfe.text, "None print(wert, ende=\"\\n\")\nGibt aus.")
        let markiert = hilfe.text.utf8.dropFirst(hilfe.hervorheben!.lowerBound).prefix(hilfe.hervorheben!.count)
        XCTAssertEqual(String(decoding: markiert, as: UTF8.self), "ende=\"\\n\"")
        XCTAssertEqual(Wortschatz.woerter(in: "äpfel und 123abc x_y os.path ab"), ["äpfel", "und", "x_y", "path"])
        XCTAssertTrue(Wortschatz.woerter(in: "os.path", zusaetzlich: ".").contains("os.path"))
    }

    func testAlleWortschaetzeVonNotepadPlusPlus() throws {
        let ordner = installer.appendingPathComponent("APIs")
        let dateien = (try? FileManager.default.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil)) ?? []
        try XCTSkipIf(dateien.isEmpty, "Quellcode von Notepad++ fehlt")
        for datei in dateien where datei.pathExtension == "xml" {
            XCTAssertNoThrow(try Wortschatz.lade(datei), datei.lastPathComponent)
        }
        let python = try Wortschatz.lade(ordner.appendingPathComponent("python.xml"))
        XCTAssertTrue(python.vorschlaege(fuer: "isinst", ausText: []).contains("isinstance"))
    }

    // MARK: Benutzerdefinierte Sprachen

    func testBenutzersprache() throws {
        let xml = Data(
            """
            <NotepadPlus>
              <UserLang name="Mini" ext="mini mn" udlVersion="2.1">
                <Settings>
                  <Global caseIgnored="yes" allowFoldOfComments="no" foldCompact="no" forcePureLC="0" decimalSeparator="0" />
                  <Prefix Keywords1="no" Keywords2="yes" Keywords3="no" Keywords4="no" Keywords5="no" Keywords6="no" Keywords7="no" Keywords8="no" />
                </Settings>
                <KeywordLists>
                  <Keywords name="Comments">00# 01 02 03{# 04#}</Keywords>
                  <Keywords name="Keywords1">wenn sonst &quot;end if&quot;</Keywords>
                  <Keywords name="Operators1">+ -</Keywords>
                  <Keywords name="Delimiters">00&quot; 01 02&quot;</Keywords>
                </KeywordLists>
                <Styles>
                  <WordsStyle name="DEFAULT" fgColor="000000" bgColor="FFFFFF" colorStyle="1" fontStyle="0" nesting="0" />
                  <WordsStyle name="KEYWORDS1" fgColor="0000FF" bgColor="FFFFFF" fontStyle="1" nesting="0" />
                  <WordsStyle name="DELIMITERS1" fgColor="808080" bgColor="FFFFFF" fontStyle="0" nesting="1024" />
                </Styles>
              </UserLang>
            </NotepadPlus>
            """.utf8)
        let s = try XCTUnwrap(try Benutzersprache.lade(xml: xml).first)
        XCTAssertEqual(s.name, "Mini")
        XCTAssertEqual(s.endungen, ["mini", "mn"])
        XCTAssertTrue(s.ohneGrossKlein)
        XCTAssertEqual(s.praefix, [false, true, false, false, false, false, false, false])
        XCTAssertEqual(s.listen[19], "wenn sonst \"end if\"")
        XCTAssertEqual(Benutzersprache.aufbereitet(s.listen[19]), "wenn sonst end\u{0B}if")
        XCTAssertEqual(Benutzersprache.aufbereitet("'a b' \\\"x"), "a\u{08}b \"x")
        XCTAssertEqual(s.kommentarzeichen.zeile, "#")
        XCTAssertEqual(s.kommentarzeichen.anfang, "{#")
        XCTAssertEqual(s.kommentarzeichen.ende, "#}")
        XCTAssertEqual(s.stile.first { $0.id == 0 }?.hinten, nil, "colorStyle=1: nur Vordergrund")
        XCTAssertEqual(s.stile.first { $0.id == 4 }?.vorne, 0x0000FF)
        XCTAssertEqual(s.stile.first { $0.id == 16 }?.verschachtelung, 1024)
    }

    func testAlteBenutzerspracheWirdAbgelehnt() {
        let alt = Data(#"<NotepadPlus><UserLang name="Alt" ext="x"></UserLang></NotepadPlus>"#.utf8)
        XCTAssertThrowsError(try Benutzersprache.lade(xml: alt))
    }
}
