// Brücke von Swift zum Editor-Kern.
//
// Scintilla.framework führt in seinem Modul nur Scintilla.h (die Nachrichten
// und Konstanten). Die Ansicht selbst, ScintillaView, und die Stilnummern der
// Lexer (SciLexer.h) kommen hier dazu.

#import <Cocoa/Cocoa.h>
#import <Scintilla/Scintilla.h>
#import <Scintilla/ScintillaView.h>
#import "SciLexer.h"

// Aus liblexilla.dylib. Der Rückgabewert ist ein Scintilla::ILexer5 *, den
// Scintilla mit SCI_SETILEXER übernimmt und selbst wieder freigibt.
// Unbekannter Name: NULL.
void *_Nullable CreateLexer(const char *_Nonnull name);
int GetLexerCount(void);
void GetLexerName(unsigned int index, char *_Nonnull name, int buflength);
