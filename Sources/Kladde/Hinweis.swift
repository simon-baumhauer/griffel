import AppKit

/// Der Hinweis über einem Knopf, wenn die Maus kurz darauf verweilt: Name des
/// Befehls und Kürzel fett, darunter in einem Satz, was er tut. Schneller und
/// ausführlicher als ein Tooltip von macOS; hell oder dunkel wie das Fenster.
final class Hinweis {
    static let gemeinsam = Hinweis()

    private let fenster: NSPanel
    var fensterFuerProbe: NSWindow { fenster }
    private let feld = NSTextField(wrappingLabelWithString: "")
    private var zeitgeber: Timer?
    private weak var anker: NSView?
    /// Ist gerade ein Hinweis zu sehen, kommt der nächste ohne Wartezeit (wie unter Windows).
    private var zuletztSichtbar = Date.distantPast

    private init() {
        fenster = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        fenster.isFloatingPanel = true
        fenster.level = .popUpMenu
        fenster.hasShadow = true
        fenster.isOpaque = false
        fenster.backgroundColor = .clear
        fenster.ignoresMouseEvents = true
        let kasten = NSView()
        kasten.wantsLayer = true
        kasten.layer?.cornerRadius = 3
        kasten.layer?.borderWidth = 1
        feld.translatesAutoresizingMaskIntoConstraints = false
        feld.preferredMaxLayoutWidth = 300
        kasten.addSubview(feld)
        NSLayoutConstraint.activate([
            feld.leadingAnchor.constraint(equalTo: kasten.leadingAnchor, constant: 7),
            feld.trailingAnchor.constraint(equalTo: kasten.trailingAnchor, constant: -7),
            feld.topAnchor.constraint(equalTo: kasten.topAnchor, constant: 4),
            feld.bottomAnchor.constraint(equalTo: kasten.bottomAnchor, constant: -5),
        ])
        fenster.contentView = kasten
    }

    /// Zeigt den Hinweis nach kurzer Pause unter `ansicht`.
    func plane(fuer ansicht: NSView, titel: String, kuerzel: String?, text: String?) {
        verberge()
        anker = ansicht
        let sofort = Date().timeIntervalSince(zuletztSichtbar) < 0.6
        zeitgeber = Timer.scheduledTimer(withTimeInterval: sofort ? 0.05 : 0.5, repeats: false) { [weak self] _ in
            self?.zeige(titel: titel, kuerzel: kuerzel, text: text)
        }
    }

    func verberge() {
        zeitgeber?.invalidate()
        zeitgeber = nil
        if fenster.isVisible {
            zuletztSichtbar = Date()
            fenster.orderOut(nil)
        }
    }

    private func zeige(titel: String, kuerzel: String?, text: String?) {
        guard let anker, let haupt = anker.window, haupt.isVisible else { return }
        let dunkel = Hauptfenster.istDunkel
        let vorne: NSColor = dunkel ? NSColor(rgb: 0xE8E8E8) : NSColor(rgb: 0x1E1E1E)
        let leise: NSColor = dunkel ? NSColor(rgb: 0xA8A8A8) : NSColor(rgb: 0x5E5E5E)
        let s = NSMutableAttributedString(string: titel, attributes: [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: vorne])
        if let kuerzel {
            s.append(NSAttributedString(string: "   " + kuerzel, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: leise]))
        }
        if let text {
            let absatz = NSMutableParagraphStyle()
            absatz.paragraphSpacingBefore = 3
            s.append(NSAttributedString(string: "\n" + text, attributes: [
                .font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: vorne, .paragraphStyle: absatz,
            ]))
        }
        feld.attributedStringValue = s
        let kasten = fenster.contentView!
        kasten.layer?.backgroundColor = (dunkel ? NSColor(rgb: 0x2B2B2B) : NSColor(rgb: 0xFFFFFF)).cgColor
        kasten.layer?.borderColor = (dunkel ? NSColor(rgb: 0x555555) : NSColor(rgb: 0xC8C8C8)).cgColor
        let groesse = feld.fittingSize
        let rahmen = NSSize(width: ceil(groesse.width) + 14, height: ceil(groesse.height) + 9)
        // Unter dem Knopf, nach links verschoben, wenn der Bildschirm rechts endet.
        let aufSchirm = haupt.convertToScreen(anker.convert(anker.bounds, to: nil))
        var ursprung = NSPoint(x: aufSchirm.minX, y: aufSchirm.minY - rahmen.height - 4)
        if let schirm = haupt.screen?.visibleFrame {
            ursprung.x = min(ursprung.x, schirm.maxX - rahmen.width - 4)
            if ursprung.y < schirm.minY { ursprung.y = aufSchirm.maxY + 4 }
        }
        fenster.setFrame(NSRect(origin: ursprung, size: rahmen), display: true)
        fenster.orderFront(nil)
    }
}
