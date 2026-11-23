#!/bin/bash
# Richtet Signatur und Beglaubigung für die Releases ein. Danach signiert der Lauf
# «Veröffentlichen» auf GitHub jede neue Fassung mit der Developer ID, lässt sie
# von Apple beglaubigen, und macOS öffnet Griffel ohne «“Griffel” Not Opened».
#
#   ./scripts/signatur-einrichten.sh ~/Downloads/AuthKey_ABC123DEFG.p8 <Issuer-ID>
#
# Vorher im Apple-Konto, beides kann nur der Kontoinhaber:
#   1. Das Zertifikat: Xcode → Einstellungen → Accounts → das Team → «Manage
#      Certificates…» → «+» → «Developer ID Application».
#   2. Der Schlüssel für die Beglaubigung: App Store Connect → Benutzer und Zugriff →
#      Integrationen → Team-Schlüssel → «+», Zugriff «Developer». Die .p8-Datei
#      laden (Apple gibt sie nur einmal heraus) und die Issuer-ID abschreiben, die
#      über der Liste der Schlüssel steht.
#
# Das Skript prüft den Schlüssel bei Apple und legt ihn als Profil «griffel» in
# deinen Schlüsselbund (damit baut GRIFFEL_NOTAR_PROFIL=griffel ./scripts/dmg-bauen.sh
# auch auf dem Mac beglaubigt), exportiert das Zertifikat mit privatem Schlüssel
# unter einem Zufallskennwort (macOS fragt dafür einmal nach deinem
# Anmeldepasswort) und legt fünf Secrets im Repo an. Kennwörter und Schlüssel
# erscheinen nie auf dem Bildschirm; die Zwischendateien sind danach gelöscht.
set -euo pipefail

REPO=simon-baumhauer/griffel
WURZEL=$(cd "$(dirname "$0")/.." && pwd)

if [ $# -ne 2 ]; then
  sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi
p8=$1
aussteller=$2

abbrechen() {
  echo "$1" >&2
  exit 1
}

# Der Schlüssel von App Store Connect: AuthKey_<Key-ID>.p8, so wie Apple ihn benennt.
[ -f "$p8" ] || abbrechen "Die Datei $p8 gibt es nicht."
grep -q 'BEGIN PRIVATE KEY' "$p8" || abbrechen "$p8 ist kein Schlüssel von App Store Connect (.p8)."
schluessel_id=$(basename "$p8")
schluessel_id=${schluessel_id#AuthKey_}
schluessel_id=${GRIFFEL_NOTAR_SCHLUESSEL_ID:-${schluessel_id%.p8}}
[[ $schluessel_id =~ ^[A-Z0-9]{10}$ ]] ||
  abbrechen "Die Key-ID steht nicht im Dateinamen (AuthKey_<Key-ID>.p8). Dann so: GRIFFEL_NOTAR_SCHLUESSEL_ID=<Key-ID> $0 …"
[[ $aussteller =~ ^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$ ]] ||
  abbrechen "«$aussteller» sieht nicht aus wie eine Issuer-ID (eine UUID wie 69a6de7e-…)."

command -v gh > /dev/null || abbrechen "Das Skript braucht gh (GitHub CLI)."
[ "$(gh api "repos/$REPO" --jq .permissions.admin 2> /dev/null)" = true ] ||
  abbrechen "gh ist nicht mit einem Konto angemeldet, das in $REPO Secrets anlegen darf (gh auth login)."

# Das Zertifikat «Developer ID Application» im Schlüsselbund.
zeilen=$(security find-identity -v -p codesigning | grep '"Developer ID Application: ' || true)
if [ -z "$zeilen" ]; then
  abbrechen "Im Schlüsselbund ist kein gültiges Zertifikat «Developer ID Application». Anlegen in Xcode → Einstellungen → Accounts → Team → «Manage Certificates…» → «+» → «Developer ID Application»."
fi
if [ "$(printf '%s\n' "$zeilen" | grep -c .)" -gt 1 ]; then
  [ -n "${GRIFFEL_ZERTIFIKAT_SHA1:-}" ] || {
    printf '%s\n' "$zeilen" >&2
    abbrechen "Es gibt mehrere. Welches gilt, sagt die Prüfsumme davor: GRIFFEL_ZERTIFIKAT_SHA1=<Prüfsumme> $0 …"
  }
  zeilen=$(printf '%s\n' "$zeilen" | grep -i "$GRIFFEL_ZERTIFIKAT_SHA1" || true)
  [ -n "$zeilen" ] || abbrechen "Kein Zertifikat mit der Prüfsumme $GRIFFEL_ZERTIFIKAT_SHA1."
fi
pruefsumme=$(printf '%s\n' "$zeilen" | awk '{print $2}')
name=$(printf '%s\n' "$zeilen" | sed 's/^[^"]*"\(.*\)"$/\1/')

arbeit=$(mktemp -d)
chmod 700 "$arbeit"
trap 'rm -rf "$arbeit"' EXIT

echo "→ Schlüssel $schluessel_id bei Apple prüfen und als Profil «griffel» ablegen"
xcrun notarytool store-credentials griffel --key "$p8" --key-id "$schluessel_id" --issuer "$aussteller"

echo "→ Zertifikat «$name» exportieren"
echo "  macOS fragt gleich nach deinem Anmeldepasswort, damit «Griffel-Signatur» den Schlüssel exportieren darf."
swiftc -O -suppress-warnings -o "$arbeit/Griffel-Signatur" "$WURZEL/scripts/zertifikat-exportieren.swift"
kennwort=$(openssl rand -base64 32 | tr -d '\n')
GRIFFEL_P12_KENNWORT=$kennwort "$arbeit/Griffel-Signatur" "$pruefsumme" "$arbeit/griffel.p12"
# Lässt sich die Datei mit dem Kennwort öffnen, und steckt das Zertifikat darin?
GRIFFEL_P12_KENNWORT=$kennwort /usr/bin/openssl pkcs12 -in "$arbeit/griffel.p12" -nokeys \
  -passin env:GRIFFEL_P12_KENNWORT 2> /dev/null | grep -q "Developer ID Application" ||
  abbrechen "Die exportierte Datei lässt sich nicht lesen; es ist nichts im Repo angelegt."

echo "→ Secrets in $REPO anlegen"
base64 -i "$arbeit/griffel.p12" | gh secret set GRIFFEL_ZERTIFIKAT --repo "$REPO"
printf '%s' "$kennwort" | gh secret set GRIFFEL_ZERTIFIKAT_PASSWORT --repo "$REPO"
gh secret set GRIFFEL_NOTAR_SCHLUESSEL --repo "$REPO" < "$p8"
printf '%s' "$schluessel_id" | gh secret set GRIFFEL_NOTAR_SCHLUESSEL_ID --repo "$REPO"
printf '%s' "$aussteller" | gh secret set GRIFFEL_NOTAR_AUSSTELLER --repo "$REPO"

cat << EOF

Fertig. Zur Probe signiert, beglaubigt und prüft der Lauf «Veröffentlichen» einmal
ohne Release:
  gh workflow run veroeffentlichen.yml --repo $REPO
Danach ist jedes Release beglaubigt. Die Datei $(basename "$p8") gehört jetzt in den
Passwortmanager und aus dem Download-Ordner: Apple gibt sie kein zweites Mal heraus.
EOF
