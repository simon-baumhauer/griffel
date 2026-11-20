#!/bin/zsh
# Baut build/Kladde.app. Mit «--start» öffnet sich die App danach.
# Voraussetzung: der Editor-Kern aus scripts/extern-bauen.sh.
set -euo pipefail

WURZEL=${0:A:h:h}
KERN=$WURZEL/build/extern/out
APP=$WURZEL/build/Kladde.app

[[ -d $KERN/Scintilla.framework && -f $KERN/liblexilla.dylib ]] || $WURZEL/scripts/extern-bauen.sh

cd $WURZEL
# Die Warnungen über das Modul von Scintilla sind bekannt und gehen weg; der
# Ausgang von swift build zählt (sonst landet die Fassung vom letzten Mal im Bündel).
protokoll=$(mktemp)
if ! swift build -c release >$protokoll 2>&1; then
  grep -E "error:" $protokoll >&2 || cat $protokoll >&2
  rm -f $protokoll
  echo "Der Bau ist gescheitert." >&2
  exit 1
fi
grep -v -E "umbrella|submodule|warnings generated|^ *\||^\[|Compiling|Building|Write|Planning|Build complete" $protokoll || true
rm -f $protokoll

rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Frameworks $APP/Contents/Resources
cp .build/release/Kladde $APP/Contents/MacOS/
cp Ressourcen/Info.plist $APP/Contents/
cp Ressourcen/kladde $APP/Contents/Resources/kladde
cp Ressourcen/Kladde.icns $APP/Contents/Resources/Kladde.icns
cp -R $KERN/Scintilla.framework $APP/Contents/Frameworks/
cp $KERN/liblexilla.dylib $APP/Contents/Frameworks/
cp LICENSE $APP/Contents/Resources/LICENSE-GPL.txt
cp extern/notepad-plus-plus/scintilla/License.txt $APP/Contents/Resources/LICENSE-Scintilla-Lexilla.txt

# Sprachen und Farbschemata aus den XML-Dateien von Notepad++ (scripts/sprachdaten.py).
rm -rf $WURZEL/build/sprachdaten
python3 -I scripts/sprachdaten.py extern/notepad-plus-plus $WURZEL/build/sprachdaten
cp -R $WURZEL/build/sprachdaten $APP/Contents/Resources/Sprachdaten

# Lokale Signatur ohne Entwicklerkonto; für die Weitergabe kommt in Etappe 7
# die echte Signatur samt Beglaubigung durch Apple.
codesign --force --deep -s - $APP 2>/dev/null

echo "fertig: $APP"
[[ ${1:-} == --start ]] && open $APP
exit 0
