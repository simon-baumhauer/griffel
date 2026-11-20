"""Kleiner Rechner für Belege: Summen, Mehrwertsteuer und Anteile."""

from dataclasses import dataclass, field
from decimal import ROUND_HALF_UP, Decimal

MWST = Decimal("0.081")  # Normalsatz in der Schweiz


@dataclass
class Posten:
    text: str
    betrag: Decimal
    menge: int = 1

    def total(self) -> Decimal:
        return self.betrag * self.menge


@dataclass
class Rechnung:
    nummer: str
    posten: list[Posten] = field(default_factory=list)

    def netto(self) -> Decimal:
        return sum((p.total() for p in self.posten), Decimal(0))

    def brutto(self) -> Decimal:
        return runde(self.netto() * (1 + MWST))


def runde(betrag: Decimal) -> Decimal:
    """Auf 5 Rappen runden, wie an der Kasse."""
    return (betrag * 20).quantize(Decimal(1), rounding=ROUND_HALF_UP) / 20


def anteil(teil: Decimal, ganzes: Decimal) -> float:
    if ganzes == 0:
        raise ValueError("Das Ganze darf nicht null sein")
    return float(teil / ganzes * 100)


if __name__ == "__main__":
    r = Rechnung("2026-117")
    r.posten.append(Posten("Kaffee", Decimal("4.50"), 2))
    r.posten.append(Posten("Gipfeli", Decimal("2.20"), 3))
    print(f"Rechnung {r.nummer}: {r.brutto()} CHF")
