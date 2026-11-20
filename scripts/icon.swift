// Zeichnet das Icon von Kladde, Vorschlag A «Klammer-K» (Design-Canvas
// «Kladde Logos», 20.11.2026): ein K aus Stamm und spitzer Klammer «<» in
// Cremeweiss auf Tintenblau, dahinter die Einfügemarke in Bernstein.
//
//   swift scripts/icon.swift Ressourcen/Kladde.icns
//
// Schreibt Kladde.icns (alle Grössen von 16 bis 1024 Pixel) und daneben
// Kladde.png (1024 × 1024). Braucht nur macOS (CoreGraphics, iconutil).
import AppKit
import Foundation

let ziel = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Kladde.icns")
let arbeit = FileManager.default.temporaryDirectory.appendingPathComponent("kladde-icon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: arbeit, withIntermediateDirectories: true)

func farbe(_ rgb: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
        blue: CGFloat(rgb & 0xFF) / 255, alpha: a)
}

let tinte: UInt32 = 0x17324D
let creme: UInt32 = 0xF6F1E6
let bernstein: UInt32 = 0xF2A93B

/// Die Form der macOS-Icons: ein Quadrat mit fliessenden («kontinuierlichen»)
/// Ecken statt Viertelkreisen. Die Kurve beginnt 1,528 × r vor der Ecke; die
/// Werte sind die übliche Nachbildung der Ecken von Apple.
func flaeche(_ r: CGRect, radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let a = 1.52866483 * radius, b = 1.08849296 * radius, c = 0.86840694 * radius
    let d = 0.63149399 * radius, e = 0.07491100 * radius, f = 0.37282383 * radius, g = 0.16905899 * radius
    p.move(to: CGPoint(x: r.minX + a, y: r.minY))
    // oben rechts
    p.addLine(to: CGPoint(x: r.maxX - a, y: r.minY))
    p.addCurve(to: CGPoint(x: r.maxX - d, y: r.minY + e), control1: CGPoint(x: r.maxX - b, y: r.minY), control2: CGPoint(x: r.maxX - c, y: r.minY))
    p.addCurve(to: CGPoint(x: r.maxX - e, y: r.minY + d), control1: CGPoint(x: r.maxX - f, y: r.minY + g), control2: CGPoint(x: r.maxX - g, y: r.minY + f))
    p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + a), control1: CGPoint(x: r.maxX, y: r.minY + c), control2: CGPoint(x: r.maxX, y: r.minY + b))
    // unten rechts
    p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - a))
    p.addCurve(to: CGPoint(x: r.maxX - e, y: r.maxY - d), control1: CGPoint(x: r.maxX, y: r.maxY - b), control2: CGPoint(x: r.maxX, y: r.maxY - c))
    p.addCurve(to: CGPoint(x: r.maxX - d, y: r.maxY - e), control1: CGPoint(x: r.maxX - g, y: r.maxY - f), control2: CGPoint(x: r.maxX - f, y: r.maxY - g))
    p.addCurve(to: CGPoint(x: r.maxX - a, y: r.maxY), control1: CGPoint(x: r.maxX - c, y: r.maxY), control2: CGPoint(x: r.maxX - b, y: r.maxY))
    // unten links
    p.addLine(to: CGPoint(x: r.minX + a, y: r.maxY))
    p.addCurve(to: CGPoint(x: r.minX + d, y: r.maxY - e), control1: CGPoint(x: r.minX + b, y: r.maxY), control2: CGPoint(x: r.minX + c, y: r.maxY))
    p.addCurve(to: CGPoint(x: r.minX + e, y: r.maxY - d), control1: CGPoint(x: r.minX + f, y: r.maxY - g), control2: CGPoint(x: r.minX + g, y: r.maxY - f))
    p.addCurve(to: CGPoint(x: r.minX, y: r.maxY - a), control1: CGPoint(x: r.minX, y: r.maxY - c), control2: CGPoint(x: r.minX, y: r.maxY - b))
    // oben links
    p.addLine(to: CGPoint(x: r.minX, y: r.minY + a))
    p.addCurve(to: CGPoint(x: r.minX + e, y: r.minY + d), control1: CGPoint(x: r.minX, y: r.minY + b), control2: CGPoint(x: r.minX, y: r.minY + c))
    p.addCurve(to: CGPoint(x: r.minX + d, y: r.minY + e), control1: CGPoint(x: r.minX + g, y: r.minY + f), control2: CGPoint(x: r.minX + f, y: r.minY + g))
    p.addCurve(to: CGPoint(x: r.minX + a, y: r.minY), control1: CGPoint(x: r.minX + c, y: r.minY), control2: CGPoint(x: r.minX + b, y: r.minY))
    p.closeSubpath()
    return p
}

/// Das K als eine Fläche: Stamm, Arm (die obere Hälfte der Klammer) und Bein.
/// Arm und Bein greifen ein Stück in ihre Nachbarn, damit an den Stössen keine
/// Haarlinie stehen bleibt. Masse wie im Entwurf (Raster 1024, oben links 0/0).
func kaa() -> CGPath {
    let p = CGMutablePath()
    p.addPath(CGPath(roundedRect: CGRect(x: 222, y: 276, width: 96, height: 472), cornerWidth: 8, cornerHeight: 8, transform: nil))
    p.addLines(between: [CGPoint(x: 300, y: 540.4), CGPoint(x: 533, y: 276), CGPoint(x: 653, y: 276), CGPoint(x: 300, y: 676.4)])
    p.closeSubpath()
    p.addLines(between: [CGPoint(x: 377.2, y: 576.8), CGPoint(x: 439.7, y: 506.0), CGPoint(x: 653, y: 748), CGPoint(x: 528, y: 748)])
    p.closeSubpath()
    return p
}

/// Zeichnet in einem Raster von 1024 × 1024 (Apples Vorlage: Inhalt 824 × 824 mit Rand 100).
func zeichne(_ k: CGContext) {
    k.saveGState()
    k.translateBy(x: 0, y: 1024)
    k.scaleBy(x: 1, y: -1)  // oben links ist 0/0

    // Fläche mit dem Schatten der macOS-Icons.
    let form = flaeche(CGRect(x: 100, y: 100, width: 824, height: 824), radius: 185)
    k.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: farbe(0x000000, 0.35))
    k.addPath(form)
    k.setFillColor(farbe(tinte))
    k.fillPath()
    k.setShadow(offset: .zero, blur: 0, color: nil)

    // Das K, eine Fläche (Regel «nonzero» vereinigt Stamm, Arm und Bein).
    k.addPath(kaa())
    k.setFillColor(farbe(creme))
    k.fillPath(using: .winding)

    // Die Einfügemarke.
    k.addPath(CGPath(roundedRect: CGRect(x: 683, y: 704, width: 120, height: 44), cornerWidth: 6, cornerHeight: 6, transform: nil))
    k.setFillColor(farbe(bernstein))
    k.fillPath()
    k.restoreGState()
}

let groessen: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
for (pixel, name) in groessen {
    let bild = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixel, pixelsHigh: pixel, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let kontext = NSGraphicsContext(bitmapImageRep: bild)!
    let k = kontext.cgContext
    k.scaleBy(x: CGFloat(pixel) / 1024, y: CGFloat(pixel) / 1024)
    k.interpolationQuality = .high
    zeichne(k)
    try bild.representation(using: .png, properties: [:])!.write(to: arbeit.appendingPathComponent("\(name).png"))
}

let prozess = Process()
prozess.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
prozess.arguments = ["-c", "icns", arbeit.path, "-o", ziel.path]
try prozess.run()
prozess.waitUntilExit()
let png = ziel.deletingPathExtension().appendingPathExtension("png")
try? FileManager.default.removeItem(at: png)
try? FileManager.default.copyItem(at: arbeit.appendingPathComponent("icon_512x512@2x.png"), to: png)
try? FileManager.default.removeItem(at: arbeit)
print(prozess.terminationStatus == 0 ? "fertig: \(ziel.path)" : "iconutil ist gescheitert")
exit(prozess.terminationStatus)
