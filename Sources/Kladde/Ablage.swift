import Foundation

/// Der Ordner von Griffel unter ~/Library/Application Support, mit der Sitzung
/// und den benutzerdefinierten Sprachen.
///
/// Bis Version 1.4 hiess die App «Kladde». Gibt es nur den alten Ordner, zieht er
/// beim ersten Zugriff um; gelingt das nicht, bleibt er in Gebrauch, damit
/// Sitzung und Sprachen nicht verloren scheinen. Gibt es beide, gilt der neue.
/// Mit «-KladdeAblage /pfad» beim Start steht /pfad für Application Support (für Prüfläufe).
enum Ablage {
    static let ordner: URL = {
        let dateien = FileManager.default
        let basis = UserDefaults.standard.string(forKey: "KladdeAblage").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? dateien.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let neu = basis.appendingPathComponent("Griffel", isDirectory: true)
        let alt = basis.appendingPathComponent("Kladde", isDirectory: true)
        guard !dateien.fileExists(atPath: neu.path), dateien.fileExists(atPath: alt.path) else { return neu }
        do {
            try dateien.moveItem(at: alt, to: neu)
            return neu
        } catch {
            NSLog("Griffel: Der Ordner %@ liess sich nicht umbenennen (%@); er bleibt in Gebrauch.", alt.path, error.localizedDescription)
            return alt
        }
    }()
}
