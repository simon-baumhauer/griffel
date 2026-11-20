#!/bin/zsh
# Baut den Editor-Kern aus dem Quellcode von Notepad++ für den Mac:
#   build/extern/out/Scintilla.framework  (Editor-Komponente, Cocoa)
#   build/extern/out/liblexilla.dylib     (Syntaxfarben, rund 130 Sprachen)
#
# Scintilla bringt ein eigenes Xcode-Projekt mit. Lexilla bauen wir direkt mit
# clang++, weil das Xcode-Projekt in der Notepad++-Fassung die drei Lexer nicht
# kennt, die Notepad++ selbst dazugeschrieben hat (ObjC, Suchergebnis,
# benutzerdefinierte Sprache).
set -euo pipefail

WURZEL=${0:A:h:h}
NPP=$WURZEL/extern/notepad-plus-plus
ZIEL=$WURZEL/build/extern
AUS=$ZIEL/out
OBJ=$ZIEL/lexilla-obj
MIN=13.0

mkdir -p $AUS $OBJ

# Der Quellcode von Notepad++ liegt nicht im Repo, sondern wird geholt: der
# Stand, gegen den Kladde gebaut und geprüft ist.
STAND=ff2530a478f11bbe0fb4867b837f842e24e49386
if [[ ! -d $NPP ]]; then
  echo "→ Notepad++ holen"
  git init -q $NPP
  git -C $NPP remote add origin https://github.com/notepad-plus-plus/notepad-plus-plus.git
  git -C $NPP fetch -q --depth 1 origin $STAND
  git -C $NPP checkout -q FETCH_HEAD
fi

echo "→ Scintilla"
xcodebuild -project $NPP/scintilla/cocoa/Scintilla/Scintilla.xcodeproj \
  -scheme Scintilla -configuration Release -derivedDataPath $ZIEL/dd \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CONFIGURATION_BUILD_DIR=$AUS \
  MACOSX_DEPLOYMENT_TARGET=$MIN \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -quiet

# Notepad++ hat Scintilla.h um zwei C++-Strukturen für seine Suchergebnisse
# ergänzt (#include <vector>). Swift liest den Header als C; in der Kopie im
# Framework stehen sie darum hinter #ifdef __cplusplus. Die Quelle bleibt, wie
# sie ist.
KOPF=$AUS/Scintilla.framework/Headers/Scintilla.h
if ! grep -q 'KLADDE_NUR_CPP' $KOPF; then
  perl -pi -e 's/^(#include <vector>\r?)$/#ifdef __cplusplus \/\/ KLADDE_NUR_CPP\n$1/;
               s/^(#ifdef INCLUDE_DEPRECATED_FEATURES\r?)$/#endif \/\/ KLADDE_NUR_CPP\n$1/' $KOPF
fi
[[ $(grep -c 'KLADDE_NUR_CPP' $KOPF) == 2 ]] || {
  echo "Scintilla.h: Die C++-Stelle sieht anders aus als erwartet." >&2; exit 1; }

echo "→ Lexilla"
# LexUser.cxx (benutzerdefinierte Sprachen) bindet <windows.h> nur für _itoa ein;
# extern/mac/windows.h liefert das.
quellen=(
  $NPP/lexilla/src/Lexilla.cxx
  $NPP/lexilla/lexlib/*.cxx
  $NPP/lexilla/lexers/*.cxx
)
print -l $quellen | xargs -P 10 -I{} zsh -c '
  o='$OBJ'/${1:t:r}.o
  [[ -f $o && $o -nt $1 ]] && exit 0
  clang++ -c -std=c++17 -O2 -fPIC -arch arm64 -mmacosx-version-min='$MIN' \
    -fvisibility=hidden -w \
    -I'$NPP'/lexilla/include -I'$NPP'/lexilla/lexlib -I'$NPP'/scintilla/include \
    -I'$NPP'/lexilla/access -I'$WURZEL'/extern/mac \
    $1 -o $o' _ {}

clang++ -dynamiclib -arch arm64 -mmacosx-version-min=$MIN \
  -install_name @rpath/liblexilla.dylib \
  $OBJ/*.o -o $AUS/liblexilla.dylib
codesign -f -s - $AUS/liblexilla.dylib 2>/dev/null

echo "fertig: $AUS"
