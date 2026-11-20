// Zeichnet das Icon von Griffel, Vorschlag D «Eselsohr» (Design-Canvas
// «Kladde Logos», gewählt am 20.11.2026): ein cremeweisses Blatt mit
// umgeknickter Ecke in Bernstein und fünf Codezeilen, auf Anthrazit.
//
//   swift scripts/icon.swift Ressourcen/Griffel.icns
//
// Schreibt Griffel.icns (alle Grössen von 16 bis 1024 Pixel) und daneben
// Griffel.png (1024 × 1024). Braucht nur macOS (CoreGraphics, iconutil).
import AppKit
import Foundation

let ziel = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Griffel.icns")
let arbeit = FileManager.default.temporaryDirectory.appendingPathComponent("griffel-icon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: arbeit, withIntermediateDirectories: true)

func farbe(_ rgb: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
        blue: CGFloat(rgb & 0xFF) / 255, alpha: a)
}

let anthrazit: UInt32 = 0x2B2D33
let papier: UInt32 = 0xF7F4EC
let bernstein: UInt32 = 0xF2B035
let blau: UInt32 = 0x3D6FE0
let orange: UInt32 = 0xE0663D

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

/// Das Blatt: oben rechts schräg abgeschnitten (dort sitzt das Eselsohr),
/// die übrigen Ecken leicht gerundet. Masse wie im Entwurf (Raster 1024, oben links 0/0).
func blatt() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 300, y: 214))
    p.addLine(to: CGPoint(x: 648, y: 214))
    p.addLine(to: CGPoint(x: 760, y: 326))
    p.addLine(to: CGPoint(x: 760, y: 790))
    p.addQuadCurve(to: CGPoint(x: 740, y: 810), control: CGPoint(x: 760, y: 810))
    p.addLine(to: CGPoint(x: 300, y: 810))
    p.addQuadCurve(to: CGPoint(x: 280, y: 790), control: CGPoint(x: 280, y: 810))
    p.addLine(to: CGPoint(x: 280, y: 234))
    p.addQuadCurve(to: CGPoint(x: 300, y: 214), control: CGPoint(x: 280, y: 214))
    p.closeSubpath()
    return p
}

/// Die umgeknickte Ecke.
func eselsohr() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 648, y: 214))
    p.addLine(to: CGPoint(x: 648, y: 306))
    p.addQuadCurve(to: CGPoint(x: 668, y: 326), control: CGPoint(x: 648, y: 326))
    p.addLine(to: CGPoint(x: 760, y: 326))
    p.closeSubpath()
    return p
}

/// Fünf Codezeilen, die mittleren eingerückt: x, y, Breite, Farbe (alle 30 hoch, rund).
let zeilen: [(CGFloat, CGFloat, CGFloat, UInt32)] = [
    (340, 392, 230, anthrazit), (340, 466, 320, blau), (390, 540, 200, anthrazit),
    (390, 614, 270, orange), (340, 688, 150, anthrazit),
]

/// Zeichnet in einem Raster von 1024 × 1024 (Apples Vorlage: Inhalt 824 × 824 mit
/// Rand 100). Der Schatten rechnet in Pixeln, nicht im Raster: darum der Massstab.
func zeichne(_ k: CGContext, massstab m: CGFloat) {
    k.saveGState()
    k.scaleBy(x: m, y: m)
    k.translateBy(x: 0, y: 1024)
    k.scaleBy(x: 1, y: -1)  // oben links ist 0/0

    // Fläche mit dem Schatten der macOS-Icons.
    let form = flaeche(CGRect(x: 100, y: 100, width: 824, height: 824), radius: 185)
    k.setShadow(offset: CGSize(width: 0, height: -12 * m), blur: 28 * m, color: farbe(0x000000, 0.35))
    k.addPath(form)
    k.setFillColor(farbe(anthrazit))
    k.fillPath()
    k.setShadow(offset: .zero, blur: 0, color: nil)

    k.addPath(blatt())
    k.setFillColor(farbe(papier))
    k.fillPath()
    k.addPath(eselsohr())
    k.setFillColor(farbe(bernstein))
    k.fillPath()
    for (x, y, breite, f) in zeilen {
        k.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: breite, height: 30), cornerWidth: 15, cornerHeight: 15, transform: nil))
        k.setFillColor(farbe(f))
        k.fillPath()
    }
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
    k.interpolationQuality = .high
    zeichne(k, massstab: CGFloat(pixel) / 1024)
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
