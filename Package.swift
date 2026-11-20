// swift-tools-version:5.9
import PackageDescription

// Scintilla.framework und liblexilla.dylib entstehen mit scripts/extern-bauen.sh
// aus dem Quellcode von Notepad++ und liegen danach unter build/extern/out.
let wurzel = Context.packageDirectory
let kern = "\(wurzel)/build/extern/out"
let lexilla = "\(wurzel)/extern/notepad-plus-plus/lexilla/include"

let package = Package(
    name: "Kladde",
    platforms: [.macOS(.v13)],
    targets: [
        // Was ohne Oberfläche geht und darum mit «swift test» prüfbar ist:
        // Zeichensätze, Suchen und Ersetzen.
        .target(name: "KladdeKern"),
        .testTarget(name: "KladdeKernTests", dependencies: ["KladdeKern"]),

        // Macht ScintillaView (Objective-C) und Lexilla (C) für Swift sichtbar.
        .target(
            name: "ScintillaBruecke",
            cSettings: [.unsafeFlags(["-F", kern, "-I", lexilla])]
        ),
        .executableTarget(
            name: "Kladde",
            dependencies: ["KladdeKern", "ScintillaBruecke"],
            swiftSettings: [
                .unsafeFlags(["-F", kern, "-Xcc", "-F\(kern)", "-Xcc", "-I\(lexilla)"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", kern, "-framework", "Scintilla",
                    "-L", kern, "-llexilla",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                ])
            ]
        ),
    ]
)
