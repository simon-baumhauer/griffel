#!/bin/zsh
# Baut build/NoteMac-<version>.dmg zum Weitergeben: die App universell (Apple
# Silicon und Intel), dazu eine Verknüpfung zu «Programme».
#
#   ./scripts/dmg-bauen.sh                 signiert und beglaubigt, wenn die Angaben unten da sind
#   ./scripts/dmg-bauen.sh --beglaubigen   bricht ab, wenn eine davon fehlt
#
# Ohne Signatur und Beglaubigung meldet macOS beim ersten Öffnen «“NoteMac++” Not
# Opened»; so ein DMG taugt nur zum Ausprobieren. Der Lauf «Veröffentlichen» baut
# darum immer mit --beglaubigen.
#
# Signatur: NOTEMAC_IDENTITAET, etwa "Developer ID Application: Name (TEAMID)".
# Mit NOTEMAC_SCHLUESSELBUND sucht codesign sie nur in diesem Schlüsselbund.
# Signiert wird mit Hardened Runtime und dem Zeitstempel von Apple.
#
# Beglaubigung, eines von beiden:
#   NOTEMAC_NOTAR_PROFIL       ein Profil aus «xcrun notarytool store-credentials»;
#                              scripts/signatur-einrichten.sh legt «notemac» an
#   NOTEMAC_NOTAR_SCHLUESSEL   Pfad zur .p8-Datei eines Schlüssels von App Store
#                              Connect, dazu NOTEMAC_NOTAR_SCHLUESSEL_ID und
#                              NOTEMAC_NOTAR_AUSSTELLER (so im Lauf auf GitHub)
#
# Beglaubigt werden erst die App, dann das DMG; beide bekommen das Ticket
# angeheftet, damit sie auch ohne Netz öffnen. Zum Schluss prüft das Skript das
# fertige DMG und die App darin so, wie macOS sie beim ersten Öffnen prüft, und
# bricht ab, wenn eine Prüfung scheitert.
set -euo pipefail

WURZEL=${0:A:h:h}
cd $WURZEL

beglaubigen=false
for arg in "$@"; do
  case $arg in
    --beglaubigen) beglaubigen=true ;;
    *) echo "Unbekannte Angabe: $arg (erlaubt ist --beglaubigen)" >&2; exit 2 ;;
  esac
done

identitaet=${NOTEMAC_IDENTITAET:-}
schluesselbund=()
[[ -n ${NOTEMAC_SCHLUESSELBUND:-} ]] && schluesselbund=(--keychain $NOTEMAC_SCHLUESSELBUND)
notar=()
if [[ -n ${NOTEMAC_NOTAR_SCHLUESSEL:-} ]]; then
  if [[ -z ${NOTEMAC_NOTAR_SCHLUESSEL_ID:-} || -z ${NOTEMAC_NOTAR_AUSSTELLER:-} ]]; then
    echo "Zu NOTEMAC_NOTAR_SCHLUESSEL fehlen NOTEMAC_NOTAR_SCHLUESSEL_ID oder NOTEMAC_NOTAR_AUSSTELLER." >&2
    exit 1
  fi
  notar=(--key $NOTEMAC_NOTAR_SCHLUESSEL --key-id $NOTEMAC_NOTAR_SCHLUESSEL_ID --issuer $NOTEMAC_NOTAR_AUSSTELLER)
elif [[ -n ${NOTEMAC_NOTAR_PROFIL:-} ]]; then
  notar=(--keychain-profile $NOTEMAC_NOTAR_PROFIL $schluesselbund)
fi

if (( ${#notar} )) && [[ -z $identitaet ]]; then
  echo "Beglaubigen geht nur mit Signatur, und NOTEMAC_IDENTITAET fehlt." >&2
  exit 1
fi
if $beglaubigen; then
  fehlt=()
  [[ -n $identitaet ]] || fehlt+=("die Signatur (NOTEMAC_IDENTITAET)")
  (( ${#notar} )) || fehlt+=("die Beglaubigung (NOTEMAC_NOTAR_PROFIL oder NOTEMAC_NOTAR_SCHLUESSEL)")
  if (( ${#fehlt} )); then
    (( ${#fehlt} > 1 )) && verb=fehlen || verb=fehlt
    echo "Für ein beglaubigtes DMG $verb ${(j: und :)fehlt}; siehe scripts/signatur-einrichten.sh." >&2
    exit 1
  fi
fi

arbeit=$(mktemp -d)
arbeit=${arbeit:A}
aufraeumen() {
  if mount | grep -q " on $arbeit/dmg "; then
    hdiutil detach -quiet -force $arbeit/dmg || return
  fi
  rm -rf $arbeit
}
trap aufraeumen EXIT

./scripts/app-bauen.sh --universell
APP=build/NoteMac++.app
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $APP/Contents/Info.plist)
dmg=build/NoteMac-$version.dmg

signiere() {
  codesign --force --options runtime --timestamp --sign $identitaet $schluesselbund "$@"
}

# Reicht eine Datei bei Apple ein und wartet auf das Ergebnis. Lehnt Apple ab,
# steht Apples Bericht im Protokoll, und das Skript bricht ab.
beglaubige() {
  local datei=$1 antwort status kennung
  echo "→ Beglaubigen bei Apple: ${datei:t}"
  antwort=$(xcrun notarytool submit $datei $notar --wait --timeout 1h --output-format json) || true
  status=$(print -r -- $antwort | plutil -extract status raw -o - - 2>/dev/null) || status=
  if [[ $status != Accepted ]]; then
    echo "Apple hat ${datei:t} nicht beglaubigt (Status: ${status:-keine Antwort})." >&2
    kennung=$(print -r -- $antwort | plutil -extract id raw -o - - 2>/dev/null) || kennung=
    [[ -n $kennung ]] && xcrun notarytool log $kennung $notar >&2
    exit 1
  fi
}

# Wie macOS beim ersten Öffnen: Nur «Notarized Developer ID» öffnet ohne Meldung.
gatekeeper() {
  local ausgabe
  ausgabe=$(spctl --assess --verbose=4 "$@" 2>&1) || true
  if [[ $ausgabe != *"source=Notarized Developer ID"* ]]; then
    echo "Gatekeeper würde das nicht ohne Meldung öffnen:" >&2
    print -r -- $ausgabe >&2
    exit 1
  fi
}

if [[ -n $identitaet ]]; then
  echo "→ Signieren mit $identitaet"
  signiere $APP/Contents/Frameworks/liblexilla.dylib
  signiere $APP/Contents/Frameworks/Scintilla.framework
  signiere $APP
  codesign --verify --strict --deep --verbose=2 $APP
  if (( ${#notar} )); then
    ditto -c -k --keepParent $APP $arbeit/NoteMac.zip
    beglaubige $arbeit/NoteMac.zip
    xcrun stapler staple $APP
  fi
fi

echo "→ DMG"
mkdir $arbeit/stapel
ditto $APP $arbeit/stapel/NoteMac++.app
ln -s /Applications $arbeit/stapel/Programme
rm -f $dmg
hdiutil create -quiet -volname "NoteMac++ $version" -srcfolder $arbeit/stapel -ov -format UDZO $dmg
if [[ -n $identitaet ]]; then
  codesign --force --timestamp --sign $identitaet $schluesselbund $dmg
  if (( ${#notar} )); then
    beglaubige $dmg
    xcrun stapler staple $dmg
  fi
fi

if (( ${#notar} )); then
  echo "→ Prüfen wie macOS beim ersten Öffnen"
  codesign --verify --strict $dmg
  xcrun stapler validate $dmg
  mkdir $arbeit/dmg
  hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint $arbeit/dmg $dmg
  app=$arbeit/dmg/NoteMac++.app
  codesign --verify --strict --deep $app
  xcrun stapler validate $app
  angaben=$(codesign -dvv $app 2>&1)
  [[ $angaben == *"Authority=Developer ID Application:"* ]] || { echo "Die App im DMG ist nicht mit einer Developer ID signiert." >&2; exit 1; }
  [[ $angaben == *"(runtime)"* ]] || { echo "Die App im DMG hat keine Hardened Runtime." >&2; exit 1; }
  if spctl --status 2>/dev/null | grep -q 'assessments enabled'; then
    gatekeeper --type open --context context:primary-signature $dmg
    gatekeeper --type execute $app
  else
    echo "Hinweis: Gatekeeper ist auf dieser Maschine ausgeschaltet; spctl prüft hier nichts."
  fi
  if command -v syspolicy_check >/dev/null; then
    syspolicy_check distribution $app
  fi
  hdiutil detach -quiet $arbeit/dmg
  echo "fertig, signiert und beglaubigt: $WURZEL/$dmg"
else
  echo "fertig: $WURZEL/$dmg"
  echo "Nicht beglaubigt: macOS meldet beim ersten Öffnen «“NoteMac++” Not Opened». Nur zum Ausprobieren."
fi
