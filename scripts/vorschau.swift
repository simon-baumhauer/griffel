// Zeichnet das Vorschaubild für geteilte Links auf das Repo (GitHub → Settings →
// General → Social preview): 1280 × 640, dunkler Grund wie die Wortmarke im
// Logo-Entwurf, links Icon, Name, Kurztext und der Befehl für Homebrew, rechts
// das Fenster aus dem README.
//
//   swift scripts/vorschau.swift [docs/bilder/vorschau.png]
//
// Aus dem Hauptordner aufrufen; liest Ressourcen/Griffel.png und
// docs/bilder/griffel.png. Braucht nur macOS (CoreGraphics, CoreText).
import AppKit
import CoreText
import Foundation

let breite = 1280, hoehe = 640
let ziel = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/bilder/vorschau.png")

func farbe(_ rgb: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
        blue: CGFloat(rgb & 0xFF) / 255, alpha: a)
}

func bild(_ pfad: String) -> CGImage {
    guard let quelle = CGImageSourceCreateWithURL(URL(fileURLWithPath: pfad) as CFURL, nil),
          let bild = CGImageSourceCreateImageAtIndex(quelle, 0, nil) else {
        FileHandle.standardError.write(Data("\(pfad) fehlt; aus dem Hauptordner von Griffel aufrufen.\n".utf8))
        exit(1)
    }
    return bild
}

let k = CGContext(
    data: nil, width: breite, height: hoehe, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
k.interpolationQuality = .high
// Gezeichnet wird von oben nach unten; CoreGraphics zählt von unten.
func y(_ vonOben: CGFloat) -> CGFloat { CGFloat(hoehe) - vonOben }

// Grund: Anthrazit, nach unten etwas dunkler.
let verlauf = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [farbe(0x24262A), farbe(0x19191C)] as CFArray,
    locations: [0, 1])!
k.drawLinearGradient(verlauf, start: CGPoint(x: 0, y: y(0)), end: CGPoint(x: 0, y: y(640)), options: [])

// Rechts das Fenster, rund abgeschnitten, mit Schatten; es läuft über den Rand hinaus.
let fenster = bild("docs/bilder/griffel.png")
let fensterBreite: CGFloat = 780
let fensterHoehe = fensterBreite * CGFloat(fenster.height) / CGFloat(fenster.width)
let fensterRahmen = CGRect(x: 660, y: y(84) - fensterHoehe, width: fensterBreite, height: fensterHoehe)
let rund = CGPath(roundedRect: fensterRahmen, cornerWidth: 12, cornerHeight: 12, transform: nil)
k.saveGState()
k.setShadow(offset: CGSize(width: 0, height: -18), blur: 48, color: farbe(0x000000, 0.55))
k.addPath(rund)
k.setFillColor(farbe(0xECECEC))
k.fillPath()
k.restoreGState()
k.saveGState()
k.addPath(rund)
k.clip()
k.draw(fenster, in: fensterRahmen)
k.restoreGState()
k.addPath(rund)
k.setStrokeColor(farbe(0xFFFFFF, 0.10))
k.setLineWidth(1)
k.strokePath()

// Links das Icon. Die PNG hat Apples Rand von 100 auf 1024; die Fläche selbst
// beginnt bündig mit dem Text.
let links: CGFloat = 88
let icon = bild("Ressourcen/Griffel.png")
let flaeche: CGFloat = 140
let iconGroesse = flaeche * 1024 / 824
let iconRand = iconGroesse * 100 / 1024
k.draw(icon, in: CGRect(x: links - iconRand, y: y(112) - iconGroesse + iconRand, width: iconGroesse, height: iconGroesse))

// Schrift: eine Zeile an einer Grundlinie (von oben gemessen).
@discardableResult
func zeile(_ text: String, _ schrift: NSFont, _ f: CGColor, x: CGFloat, grundlinie: CGFloat) -> CGFloat {
    let a = NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): schrift,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): f,
    ])
    let l = CTLineCreateWithAttributedString(a)
    k.textPosition = CGPoint(x: x, y: y(grundlinie))
    CTLineDraw(l, k)
    return CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil))
}

let papier = farbe(0xF7F4EC), grau = farbe(0xB4B9C2), bernstein = farbe(0xF2B035)
zeile("Griffel", NSFont.systemFont(ofSize: 96, weight: .semibold), papier, x: links - 4, grundlinie: 352)
zeile("Texteditor für den Mac", NSFont.systemFont(ofSize: 34, weight: .regular), grau, x: links, grundlinie: 408)
zeile("nach dem Vorbild von Notepad++", NSFont.systemFont(ofSize: 34, weight: .regular), grau, x: links, grundlinie: 452)

// Der Befehl für Homebrew in einer Pille.
let mono = NSFont.monospacedSystemFont(ofSize: 17, weight: .regular)
let befehl = "brew install --cask simon-baumhauer/tap/griffel"
let probe = CTLineCreateWithAttributedString(NSAttributedString(string: "$ " + befehl, attributes: [
    NSAttributedString.Key(kCTFontAttributeName as String): mono,
]))
let textBreite = CGFloat(CTLineGetTypographicBounds(probe, nil, nil, nil))
let pille = CGRect(x: links, y: y(530), width: textBreite + 36, height: 46)
k.addPath(CGPath(roundedRect: pille, cornerWidth: 10, cornerHeight: 10, transform: nil))
k.setFillColor(farbe(0x2B2D33))
k.fillPath()
k.addPath(CGPath(roundedRect: pille, cornerWidth: 10, cornerHeight: 10, transform: nil))
k.setStrokeColor(farbe(0xFFFFFF, 0.07))
k.strokePath()
let dollar = zeile("$ ", mono, bernstein, x: links + 18, grundlinie: 513)
zeile(befehl, mono, farbe(0xE6E2D8), x: links + 18 + dollar, grundlinie: 513)
if pille.maxX > fensterRahmen.minX - 16 {
    FileHandle.standardError.write(Data("Der Befehl ist zu breit: Pille endet bei \(Int(pille.maxX)).\n".utf8))
    exit(1)
}

let ergebnis = NSBitmapImageRep(cgImage: k.makeImage()!)
try ergebnis.representation(using: .png, properties: [:])!.write(to: ziel)
print("fertig: \(ziel.path) (\(breite) × \(hoehe))")
