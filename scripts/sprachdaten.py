"""Sprachen und Farbschemata aus dem Quellcode von Notepad++ für Kladde aufbereiten.

Aufruf: python3 -I scripts/sprachdaten.py <notepad-plus-plus> <ziel>

Liest
  PowerEditor/src/ScintillaComponent/ScintillaEditView.cpp   Tabelle Sprache → Lexer
  PowerEditor/src/langs.model.xml                             Endungen, Kommentare, Schlüsselwörter
  PowerEditor/src/stylers.model.xml                           Farbschema «Standard»
  PowerEditor/installer/themes/*.xml                          die übrigen Farbschemata
und schreibt
  <ziel>/sprachen.json
  <ziel>/farbschemata/<Name>.json   (eine Datei je Schema, die App lädt sie erst bei Bedarf)
  <ziel>/farbschemata.json          (die Namen, in Menüfolge)

Die Daten bleiben, wie Notepad++ sie führt; nur das Format ändert sich.
"""

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# Diese Einträge der Tabelle erscheinen nicht im Menü «Sprache».
NICHT_IM_MENUE = {
    "udf",           # benutzerdefinierte Sprache: eigener Lexer, später
    "searchResult",  # Ergebnisliste der Suche von Notepad++
    "javascript",    # JavaScript eingebettet in HTML; liefert dort nur Farben und Wörter
}

KLASSEN = ["instre1", "instre2", "type1", "type2", "type3", "type4", "type5", "type6", "type7"]


def tabelle(npp: Path):
    quelle = (npp / "PowerEditor/src/ScintillaComponent/ScintillaEditView.cpp").read_text(encoding="utf-8")
    anfang = quelle.index("ScintillaEditView::_langNameInfoArray[")
    ende = quelle.index("};", anfang)
    zeilen = re.findall(
        r'\{L"([^"]*)",\s*L"([^"]*)",\s*L"([^"]*)",\s*(L_\w+),\s*"([^"]*)"\}', quelle[anfang:ende])
    if len(zeilen) < 90:
        sys.exit(f"Sprachtabelle in ScintillaEditView.cpp nicht erkannt ({len(zeilen)} Zeilen)")
    return {name: {"kurz": kurz, "lang": lang, "id": lid, "lexer": lexer} for name, kurz, lang, lid, lexer in zeilen}


def sprachen(npp: Path):
    eintraege = tabelle(npp)
    wurzel = ET.parse(npp / "PowerEditor/src/langs.model.xml").getroot()
    liste = []
    for sprache in wurzel.iter("Language"):
        name = sprache.get("name")
        eintrag = eintraege.get(name)
        if eintrag is None:
            continue
        woerter = {}
        for kw in sprache.iter("Keywords"):
            text = " ".join((kw.text or "").split())
            if text:
                woerter[kw.get("name")] = text
        liste.append({
            "name": name,
            "kurz": eintrag["kurz"],
            "lang": eintrag["lang"],
            "lexer": eintrag["lexer"],
            "imMenue": name not in NICHT_IM_MENUE,
            "endungen": (sprache.get("ext") or "").split(),
            "kommentarZeile": sprache.get("commentLine") or None,
            "kommentarAnfang": sprache.get("commentStart") or None,
            "kommentarEnde": sprache.get("commentEnd") or None,
            "woerter": woerter,
        })
    return liste


def farbe(text):
    text = (text or "").strip()
    return int(text, 16) if re.fullmatch(r"[0-9A-Fa-f]{6}", text) else None


def zahl(text):
    text = (text or "").strip()
    return int(text) if text.lstrip("-").isdigit() else None


def stil(knoten):
    s = {"id": int(knoten.get("styleID", "0"))}
    for schluessel, wert in [("vorne", farbe(knoten.get("fgColor"))), ("hinten", farbe(knoten.get("bgColor"))),
                             ("schrift", zahl(knoten.get("fontStyle")))]:
        if wert is not None:
            s[schluessel] = wert
    klasse = knoten.get("keywordClass")
    if klasse in KLASSEN:
        s["klasse"] = klasse
        woerter = " ".join((knoten.text or "").split())
        if woerter:
            s["woerter"] = woerter
    return s


def farbschema(datei: Path, name: str):
    wurzel = ET.parse(datei).getroot()
    schema = {"name": name, "global": {}, "lexer": {}}
    for knoten in wurzel.iter("WidgetStyle"):
        schema["global"][knoten.get("name")] = stil(knoten)
    for lexer in wurzel.iter("LexerType"):
        schema["lexer"][lexer.get("name")] = [stil(k) for k in lexer.iter("WordsStyle")]
    return schema


def hauptprogramm():
    npp, ziel = Path(sys.argv[1]), Path(sys.argv[2])
    (ziel / "farbschemata").mkdir(parents=True, exist_ok=True)

    liste = sprachen(npp)
    (ziel / "sprachen.json").write_text(json.dumps(liste, ensure_ascii=False), encoding="utf-8")

    quellen = [("Standard", npp / "PowerEditor/src/stylers.model.xml")]
    quellen += sorted(((d.stem, d) for d in (npp / "PowerEditor/installer/themes").glob("*.xml")),
                      key=lambda p: p[0].lower())
    namen = []
    for name, datei in quellen:
        schema = farbschema(datei, name)
        (ziel / "farbschemata" / f"{name}.json").write_text(json.dumps(schema, ensure_ascii=False), encoding="utf-8")
        namen.append(name)
    (ziel / "farbschemata.json").write_text(json.dumps(namen, ensure_ascii=False), encoding="utf-8")
    print(f"{len(liste)} Sprachen, {len(namen)} Farbschemata")


hauptprogramm()
