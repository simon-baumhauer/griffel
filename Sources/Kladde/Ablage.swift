import Foundation

/// Der Ordner von NoteMac++ unter ~/Library/Application Support, mit der Sitzung
/// und den benutzerdefinierten Sprachen.
///
/// Bis Version 1.4 hiess die App «Kladde», in 1.5 «Griffel». Gibt es nur einen
/// alten Ordner, zieht er beim ersten Zugriff um, der von Griffel vor dem von
/// Kladde; gelingt das nicht, bleibt er in Gebrauch, damit Sitzung und Sprachen
/// nicht verloren scheinen. Gibt es den neuen schon, gilt er.
/// Mit «-KladdeAblage /pfad» beim Start steht /pfad für Application Support (für Prüfläufe).
enum Ablage {
    static let ordner: URL = {
        let dateien = FileManager.default
        let basis = UserDefaults.standard.string(forKey: "KladdeAblage").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? dateien.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let neu = basis.appendingPathComponent("NoteMac++", isDirectory: true)
        guard !dateien.fileExists(atPath: neu.path) else { return neu }
        for name in ["Griffel", "Kladde"] {
            let alt = basis.appendingPathComponent(name, isDirectory: true)
            guard dateien.fileExists(atPath: alt.path) else { continue }
            do {
                try dateien.moveItem(at: alt, to: neu)
                return neu
            } catch {
                NSLog("NoteMac++: Der Ordner %@ liess sich nicht umbenennen (%@); er bleibt in Gebrauch.", alt.path, error.localizedDescription)
                return alt
            }
        }
        return neu
    }()
}
