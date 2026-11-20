#!/bin/zsh
# Baut build/Kladde-<version>.dmg zum Weitergeben: die App universell (Apple
# Silicon und Intel), dazu eine Verknüpfung zu «Programme».
#
# Signatur: Ist KLADDE_IDENTITAET gesetzt (etwa "Developer ID Application: Name
# (TEAMID)"), signiert das Skript damit, mit Hardened Runtime und Zeitstempel.
# Ist dazu KLADDE_NOTAR_PROFIL gesetzt (ein Profil aus «xcrun notarytool
# store-credentials»), reicht es die App bei Apple zur Beglaubigung ein und
# heftet das Ergebnis an. Ohne beides bleibt die lokale Signatur; macOS fragt
# dann beim ersten Öffnen nach (siehe README).
set -euo pipefail

WURZEL=${0:A:h:h}
cd $WURZEL
./scripts/app-bauen.sh --universell
APP=build/Kladde.app
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $APP/Contents/Info.plist)

if [[ -n ${KLADDE_IDENTITAET:-} ]]; then
  echo "→ Signieren mit $KLADDE_IDENTITAET"
  signiere() { codesign --force --options runtime --timestamp --sign "$KLADDE_IDENTITAET" "$@"; }
  signiere $APP/Contents/Frameworks/liblexilla.dylib
  signiere $APP/Contents/Frameworks/Scintilla.framework
  signiere $APP
  codesign --verify --strict --deep $APP
  if [[ -n ${KLADDE_NOTAR_PROFIL:-} ]]; then
    echo "→ Beglaubigen bei Apple"
    zip=$(mktemp -d)/Kladde.zip
    ditto -c -k --keepParent $APP $zip
    xcrun notarytool submit $zip --keychain-profile "$KLADDE_NOTAR_PROFIL" --wait
    xcrun stapler staple $APP
  fi
fi

echo "→ DMG"
stapel=$(mktemp -d)
cp -R $APP $stapel/
ln -s /Applications $stapel/Programme
dmg=build/Kladde-$version.dmg
rm -f $dmg
hdiutil create -quiet -volname "Kladde $version" -srcfolder $stapel -ov -format UDZO $dmg
rm -rf $stapel
if [[ -n ${KLADDE_IDENTITAET:-} ]]; then
  codesign --force --sign "$KLADDE_IDENTITAET" $dmg
  [[ -n ${KLADDE_NOTAR_PROFIL:-} ]] && { xcrun notarytool submit $dmg --keychain-profile "$KLADDE_NOTAR_PROFIL" --wait && xcrun stapler staple $dmg; }
fi
echo "fertig: $WURZEL/$dmg"
