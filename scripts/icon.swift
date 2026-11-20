// Zeichnet das Icon von Kladde: ein grünes Schreibheft (eine Kladde) mit einer
// Seite, auf der farbige Striche wie eingefärbte Codezeilen stehen.
//
//   swift scripts/icon.swift Ressourcen/Kladde.icns
//
// Braucht nur macOS (CoreGraphics, iconutil).
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

/// Zeichnet in einem Raster von 1024 × 1024 (Apples Vorlage: Inhalt 824 × 824 mit Rand 100).
func zeichne(_ k: CGContext) {
    k.saveGState()
    k.translateBy(x: 0, y: 1024)
    k.scaleBy(x: 1, y: -1)  // oben links ist 0/0

    // Schatten unter dem Heft.
    let heft = CGRect(x: 100, y: 100, width: 824, height: 824)
    let form = CGPath(roundedRect: heft, cornerWidth: 185, cornerHeight: 185, transform: nil)
    k.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: farbe(0x000000, 0.35))
    k.addPath(form)
    k.setFillColor(farbe(0x245C43))
    k.fillPath()
    k.setShadow(offset: .zero, blur: 0, color: nil)

    // Einband mit leichtem Verlauf.
    k.saveGState()
    k.addPath(form)
    k.clip()
    let verlauf = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [farbe(0x2F7A57), farbe(0x1C4A35)] as CFArray,
        locations: [0, 1])!
    k.drawLinearGradient(verlauf, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])

    // Rücken links mit Heftung.
    k.setFillColor(farbe(0x163B2A))
    k.fill(CGRect(x: 100, y: 100, width: 120, height: 824))
    k.setFillColor(farbe(0xE8D9A8))
    for y in stride(from: 250, through: 700, by: 150) {
        k.fill(CGRect(x: 150, y: CGFloat(y), width: 20, height: 70))
    }
    k.restoreGState()

    // Die Seite.
    let seite = CGRect(x: 268, y: 178, width: 580, height: 668)
    k.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: farbe(0x000000, 0.3))
    k.addPath(CGPath(roundedRect: seite, cornerWidth: 34, cornerHeight: 34, transform: nil))
    k.setFillColor(farbe(0xFBF7EC))
    k.fillPath()
    k.setShadow(offset: .zero, blur: 0, color: nil)

    // Linien und roter Rand wie im Schulheft.
    k.setStrokeColor(farbe(0xA9C4E0))
    k.setLineWidth(4)
    let zeilen = stride(from: 270, through: 790, by: 65).map { CGFloat($0) }
    for y in zeilen {
        k.move(to: CGPoint(x: seite.minX + 26, y: y + 26))
        k.addLine(to: CGPoint(x: seite.maxX - 26, y: y + 26))
    }
    k.strokePath()
    k.setStrokeColor(farbe(0xE07A6B))
    k.setLineWidth(5)
    k.move(to: CGPoint(x: seite.minX + 92, y: seite.minY + 22))
    k.addLine(to: CGPoint(x: seite.minX + 92, y: seite.maxY - 22))
    k.strokePath()

    // Codezeilen: Einrückung und Farben wie eingefärbter Quelltext.
    let code: [(einzug: CGFloat, teile: [(breite: CGFloat, farbe: UInt32)])] = [
        (0, [(110, 0x2D6CDF), (150, 0x1F1F1F)]),
        (40, [(90, 0x2D6CDF), (190, 0xD9822B)]),
        (40, [(70, 0x8E44AD), (120, 0x1F1F1F), (60, 0x2E9E5B)]),
        (80, [(210, 0x2E9E5B)]),
        (40, [(60, 0x1F1F1F)]),
        (0, [(40, 0x1F1F1F)]),
        (0, [(130, 0x7F8C8D), (120, 0x7F8C8D)]),
    ]
    for (i, zeile) in code.enumerated() {
        var x = seite.minX + 118 + zeile.einzug
        let y = zeilen[i] + 2
        for teil in zeile.teile {
            k.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: teil.breite, height: 20), cornerWidth: 10, cornerHeight: 10, transform: nil))
            k.setFillColor(farbe(teil.farbe))
            k.fillPath()
            x += teil.breite + 18
        }
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
try? FileManager.default.copyItem(
    at: arbeit.appendingPathComponent("icon_512x512@2x.png"),
    to: ziel.deletingPathExtension().appendingPathExtension("png"))
try? FileManager.default.removeItem(at: arbeit)
print(prozess.terminationStatus == 0 ? "fertig: \(ziel.path)" : "iconutil ist gescheitert")
exit(prozess.terminationStatus)
