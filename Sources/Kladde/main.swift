import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var zwischensicherung: Timer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Menue.baue(appName: "Kladde")
        // Vor den Dateien, die der Finder zum Öffnen schickt: Die landen als
        // weitere Tabs hinter der Sitzung.
        Sitzung.stelleWiederHer()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Auch ein Absturz verliert höchstens die letzten Sekunden.
        zwischensicherung = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Sitzung.sichere()
        }
        Probe.starteFallsVerlangt()
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

    // MARK: Menü «Suchen» (gilt auch ohne offenes Dokument)

    @objc func zeigeDateiSuche(_ sender: Any?) {
        let vorne = NSApp.orderedWindows.lazy.compactMap { $0.windowController?.document as? Dokument }.first
        DateiSuche.gemeinsam.zeige(ordnerVon: vorne)
    }

    @objc func zeigeSuchergebnisse(_ sender: Any?) {
        Suchergebnisse.gemeinsam.showWindow(nil)
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
