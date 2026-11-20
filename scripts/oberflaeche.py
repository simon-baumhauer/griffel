"""Die Oberfläche von Notepad++ als Daten für Kladde: Menüs, Tastenkürzel,
Tab-Kontextmenü, Suchen-Dialog und Statusleiste, mit den Texten der deutschen
Fassung.

Aufruf: python3 -I scripts/oberflaeche.py <notepad-plus-plus> <ziel.json>

Liest aus PowerEditor/src
  Notepad_plus.rc              Aufbau der Menüs (IDR_M30_MENU)
  menuCmdID.h, resource.h      Nummern der Befehle
  localization.cpp             welche Untermenüs welchen deutschen Namen haben
  Parameters.cpp               Tastenkürzel (winKeyDefs, scintKeyDefs)
  tabContextMenu_example.xml   Aufbau des Tab-Kontextmenüs
  ScintillaComponent/FindReplaceDlg.rc, FindReplaceDlg_rc.h   der Suchen-Dialog
und aus PowerEditor/installer/nativeLang/german.xml die deutschen Texte.
"""

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

npp = Path(sys.argv[1]) / "PowerEditor"
ziel = Path(sys.argv[2])
src = npp / "src"


def lies(pfad):
    return (src / pfad).read_text(encoding="utf-8", errors="replace")


# ---------------------------------------------------------------- Nummern

def defines(*dateien):
    roh = {}
    for d in dateien:
        for name, wert in re.findall(r"^[ \t]*#define[ \t]+(\w+)[ \t]+([^\n/]+)", lies(d), re.M):
            roh[name] = wert.strip()
    werte = {}
    for _ in range(20):
        neu = False
        for name, ausdruck in roh.items():
            if name in werte:
                continue
            text = re.sub(r"\b([A-Za-z_]\w*)\b", lambda m: str(werte[m.group(1)]) if m.group(1) in werte else m.group(1), ausdruck)
            if re.fullmatch(r"[\s()0-9xXa-fA-F+\-*|<>]+", text):
                try:
                    werte[name] = int(eval(text, {"__builtins__": {}}))
                    neu = True
                except Exception:
                    pass
        if not neu:
            break
    return werte


nummern = defines("menuCmdID.h", "resource.h")
dialog_nummern = defines("ScintillaComponent/FindReplaceDlg_rc.h", "resource.h")
dialog_nummern.setdefault("IDOK", 1)
dialog_nummern.setdefault("IDCANCEL", 2)

# ---------------------------------------------------------------- Deutsch

de = ET.parse(npp / "installer/nativeLang/german.xml").getroot()


def sauber(text):
    """«&Öffnen …» → «Öffnen …»; «&&» bleibt ein «&»."""
    return (text or "").replace("&&", "\x00").replace("&", "").replace("\x00", "&")


de_befehle = {int(e.get("id")): sauber(e.get("name")) for e in de.iter("Item") if e.get("id", "").isdigit()
              and e.get("name") is not None}
# Der Menüteil hat Vorrang vor gleichnamigen Ids in Dialogen.
menue_de = de.find(".//Menu/Main")
for e in menue_de.find("Commands").iter("Item"):
    de_befehle[int(e.get("id"))] = sauber(e.get("name"))
de_haupt = {e.get("menuId"): sauber(e.get("name")) for e in menue_de.find("Entries").iter("Item")}
de_unter = {e.get("subMenuId"): sauber(e.get("name")) for e in menue_de.find("SubEntries").iter("Item")}

# Position (oben, mitte, unten) → subMenuId, wie localization.cpp sie zuordnet.
positionen = {}
for a, b, c, kennung in re.findall(r"\{\s*(-?\d+),\s*(-?\d+),\s*(-?\d+),\s*\"([^\"]+)\"\s*\}", lies("localization.cpp")):
    positionen[(int(a), int(b), int(c))] = kennung

# ---------------------------------------------------------------- Kürzel

kuerzel = {}
tabelle = lies("Parameters.cpp")
tabelle = tabelle[tabelle.index("winKeyDefs[]"):]
tabelle = tabelle[:tabelle.index("};")]
for taste, befehl, ctrl, alt, shift in re.findall(
        r"\{\s*(VK_\w+),\s*(IDM_\w+),\s*(true|false),\s*(true|false),\s*(true|false)", tabelle):
    if taste == "VK_NULL":
        continue
    # Bei mehreren Kürzeln gewinnt eines mit Buchstabe (Ctrl+X vor Shift+Entf): das passt zum Mac.
    if befehl in kuerzel and not (len(taste) == 4 and len(kuerzel[befehl]["taste"]) > 1):
        continue
    kuerzel[befehl] = {"taste": taste[3:], "ctrl": ctrl == "true", "alt": alt == "true", "shift": shift == "true"}

# Die Kürzel der Editor-Befehle (Ctrl+D, Ctrl+L …) stehen in scintKeyDefs; ohne die auskommentierten.
tabelle = lies("Parameters.cpp")
tabelle = tabelle[tabelle.index("scintKeyDefs[]"):]
tabelle = tabelle[:tabelle.index("};")]
for zeile in tabelle.splitlines():
    if zeile.strip().startswith("//"):
        continue
    m = re.search(r'\{\s*L?"\w+",\s*\w+,\s*(true|false),\s*(true|false),\s*(true|false),\s*(VK_\w+|\'\w\'|\d+),\s*(IDM_\w+)', zeile)
    if not m:
        continue
    ctrl, alt, shift, taste, befehl = m.groups()
    if befehl in kuerzel or taste in ("VK_NULL", "0"):
        continue
    taste = taste.strip("'") if taste.startswith("'") else taste[3:]
    kuerzel[befehl] = {"taste": taste, "ctrl": ctrl == "true", "alt": alt == "true", "shift": shift == "true"}

# ---------------------------------------------------------------- Menüs

rc = lies("Notepad_plus.rc")
anfang = rc.index("IDR_M30_MENU MENU")
zeilen = rc[anfang:].splitlines()[1:]


def befehl(name, englisch):
    nummer = nummern.get(name)
    eintrag = {"art": "befehl", "id": name, "titel": de_befehle.get(nummer, sauber(englisch.split("\\t")[0]))}
    if name in kuerzel:
        eintrag["kuerzel"] = kuerzel[name]
    return eintrag


def lies_block(i, pfad):
    """Liest ab Zeile i (nach BEGIN) bis END; pfad = Position für localization.cpp."""
    eintraege = []
    while i < len(zeilen):
        z = zeilen[i].strip()
        i += 1
        if z == "END":
            return eintraege, i
        if z.startswith("MENUITEM SEPARATOR"):
            eintraege.append({"art": "trenner"})
        elif z.startswith("MENUITEM"):
            m = re.match(r'MENUITEM\s+"((?:[^"]|"")*)",\s*(\w+)', z)
            if m:
                eintraege.append(befehl(m.group(2), m.group(1)))
        elif z.startswith("POPUP"):
            englisch = re.match(r'POPUP\s+"((?:[^"]|"")*)"', z).group(1)
            stelle = len(eintraege)
            unterpfad = pfad + (stelle,)
            while zeilen[i].strip() != "BEGIN":
                i += 1
            kinder, i = lies_block(i + 1, unterpfad)
            schluessel = (unterpfad + (-1, -1))[:3]
            kennung = positionen.get(schluessel)
            eintraege.append({"art": "untermenue", "titel": de_unter.get(kennung, sauber(englisch)),
                              "kennung": kennung, "eintraege": kinder})
    return eintraege, i


hauptmenues = []
i = 0
oben = 0
haupt_kennungen = ["file", "edit", "search", "view", "encoding", "language", "settings", "tools", "macro", "run",
                   "Plugins", "Window", "?"]
sprache_gesehen = 0
anzahl_sprache = sum(1 for z in zeilen[:zeilen.index("END") if "END" in zeilen else len(zeilen)]
                     if z.startswith('    POPUP "&Language"'))
while i < len(zeilen):
    z = zeilen[i].strip()
    if zeilen[i] == "END":
        break
    if zeilen[i].startswith("    POPUP"):
        englisch = re.match(r'POPUP\s+"((?:[^"]|"")*)"', z).group(1)
        while zeilen[i].strip() != "BEGIN":
            i += 1
        # Notepad++ hat das Sprachmenü zweimal (flach und nach Buchstaben) und
        # entfernt eines zur Laufzeit; dazu das versteckte Menü «▼».
        ueberspringen = englisch == "▼"
        if englisch == "&Language":
            sprache_gesehen += 1
            ueberspringen = sprache_gesehen < anzahl_sprache
        kinder, i = lies_block(i + 1, (oben,))
        if ueberspringen:
            continue
        kennung = haupt_kennungen[oben] if oben < len(haupt_kennungen) else None
        titel = de_haupt.get(kennung) or ("?" if englisch == "&?" else sauber(englisch))
        hauptmenues.append({"titel": titel, "kennung": kennung, "eintraege": kinder})
        oben += 1
        continue
    i += 1

# ---------------------------------------------------------------- Tab-Kontextmenü

def englischer_index():
    """(Hauptmenü englisch, Eintrag englisch) → IDM-Name."""
    ergebnis = {}
    aktuell = None
    for z in zeilen:
        z = z.strip()
        m = re.match(r'POPUP\s+"((?:[^"]|"")*)"', z)
        if m and z.startswith("POPUP") and not z.startswith("POPUP \"&L"):
            name = sauber(m.group(1))
            if name in ("File", "Edit", "Search", "View", "Encoding", "Settings", "Tools", "Macro", "Run", "Window"):
                aktuell = name
        m = re.match(r'MENUITEM\s+"((?:[^"]|"")*)",\s*(\w+)', z)
        if m and aktuell:
            ergebnis[(aktuell, sauber(m.group(1)).split("\\t")[0])] = m.group(2)
    return ergebnis


index = englischer_index()
de_tab = {int(e.get("CMDID")): (sauber(e.get("name")), sauber(e.get("alternativeName") or ""))
          for e in de.find(".//TabBar").iter("Item")}
ordner_nummer = {}
tabmenue = []
ordner = {}
for e in ET.parse(src / "tabContextMenu_example.xml").getroot().iter("Item"):
    eintrag = None
    if e.get("id") == "0":
        eintrag = {"art": "trenner"}
    elif e.get("id"):
        nummer = int(e.get("id"))
        name = next((n for n, w in nummern.items() if w == nummer and n.startswith("IDM_")), str(nummer))
        titel, anders = de_tab.get(nummer, (de_befehle.get(nummer, name), ""))
        eintrag = {"art": "befehl", "id": name, "titel": titel}
        if anders:
            eintrag["anders"] = anders
    elif e.get("MenuItemName"):
        name = index.get((e.get("MenuEntryName"), e.get("MenuItemName")))
        if not name:
            continue
        nummer = nummern.get(name)
        titel = de_tab.get(nummer, (de_befehle.get(nummer, e.get("MenuItemName")), ""))[0]
        eintrag = {"art": "befehl", "id": name, "titel": titel}
    if eintrag is None:
        continue
    gruppe = e.get("FolderName")
    if gruppe:
        if gruppe not in ordner:
            nummer = len(ordner)
            ordner[gruppe] = {"art": "untermenue", "titel": de_tab.get(nummer, (gruppe, ""))[0], "eintraege": []}
            tabmenue.append(ordner[gruppe])
        ordner[gruppe]["eintraege"].append(eintrag)
    else:
        tabmenue.append(eintrag)

# ---------------------------------------------------------------- Suchen-Dialog

frc = lies("ScintillaComponent/FindReplaceDlg.rc")
block = frc[frc.index("IDD_FIND_REPLACE_DLG DIALOGEX"):]
groesse = [int(x) for x in re.match(r"IDD_FIND_REPLACE_DLG DIALOGEX\s+\d+,\s*\d+,\s*(\d+),\s*(\d+)", block).groups()]
block = block[block.index("BEGIN"):block.index("\nEND")]
de_find = de.find(".//Dialog/Find")
de_find_texte = {int(e.get("id")): sauber(e.get("name")) for e in de_find.iter("Item") if e.get("id", "").isdigit()}
elemente = []
for z in block.splitlines():
    z = z.strip()
    m = re.match(r'(\w+)\s+(?:"((?:[^"]|"")*)",\s*)?(\w+),\s*(?:"(\w+)",\s*([\w| ]+),\s*)?(\d+),\s*(\d+),\s*(\d+),\s*(\d+)', z)
    if not m:
        continue
    art, text, kennung, klasse, stil, x, y, b, h = m.groups()
    if art == "CONTROL":
        stil = stil or ""
        art = "RADIO" if "RADIO" in stil else "CHECKBOX" if "CHECKBOX" in stil else "SPLITBUTTON" if "SPLIT" in stil \
            else "SLIDER" if klasse == "msctls_trackbar32" else "CONTROL"
    nummer = dialog_nummern.get(kennung)
    elemente.append({"art": art, "id": kennung, "text": de_find_texte.get(nummer, sauber(text or "")),
                     "x": int(x), "y": int(y), "b": int(b), "h": int(h)})

suchen = {
    "titel": {k: de_find.get(k) for k in ("title", "titleFind", "titleReplace", "titleFindInFiles", "titleFindInProjects", "titleMark")},
    "groesse": groesse,
    "elemente": elemente,
}

# ---------------------------------------------------------------- Weitere Dialoge

def dialog(rc, name, header, de_name):
    """Ein Dialog aus einer .rc-Datei: Grösse, Elemente mit deutschem Text, Titel."""
    t = lies(rc)
    block = t[t.index(f"{name} DIALOGEX"):]
    groesse = [int(x) for x in re.match(rf"{name} DIALOGEX\s+\d+,\s*\d+,\s*(\d+),\s*(\d+)", block).groups()]
    block = block[block.index("BEGIN"):block.index("\nEND")]
    nummern = defines(*header, "resource.h")
    for name, wert in (("IDOK", 1), ("IDCANCEL", 2), ("IDABORT", 3), ("IDRETRY", 4), ("IDIGNORE", 5), ("IDYES", 6), ("IDNO", 7)):
        nummern.setdefault(name, wert)
    knoten = de.find(f".//Dialog/{de_name}")
    texte = {}
    listen = {}
    if knoten is not None:
        texte = {int(e.get("id")): sauber(e.get("name")) for e in knoten.iter("Item") if e.get("id", "").isdigit()}
        listen = {int(c.get("id")): [sauber(x.get("name")) for x in c.iter("Element")] for c in knoten.iter("ComboBox")}
    elemente = []
    for z in block.splitlines():
        z = z.strip()
        if z.startswith("//"):
            continue
        m = re.match(r'(\w+)\s+(?:"((?:[^"]|"")*)",\s*)?(\w+),\s*(?:"(\w+)",\s*([\w| ]+),\s*)?(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\s*(?:,\s*([\w| ]+))?', z)
        if not m:
            continue
        art, text, kennung, klasse, stil, x, y, b, h, stil2 = m.groups()
        stil = (stil or "") + "|" + (stil2 or "")
        if art == "CONTROL":
            art = ("RADIO" if "RADIO" in stil else "CHECKBOX" if "CHECKBOX" in stil
                   else "SLIDER" if klasse == "msctls_trackbar32" else "PUSHBUTTON" if klasse == "Button" else "CONTROL")
        if art == "DEFPUSHBUTTON":
            art, stil = "PUSHBUTTON", stil + "|STANDARD"
        nummer = nummern.get(kennung)
        e = {"art": art, "id": kennung, "text": texte.get(nummer, sauber(text or "")),
             "x": int(x), "y": int(y), "b": int(b), "h": int(h), "stil": stil}
        if nummer in listen:
            e["liste"] = listen[nummer]
        elemente.append(e)
    titel = knoten.get("title") if knoten is not None else name
    return {"titel": titel, "groesse": groesse, "elemente": elemente}

dialoge = {
    "gehezu": dialog("Notepad_plus.rc", "IDD_GOLINE", [], "GoToLine"),
    "ausfuehren": dialog("WinControls/StaticDialog/RunDlg/RunDlg.rc", "IDD_RUN_DLG", ["WinControls/StaticDialog/RunDlg/RunDlg_rc.h"], "Run"),
    "spalten": dialog("ScintillaComponent/columnEditor.rc", "IDD_COLUMNEDIT", ["ScintillaComponent/columnEditor_rc.h"], "ColumnEditor"),
    "makro": dialog("WinControls/shortcut/RunMacroDlg.rc", "IDD_RUN_MACRO_DLG", ["WinControls/shortcut/RunMacroDlg_rc.h"], "MultiMacro"),
    "hash": dialog("MISC/md5/md5Dlgs.rc", "IDD_HASHFROMTEXT_DLG", ["MISC/md5/md5Dlgs_rc.h"], "MD5FromTextDlg"),
    "speichern": dialog("Notepad_plus.rc", "IDD_DOSAVEORNOTBOX", [], "DoSaveOrNot"),
}

# Die Optionen: Rahmen mit Kategorienliste und die Seiten in der Reihenfolge von preferenceDlg.cpp.
_pref = "WinControls/Preference/preference.rc"
_pref_h = ["WinControls/Preference/preference_rc.h"]
optionen = {"rahmen": dialog(_pref, "IDD_PREFERENCE_BOX", _pref_h, "Preference"), "seiten": []}
for tag, name in [("Global", "GENERAL"), ("Toolbar", "TOOLBAR"), ("Tabbar", "TABBAR"), ("Scintillas", "EDITING"),
                  ("Scintillas2", "EDITING2"), ("DarkMode", "DARKMODE"), ("MarginsBorderEdge", "MARGING_BORDER_EDGE"),
                  ("NewDoc", "NEWDOCUMENT"), ("DefaultDir", "DEFAULTDIRECTORY"), ("RecentFilesHistory", "RECENTFILESHISTORY"),
                  ("Language", "LANGUAGE"), ("Indentation", "INDENTATION"), ("Highlighting", "HIGHLIGHTING"), ("Print", "PRINT"),
                  ("Searching", "SEARCHING"), ("Backup", "BACKUP"), ("AutoCompletion", "AUTOCOMPLETION"),
                  ("MultiInstance", "MULTIINSTANCE"), ("Delimiter", "DELIMITER"), ("Performance", "PERFORMANCE"),
                  ("Cloud", "CLOUD_LINK"), ("SearchEngine", "SEARCHENGINE"), ("MISC", "MISC")]:
    seite = dialog(_pref, f"IDD_PREFERENCE_SUB_{name}", _pref_h, f"Preference/{tag}")
    seite["kennung"] = tag
    optionen["seiten"].append(seite)
dialoge["optionen"] = optionen["rahmen"]

# ---------------------------------------------------------------- Statusleiste und Rest

misc = de.find(".//MiscStrings")
texte = {e.tag: e.get("value") for e in misc} if misc is not None else {}

# Seitenleisten: «DocList.PanelTitle» → «Dokumentenliste» usw.
for abschnitt in ("DocList", "DocumentMap", "FunctionList", "FolderAsWorkspace", "ClipboardHistory", "WindowsDlg"):
    knoten = de.find(f".//{abschnitt}")
    if knoten is None:
        continue
    for kind in knoten:
        if kind.get("name") is not None:
            texte[f"{abschnitt}.{kind.tag}"] = sauber(kind.get("name"))
    for item in knoten.iter("Item"):
        if item.get("id"):
            texte[f"{abschnitt}.{item.get('id')}"] = sauber(item.get("name"))
for dialog in ("GoToLine", "Run", "IncrementalFind", "MD5FromTextDlg", "SHA1FromTextDlg", "SHA256FromTextDlg", "SHA512FromTextDlg",
               "MD5FromFilesDlg", "SHA1FromFilesDlg", "SHA256FromFilesDlg", "SHA512FromFilesDlg"):
    knoten = de.find(f".//Dialog/{dialog}")
    if knoten is None:
        continue
    texte[f"{dialog}.title"] = knoten.get("title")
    for item in knoten.iter("Item"):
        texte[f"{dialog}.{item.get('id')}"] = sauber(item.get("name"))

ergebnis = {"menues": hauptmenues, "tabmenue": tabmenue, "suchen": suchen, "dialoge": dialoge, "optionen": optionen["seiten"], "texte": texte}
ziel.write_text(json.dumps(ergebnis, ensure_ascii=False, indent=1), encoding="utf-8")

anzahl = 0
def zaehle(liste):
    global anzahl
    for e in liste:
        if e["art"] == "befehl":
            anzahl += 1
        if e["art"] == "untermenue":
            zaehle(e["eintraege"])
for m in hauptmenues:
    zaehle(m["eintraege"])
print(f"{len(hauptmenues)} Menüs mit {anzahl} Befehlen, {len(kuerzel)} Kürzel, "
      f"{len(tabmenue)} Einträge im Tab-Menü, {len(elemente)} Elemente im Suchen-Dialog")
