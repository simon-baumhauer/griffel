// Platzhalter für Lexer aus Notepad++, die auf dem Mac noch nicht gebaut werden.
//
// lexilla/src/Lexilla.cxx trägt lmUserDefine in seinen Katalog ein. Die Quelle
// dazu (lexers/LexUser.cxx, «benutzerdefinierte Sprache») braucht <windows.h>.
// Bis sie portiert ist, steht hier ein Lexer ohne Funktion: Er färbt
// nichts ein, und der Katalog bleibt vollständig.

#include <cstddef>
#include <cstdint>

#include "ILexer.h"
#include "Scintilla.h"
#include "SciLexer.h"
#include "LexerModule.h"

using namespace Lexilla;

extern const LexerModule lmUserDefine(SCLEX_USER, static_cast<LexerFunction>(nullptr), "user");
