#!/bin/zsh
# Baut build/Griffel-<version>.dmg zum Weitergeben: die App universell (Apple
# Silicon und Intel), dazu eine Verknüpfung zu «Programme».
#
# Signatur: Ist GRIFFEL_IDENTITAET gesetzt (etwa "Developer ID Application: Name
# (TEAMID)"), signiert das Skript damit, mit Hardened Runtime und Zeitstempel.
# Ist dazu GRIFFEL_NOTAR_PROFIL gesetzt (ein Profil aus «xcrun notarytool
# store-credentials»), reicht es die App bei Apple zur Beglaubigung ein und
# heftet das Ergebnis an. Ohne beides bleibt die lokale Signatur; macOS fragt
# dann beim ersten Öffnen nach (siehe README).
set -euo pipefail

WURZEL=${0:A:h:h}
cd $WURZEL
./scripts/app-bauen.sh --universell
APP=build/Griffel.app
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $APP/Contents/Info.plist)

if [[ -n ${GRIFFEL_IDENTITAET:-} ]]; then
  echo "→ Signieren mit $GRIFFEL_IDENTITAET"
  signiere() { codesign --force --options runtime --timestamp --sign "$GRIFFEL_IDENTITAET" "$@"; }
  signiere $APP/Contents/Frameworks/liblexilla.dylib
  signiere $APP/Contents/Frameworks/Scintilla.framework
  signiere $APP
  codesign --verify --strict --deep $APP
  if [[ -n ${GRIFFEL_NOTAR_PROFIL:-} ]]; then
    echo "→ Beglaubigen bei Apple"
    zip=$(mktemp -d)/Griffel.zip
    ditto -c -k --keepParent $APP $zip
    xcrun notarytool submit $zip --keychain-profile "$GRIFFEL_NOTAR_PROFIL" --wait
    xcrun stapler staple $APP
  fi
fi

echo "→ DMG"
stapel=$(mktemp -d)
cp -R $APP $stapel/
ln -s /Applications $stapel/Programme
dmg=build/Griffel-$version.dmg
rm -f $dmg
hdiutil create -quiet -volname "Griffel $version" -srcfolder $stapel -ov -format UDZO $dmg
rm -rf $stapel
if [[ -n ${GRIFFEL_IDENTITAET:-} ]]; then
  codesign --force --sign "$GRIFFEL_IDENTITAET" $dmg
  [[ -n ${GRIFFEL_NOTAR_PROFIL:-} ]] && { xcrun notarytool submit $dmg --keychain-profile "$GRIFFEL_NOTAR_PROFIL" --wait && xcrun stapler staple $dmg; }
fi
echo "fertig: $WURZEL/$dmg"
