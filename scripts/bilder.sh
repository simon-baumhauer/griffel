#!/bin/zsh
# Erneuert die Bilder fürs README in docs/bilder/: Eine Kopie von
# build/Griffel.app mit eigener Kennung öffnet im Hintergrund die Beispiele aus
# docs/bilder/beispiele/, und die Selbstprüfung «bilder» (Sources/Kladde/Probe.swift)
# zeichnet die Fenster. Die Kopie startet mit leeren Einstellungen, eigener
# Sitzung und Ablage; eine laufende Griffel bleibt unberührt. Vorher
# ./scripts/app-bauen.sh.
set -euo pipefail

WURZEL=${0:A:h:h}
cd $WURZEL
[[ -d build/Griffel.app ]] || { echo "Erst ./scripts/app-bauen.sh laufen lassen." >&2; exit 1; }

kennung=io.github.simon-baumhauer.kladde.bilder
defaults delete $kennung 2>/dev/null || true  # Einstellungen eines früheren Laufs
arbeit=$(mktemp -d)
trap 'rm -rf $arbeit; defaults delete $kennung 2>/dev/null || true' EXIT

kopie=$arbeit/Griffel-Bilder.app
cp -R build/Griffel.app $kopie
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $kennung" $kopie/Contents/Info.plist
codesign --force --deep -s - $kopie 2>/dev/null

mkdir -p $arbeit/bericht $arbeit/beispiele
cp docs/bilder/beispiele/* $arbeit/beispiele/
open -g -n -W -a $kopie $arbeit/beispiele/* --args \
  -KladdeProbe $arbeit/bericht -KladdeProbeAktion bilder \
  -KladdeSitzung $arbeit/sitzung -KladdeUDL $arbeit/udl -KladdeAblage $arbeit/ablage

for bild in griffel griffel-dunkel suchen json-viewer optionen; do
  [[ -f $arbeit/bericht/$bild.png ]] || { echo "$bild.png fehlt" >&2; exit 1; }
  cp $arbeit/bericht/$bild.png docs/bilder/$bild.png
done
grep "^bilder:" $arbeit/bericht/bericht.txt || true
echo "fertig: docs/bilder/"
