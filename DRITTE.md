# Fremde Bestandteile

Griffel baut auf freier Software auf. Nichts davon liegt im Repository; `scripts/extern-bauen.sh`
holt den Quellcode von Notepad++ beim ersten Bau auf einen festen Stand.

| Bestandteil | Woher | Lizenz | Wofür |
| --- | --- | --- | --- |
| Scintilla | Neil Hodgson, über den Quellcode von Notepad++ | Scintilla-Lizenz (unten) | Die Editor-Komponente |
| Lexilla | Neil Hodgson, über den Quellcode von Notepad++ | Scintilla-Lizenz (unten) | Syntaxfarben und Faltung |
| `langs.model.xml`, `stylers.model.xml`, `installer/themes/`, `installer/APIs/`, `installer/functionList/` | Don Ho und die Mitwirkenden von Notepad++ | GPL v3 | Sprachen, Farbschemata, Autovervollständigung, Funktionsliste |
| `src/icons/` (Werkzeugleiste, Tabs, Seitenleisten) | Don Ho und die Mitwirkenden von Notepad++ | GPL v3 | Symbole der Oberfläche |
| `Notepad_plus.rc`, `Parameters.cpp`, `FindReplaceDlg.rc`, `preference.rc`, die übrigen `.rc`-Dialoge, `installer/nativeLang/german.xml`, `tabContextMenu_example.xml` | Don Ho und die Mitwirkenden von Notepad++, deutsche Übersetzung von deren Übersetzerinnen und Übersetzern | GPL v3 | Aufbau und Texte der Menüs, Tastenkürzel, Layout des Suchen-Dialogs |

Griffel selbst steht unter der GPL v3 (`LICENSE`). Code von Notepad++ übernimmt Griffel nicht; die
Oberfläche ist neu geschrieben und liest Aufbau, Texte und Symbole beim Bauen aus den Dateien oben. «Notepad++» ist der Name des Vorbilds, nicht dieses Programms.

## Lizenz von Scintilla und Lexilla

```
License for Lexilla, Scintilla, and SciTE

Copyright 1998-2021 by Neil Hodgson <neilh@scintilla.org>

All Rights Reserved

Permission to use, copy, modify, and distribute this software and its
documentation for any purpose and without fee is hereby granted,
provided that the above copyright notice appear in all copies and that
both that copyright notice and this permission notice appear in
supporting documentation.

NEIL HODGSON DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS
SOFTWARE, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS, IN NO EVENT SHALL NEIL HODGSON BE LIABLE FOR ANY
SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE
OR PERFORMANCE OF THIS SOFTWARE.
```
