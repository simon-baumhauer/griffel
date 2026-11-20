// Eine kleine Aufgabenliste mit Fälligkeit und Priorität.

type Prioritaet = "hoch" | "mittel" | "tief";

interface Aufgabe {
  id: number;
  titel: string;
  erledigt: boolean;
  faellig?: Date;
  prioritaet: Prioritaet;
}

export class Aufgabenliste {
  private aufgaben: Aufgabe[] = [];
  private naechsteId = 1;

  hinzufuegen(titel: string, prioritaet: Prioritaet = "mittel"): Aufgabe {
    const neu = { id: this.naechsteId++, titel, erledigt: false, prioritaet };
    this.aufgaben.push(neu);
    return neu;
  }

  faelligAm(id: number, datum: Date): void {
    const aufgabe = this.aufgaben.find((a) => a.id === id);
    if (aufgabe) aufgabe.faellig = datum;
  }

  erledigen(id: number): void {
    const aufgabe = this.aufgaben.find((a) => a.id === id);
    if (aufgabe) aufgabe.erledigt = true;
  }

  offene(): Aufgabe[] {
    return this.aufgaben.filter((a) => !a.erledigt);
  }

  ueberfaellig(heute = new Date()): Aufgabe[] {
    return this.offene().filter((a) => a.faellig && a.faellig < heute);
  }
}

export function nachPrioritaet(liste: Aufgabe[]): Aufgabe[] {
  const rang: Record<Prioritaet, number> = { hoch: 0, mittel: 1, tief: 2 };
  return [...liste].sort((a, b) => rang[a.prioritaet] - rang[b.prioritaet]);
}
