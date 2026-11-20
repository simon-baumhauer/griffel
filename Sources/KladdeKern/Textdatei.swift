import Foundation

/// Was eine Datei auf der Platte ausmacht, ausser ihrem Text: Zeichensatz und
/// Zeilenende. Im Editor liegt der Text immer als UTF-8; beim Sichern geht er
/// im Zeichensatz zurück, in dem er kam.
public struct Textdatei {
    /// Die Zahlen stehen in der Sitzungsdatei und als «tag» an den Menüeinträgen.
    public enum Kodierung: Int, CaseIterable, Codable {
        case utf8, utf8MitBOM, utf16LE, utf16BE, windows1252

        public var name: String {
            switch self {
            case .utf8: return "UTF-8"
            case .utf8MitBOM: return "UTF-8 mit BOM"
            case .utf16LE: return "UTF-16 LE"
            case .utf16BE: return "UTF-16 BE"
            case .windows1252: return "Windows-1252"
            }
        }

        /// Die Marke, mit der eine Datei dieses Zeichensatzes beginnt.
        public var marke: [UInt8] {
            switch self {
            case .utf8, .windows1252: return []
            case .utf8MitBOM: return [0xEF, 0xBB, 0xBF]
            case .utf16LE: return [0xFF, 0xFE]
            case .utf16BE: return [0xFE, 0xFF]
            }
        }
    }

    /// Die Werte sind die von SCI_SETEOLMODE.
    public enum Zeilenende: Int, CaseIterable, Codable {
        case crlf = 0, cr = 1, lf = 2

        public var name: String {
            switch self {
            case .crlf: return "Windows (CRLF)"
            case .lf: return "Unix und macOS (LF)"
            case .cr: return "Altes Mac OS (CR)"
            }
        }
    }

    public struct NichtDarstellbar: LocalizedError {
        public let kodierung: Kodierung
        public var errorDescription: String? {
            "Der Text enthält Zeichen, die es in \(kodierung.name) nicht gibt."
        }
        public var recoverySuggestion: String? {
            "Entferne die Zeichen oder wähle im Menü «Kodierung» einen anderen Zeichensatz."
        }
    }

    public var utf8 = Data()
    public var kodierung = Kodierung.utf8
    public var zeilenende = Zeilenende.lf

    public init() {}

    /// Liest die Bytes einer Datei. Ohne «als» wird der Zeichensatz erkannt;
    /// mit «als» gilt der genannte, was auch immer in der Datei steht.
    public init(daten: Data, als erzwungen: Kodierung? = nil) {
        if let erzwungen {
            kodierung = erzwungen
            let marke = erzwungen.marke
            let rumpf = !marke.isEmpty && daten.starts(with: marke) ? daten.dropFirst(marke.count) : daten
            utf8 = Self.alsUTF8(Data(rumpf), erzwungen)
        } else {
            let (erkannt, rumpf) = Self.erkenne(daten)
            kodierung = erkannt
            utf8 = Self.alsUTF8(rumpf, erkannt)
        }
        zeilenende = Self.zeilenende(in: utf8)
    }

    /// Der Text im Zeichensatz der Datei, mit ihrer Marke am Anfang.
    public func kodiert() throws -> Data {
        let rumpf: Data?
        switch kodierung {
        case .utf8, .utf8MitBOM:
            rumpf = utf8
        case .utf16LE:
            rumpf = String(decoding: utf8, as: UTF8.self).data(using: .utf16LittleEndian)
        case .utf16BE:
            rumpf = String(decoding: utf8, as: UTF8.self).data(using: .utf16BigEndian)
        case .windows1252:
            rumpf = String(decoding: utf8, as: UTF8.self).data(using: .windowsCP1252)
        }
        guard let rumpf else { throw NichtDarstellbar(kodierung: kodierung) }
        return Data(kodierung.marke) + rumpf
    }

    private static func alsUTF8(_ rumpf: Data, _ kodierung: Kodierung) -> Data {
        switch kodierung {
        case .utf8, .utf8MitBOM:
            // Ungültige Folgen (nur bei erzwungenem Zeichensatz) werden zu «�».
            return String(data: rumpf, encoding: .utf8) != nil ? rumpf : Data(String(decoding: rumpf, as: UTF8.self).utf8)
        case .utf16LE:
            return Data((String(data: rumpf, encoding: .utf16LittleEndian) ?? "").utf8)
        case .utf16BE:
            return Data((String(data: rumpf, encoding: .utf16BigEndian) ?? "").utf8)
        case .windows1252:
            // Windows-1252 lässt fünf Bytes frei; Foundation lehnt die Datei dann
            // ab. Latin-1 belegt alle 256 und liest darum jede Datei.
            let text = String(data: rumpf, encoding: .windowsCP1252) ?? String(data: rumpf, encoding: .isoLatin1)
            return Data((text ?? "").utf8)
        }
    }

    /// Marke am Anfang, sonst gültiges UTF-8, sonst Windows-1252.
    private static func erkenne(_ daten: Data) -> (Kodierung, Data) {
        for kodierung in [Kodierung.utf8MitBOM, .utf16LE, .utf16BE] where daten.starts(with: kodierung.marke) {
            return (kodierung, Data(daten.dropFirst(kodierung.marke.count)))
        }
        if String(data: daten, encoding: .utf8) != nil { return (.utf8, daten) }
        return (.windows1252, daten)
    }

    /// Das erste Zeilenende der Datei gilt für neue Zeilen. Ohne eines: LF.
    private static func zeilenende(in utf8: Data) -> Zeilenende {
        guard let stelle = utf8.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) else { return .lf }
        if utf8[stelle] == 0x0A { return .lf }
        let danach = utf8.index(after: stelle)
        return danach < utf8.endIndex && utf8[danach] == 0x0A ? .crlf : .cr
    }
}
