#!/bin/zsh
# Baut build/NoteMac++.app. Mit «--start» öffnet sich die App danach, mit
# «--universell» entsteht sie für Apple Silicon und Intel (für die Weitergabe).
# Den Editor-Kern baut scripts/extern-bauen.sh beim ersten Mal von selbst.
set -euo pipefail

WURZEL=${0:A:h:h}
KERN=$WURZEL/build/extern/out
APP=$WURZEL/build/NoteMac++.app

[[ -d $KERN/Scintilla.framework && -f $KERN/liblexilla.dylib ]] || $WURZEL/scripts/extern-bauen.sh

cd $WURZEL
# Die Warnungen über das Modul von Scintilla sind bekannt und gehen weg; der
# Ausgang von swift build zählt (sonst landet die Fassung vom letzten Mal im Bündel).
protokoll=$(mktemp)
universell=false
start=false
for arg in "$@"; do
  case $arg in
    --universell) universell=true ;;
    --start) start=true ;;
  esac
done
if $universell; then
  bau=(swift build -c release --arch arm64 --arch x86_64)
  programm=.build/apple/Products/Release/Kladde
else
  bau=(swift build -c release)
  programm=.build/release/Kladde
fi
if ! $bau >$protokoll 2>&1; then
  grep -E "error:" $protokoll >&2 || cat $protokoll >&2
  rm -f $protokoll
  echo "Der Bau ist gescheitert." >&2
  exit 1
fi
grep -v -E "umbrella|submodule|warnings generated|^ *\||^\[|^[0-9]+%:|Compiling|Building|Write|Planning|Build complete" $protokoll || true
rm -f $protokoll

rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Frameworks $APP/Contents/Resources
# Das Ziel in Package.swift heisst noch «Kladde» (der alte Name der App).
cp $programm $APP/Contents/MacOS/NoteMac++
# swift build trägt auch den Ordner der Swift-Bibliotheken von Xcode als Suchpfad
# ein. Auf anderen Macs fehlt er, und Apple lehnt die Beglaubigung ab, solange ein
# Suchpfad aus dem Bündel hinaus auf einen leeren Ort zeigt (syspolicy_check:
# «Bad Load Command»). NoteMac++ braucht nur /usr/lib/swift und die eigenen Frameworks.
otool -l $APP/Contents/MacOS/NoteMac++ | sed -n 's/^ *path \(.*\) (offset [0-9]*)$/\1/p' |
  while IFS= read -r pfad; do
    case $pfad in
      /usr/lib/swift|@*) ;;
      /*)
        # Die Warnung, dass die Signatur ungültig wird, stimmt; signiert wird unten.
        if ! meldung=$(install_name_tool -delete_rpath "$pfad" $APP/Contents/MacOS/NoteMac++ 2>&1); then
          echo "$meldung" >&2
          exit 1
        fi
        ;;
    esac
  done
cp Ressourcen/Info.plist $APP/Contents/
# Version aus dem letzten Tag (v1.2.3), Build-Nummer aus der Zahl der Commits.
version=$( { git describe --tags --abbrev=0 2>/dev/null || true; } | sed 's/^v//')
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version:-0.0.0}" $APP/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD 2>/dev/null || echo 1)" $APP/Contents/Info.plist
cp Ressourcen/notemac $APP/Contents/Resources/notemac
cp Ressourcen/NoteMac.icns $APP/Contents/Resources/NoteMac.icns
cp -R $KERN/Scintilla.framework $APP/Contents/Frameworks/
cp $KERN/liblexilla.dylib $APP/Contents/Frameworks/
cp LICENSE $APP/Contents/Resources/LICENSE-GPL.txt
cp extern/notepad-plus-plus/scintilla/License.txt $APP/Contents/Resources/LICENSE-Scintilla-Lexilla.txt

# Sprachen und Farbschemata aus den XML-Dateien von Notepad++ (scripts/sprachdaten.py).
rm -rf $WURZEL/build/sprachdaten
python3 -I scripts/sprachdaten.py extern/notepad-plus-plus $WURZEL/build/sprachdaten
cp -R $WURZEL/build/sprachdaten $APP/Contents/Resources/Sprachdaten

# Symbole von Notepad++ (Werkzeugleiste, Tabs, Seitenleisten), GPL wie NoteMac++.
mkdir -p $APP/Contents/Resources/Symbole
for satz in standard light dark; do
  cp -R extern/notepad-plus-plus/PowerEditor/src/icons/$satz $APP/Contents/Resources/Symbole/
done

# Lokale Signatur ohne Entwicklerkonto. Für die Weitergabe signiert
# scripts/dmg-bauen.sh mit der «Developer ID» und lässt die App beglaubigen.
codesign --force --deep -s - $APP 2>/dev/null

echo "fertig: $APP"
$start && open $APP
exit 0
