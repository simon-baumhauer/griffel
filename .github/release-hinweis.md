Ein Texteditor für den Mac nach dem Vorbild von Notepad++ – Scintilla und Lexilla wie dort, die Oberfläche in Swift nachgebaut. Für Apple Silicon und Intel, ab macOS 13.

## Neu in 1.2.0

- Hinweise beim Überfahren der Werkzeugleiste: Name, Kürzel und in einem Satz, was der Befehl tut; dieselben Sätze als Tooltip in den Menüs
- Aufklappmenüs ▾ an Öffnen (zuletzt benutzte Dateien), Speichern, Schließen, Drucken, Suchen, Vergrößern, Alle Zeichen, Funktionsliste und Makro abspielen (gesicherte Makros)
- Rechtsklick auf die Werkzeugleiste wählt die Symbole: klassisch, Fluent oder Fluent gefüllt
- Menütexte nennen «⌘ + Mausrad» statt «STRG + Mausrad»

## Neu in 1.1.0

Die Oberfläche sieht jetzt aus wie die von Notepad++; nur Fensterrahmen und Menüleiste oben sind vom Mac.

- Ein Fenster für alle Dateien, Werkzeugleiste mit den Original-Symbolen, Tableiste mit Heften und Schliessen
- Alle Menüs und Kürzel von Notepad++ mit den deutschen Texten; was Kladde noch nicht kann, steht ausgegraut
- Suchen-Dialog mit den Reitern Suchen, Ersetzen, In Dateien suchen und Hervorheben; Suchergebnis unten im Fenster; inkrementelle Suche
- Seitenleisten: Dokumentenliste, Miniaturansicht, Ordner als Arbeitsbereich, Funktionsliste
- Statusleiste wie in Notepad++
- Neu: Drucken, synchrones Scrollen, Datei überwachen, Hashwerte, «Ausführen …», Sitzungen als Datei

Die Tastenkürzel sind jetzt die von Notepad++ (⌘ statt Ctrl, ⌥ statt Alt); einige weichen darum von 1.0 ab, etwa Ersetzen (⌃H) und Gehe zu (⌘G).

## Installieren

1. Das DMG unten herunterladen und öffnen, **Kladde** in **Programme** ziehen.
2. Kladde ist nicht bei Apple beglaubigt. Beim ersten Öffnen meldet macOS darum, die App könne nicht geprüft werden. Dann **Systemeinstellungen → Datenschutz & Sicherheit** öffnen und bei «Kladde» auf **Dennoch öffnen** klicken. Wer das Terminal vorzieht:

   ```
   xattr -dr com.apple.quarantine /Applications/Kladde.app
   ```

Was Kladde kann, steht im [README](https://github.com/simon-baumhauer/kladde#readme).
