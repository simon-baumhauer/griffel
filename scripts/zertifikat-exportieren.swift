// Exportiert ein Zertifikat samt privatem Schlüssel aus dem Schlüsselbund als
// PKCS#12-Datei. Die Zwischenzertifikate bis vor die Wurzel von Apple kommen mit,
// damit codesign auf einer anderen Maschine (dem Lauf auf GitHub) die Kette bilden
// kann. Gebraucht von scripts/signatur-einrichten.sh.
//
//   GRIFFEL_P12_KENNWORT=… zertifikat-exportieren <SHA-1 des Zertifikats> <ziel.p12> [schlüsselbund]
//
// Das Kennwort kommt aus der Umgebung, nicht aus den Argumenten, die jeder in ps
// sieht. macOS fragt beim Export nach dem Anmeldepasswort, weil der private
// Schlüssel sonst nur Xcode und codesign offensteht.
import CryptoKit
import Foundation
import Security

func abbrechen(_ text: String) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(1)
}

let argumente = CommandLine.arguments
guard argumente.count == 3 || argumente.count == 4 else {
    abbrechen("Aufruf: zertifikat-exportieren <SHA-1 des Zertifikats> <ziel.p12> [schlüsselbund]")
}
let gesucht = argumente[1].uppercased()
let ziel = URL(fileURLWithPath: argumente[2])
guard let kennwort = ProcessInfo.processInfo.environment["GRIFFEL_P12_KENNWORT"], !kennwort.isEmpty else {
    abbrechen("GRIFFEL_P12_KENNWORT fehlt.")
}

var abfrage: [String: Any] = [
    kSecClass as String: kSecClassIdentity,
    kSecMatchLimit as String: kSecMatchLimitAll,
    kSecReturnRef as String: true,
]
if argumente.count == 4 {
    // Nur für Proben mit einem eigenen Schlüsselbund; sonst gilt der Suchpfad.
    // Proben fragen nie nach: lieber scheitern als ein Fenster öffnen.
    SecKeychainSetUserInteractionAllowed(false)
    var bund: SecKeychain?
    guard SecKeychainOpen(argumente[3], &bund) == errSecSuccess, let bund else {
        abbrechen("Der Schlüsselbund \(argumente[3]) lässt sich nicht öffnen.")
    }
    abfrage[kSecMatchSearchList as String] = [bund]
}
var ergebnis: CFTypeRef?
let gefunden = SecItemCopyMatching(abfrage as CFDictionary, &ergebnis)
guard gefunden == errSecSuccess, let identitaeten = ergebnis as? [SecIdentity] else {
    abbrechen("Im Schlüsselbund ist kein Zertifikat mit privatem Schlüssel (\(gefunden)).")
}

func pruefsumme(_ zertifikat: SecCertificate) -> String {
    Insecure.SHA1.hash(data: SecCertificateCopyData(zertifikat) as Data)
        .map { String(format: "%02X", $0) }.joined()
}

func istWurzel(_ zertifikat: SecCertificate) -> Bool {
    guard let aussteller = SecCertificateCopyNormalizedIssuerSequence(zertifikat),
          let inhaber = SecCertificateCopyNormalizedSubjectSequence(zertifikat) else { return false }
    return (aussteller as Data) == (inhaber as Data)
}

var treffer: (identitaet: SecIdentity, zertifikat: SecCertificate)?
for identitaet in identitaeten {
    var zertifikat: SecCertificate?
    guard SecIdentityCopyCertificate(identitaet, &zertifikat) == errSecSuccess, let zertifikat else { continue }
    if pruefsumme(zertifikat) == gesucht {
        treffer = (identitaet, zertifikat)
        break
    }
}
guard let treffer else { abbrechen("Kein Zertifikat mit der Prüfsumme \(gesucht) und privatem Schlüssel.") }

// Die Kette, wie macOS sie bildet: dahinter die Zwischenzertifikate, ohne die Wurzel.
var zwischen: [SecCertificate] = []
var vertrauen: SecTrust?
if SecTrustCreateWithCertificates(treffer.zertifikat, SecPolicyCreateBasicX509(), &vertrauen) == errSecSuccess,
   let vertrauen {
    _ = SecTrustEvaluateWithError(vertrauen, nil)
    if let kette = SecTrustCopyCertificateChain(vertrauen) as? [SecCertificate] {
        zwischen = kette.dropFirst().filter { !istWurzel($0) }
    }
}

let kennwortCF = kennwort as CFString
var parameter = SecItemImportExportKeyParameters()
parameter.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
parameter.passphrase = Unmanaged<AnyObject>.passUnretained(kennwortCF)
var daten: CFData?
let teile: [AnyObject] = [treffer.identitaet] + zwischen
let exportiert = SecItemExport(teile as CFArray, .formatPKCS12, [], &parameter, &daten)
withExtendedLifetime(kennwortCF) {}
guard exportiert == errSecSuccess, let daten else {
    let grund = SecCopyErrorMessageString(exportiert, nil) as String? ?? "unbekannt"
    abbrechen("Der Export ist gescheitert: \(grund) (\(exportiert)).")
}
do {
    try (daten as Data).write(to: ziel, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ziel.path)
} catch {
    abbrechen("\(ziel.path) lässt sich nicht schreiben: \(error.localizedDescription)")
}
print("exportiert, mit \(zwischen.count) Zwischenzertifikat\(zwischen.count == 1 ? "" : "en")")
