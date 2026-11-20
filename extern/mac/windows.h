// Ersatz für <windows.h> beim Bau von Lexilla auf dem Mac.
//
// Nur lexers/LexUser.cxx (benutzerdefinierte Sprachen von Notepad++) bindet
// <windows.h> ein, und braucht davon nur _itoa.
#pragma once

#include <cstdio>

inline char *_itoa(int wert, char *ziel, int basis) {
    if (basis == 16) {
        std::snprintf(ziel, 34, "%x", wert);
    } else {
        std::snprintf(ziel, 34, "%d", wert);
    }
    return ziel;
}
