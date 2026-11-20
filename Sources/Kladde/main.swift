import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var zwischensicherung: Timer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Befehlsmenue.baue()
        // Ein Fenster für alles, wie in Notepad++.
        let haupt = Hauptfenster.gemeinsam
        Panels.gemeinsam.anwenden()
        haupt.ordneDocks()
        // Vor den Dateien, die der Finder zum Öffnen schickt: Die landen als
        // weitere Tabs hinter der Sitzung.
        Sitzung.stelleWiederHer()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Auch ein Absturz verliert höchstens die letzten Sekunden («Sitzungen zeitgesteuert speichern»).
        planeZwischensicherung()
        NotificationCenter.default.addObserver(forName: Einstellungen.geaendert, object: nil, queue: .main) { [weak self] _ in
            self?.planeZwischensicherung()
        }
        Hauptfenster.gemeinsam.showWindow(nil)
        Probe.starteFallsVerlangt()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Hauptfenster.gemeinsam.showWindow(nil)
        return true
    }

    private var geplanteSekunden = 0

    private func planeZwischensicherung() {
        let sekunden = Einstellungen.zwischensicherung && Einstellungen.sitzungMerken ? Einstellungen.zwischensicherungSekunden : 0
        guard sekunden != geplanteSekunden else { return }
        geplanteSekunden = sekunden
        zwischensicherung?.invalidate()
        zwischensicherung = sekunden == 0 ? nil : Timer.scheduledTimer(withTimeInterval: TimeInterval(sekunden), repeats: true) { _ in
            Sitzung.sichere()
        }
    }

    /// Auch ohne ungesicherte Dokumente: Dann fragt macOS gar nicht erst nach
    /// (reviewUnsavedDocuments in Dokumente bleibt aus), und die Sitzung wäre
    /// so alt wie die letzte Zwischensicherung.
    func applicationWillTerminate(_ notification: Notification) {
        Sitzung.sichere()
    }

    /// Start ohne Datei und ohne Sitzung: ein leeres Dokument, wie «new 1» in Notepad++.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSDocumentController.shared.documents.isEmpty
    }

    /// «Über Kladde» mit Herkunft und Lizenzen.
    @objc func zeigeUeber(_ sender: Any?) {
        let text = """
            Ein Texteditor für den Mac nach dem Vorbild von Notepad++.

            Editor-Kern: Scintilla und Lexilla von Neil Hodgson. Sprachen, Farbschemata, \
            Funktionslisten und Autovervollständigung: aus Notepad++ von Don Ho und Mitwirkenden.

            Freie Software unter der GPL v3.
            github.com/simon-baumhauer/kladde
            """
        let absatz = NSMutableParagraphStyle()
        absatz.alignment = .center
        let mitwirkende = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor, .paragraphStyle: absatz,
        ])
        let link = (text as NSString).range(of: "github.com/simon-baumhauer/kladde")
        mitwirkende.addAttribute(.link, value: URL(string: "https://github.com/simon-baumhauer/kladde")!, range: link)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: mitwirkende])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func zeigeEinstellungen(_ sender: Any?) {
        EinstellungsFenster.gemeinsam.zeige()
    }

    // MARK: Befehl fürs Terminal

    /// Legt das Skript «kladde» in einen Ordner im PATH: zuerst den von
    /// Homebrew, wenn er beschreibbar ist, sonst ~/.local/bin. Fragt vorher.
    @objc func installiereBefehl(_ sender: Any?) {
        guard let quelle = Bundle.main.url(forResource: "kladde", withExtension: nil) else { return NSSound.beep() }
        let dateien = FileManager.default
        let heim = dateien.homeDirectoryForCurrentUser
        let kandidaten = ["/opt/homebrew/bin", "/usr/local/bin"].map { URL(fileURLWithPath: $0) }
        let ordner = kandidaten.first { dateien.isWritableFile(atPath: $0.path) }
            ?? heim.appendingPathComponent(".local/bin", isDirectory: true)
        let ziel = ordner.appendingPathComponent("kladde")
        let imPfad = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").contains { $0 == ordner.path }

        let frage = NSAlert()
        frage.messageText = "Befehl «kladde» installieren?"
        frage.informativeText = """
            Kladde legt das Skript nach \((ziel.path as NSString).abbreviatingWithTildeInPath)\
            \(dateien.fileExists(atPath: ziel.path) ? " (die vorhandene Datei wird ersetzt)" : "").
            Danach öffnet «kladde datei.txt» die Datei in Kladde; eine fehlende Datei legt der Befehl leer an.
            """
        frage.addButton(withTitle: "Installieren")
        frage.addButton(withTitle: "Abbrechen")
        guard frage.runModal() == .alertFirstButtonReturn else { return }
        do {
            try dateien.createDirectory(at: ordner, withIntermediateDirectories: true)
            if dateien.fileExists(atPath: ziel.path) { try dateien.removeItem(at: ziel) }
            try dateien.copyItem(at: quelle, to: ziel)
            try dateien.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ziel.path)
            let fertig = NSAlert()
            fertig.messageText = "«kladde» ist installiert"
            fertig.informativeText = imPfad
                ? "Im Terminal: kladde datei.txt"
                : "\(ordner.path) steht noch nicht im PATH. In ~/.zshrc ergänzen:\nexport PATH=\"\(ordner.path):$PATH\""
            fertig.runModal()
        } catch {
            NSApp.presentError(error)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

// Wer zuerst entsteht, ist NSDocumentController.shared: unsere Unterklasse
// muss vor NSApplication da sein.
_ = Dokumente()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
