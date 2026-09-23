# FTS Printer – verbindliche Produktionsspezifikation

Stand: 2026-09-24

Diese Datei hält die verbindlich vereinbarten Regeln für die endgültige FTS-Printer-App fest.

## Abholcode und Kundenbenachrichtigung

- Jeder bezahlte Selfie-Druckauftrag besitzt einen Abholcode.
- Derselbe Abholcode ist beim Kunden und in der Printer-App sichtbar.
- Mehrere bezahlte Exemplare eines Auftrags werden automatisch als Stückzahl übernommen und vollständig abgearbeitet.
- Ein Auftrag wird erst dann auf **ABHOLBEREIT** gesetzt, wenn alle bezahlten Exemplare erfolgreich gedruckt wurden.
- Erst bei **ABHOLBEREIT** darf die Kundenbenachrichtigung ausgelöst werden.
- Zieltext der Benachrichtigung: „Deine Fotos sind fertig. Abholcode: <CODE>.“
- Der Mitarbeiter gleicht bei der Ausgabe den Kunden-Abholcode mit dem Abholcode in der Printer-App ab.
- Wenn Push-Benachrichtigungen vom Kunden nicht erlaubt sind, muss der Status auf der Selfie-Seite trotzdem sichtbar sein: **Fertig zum Abholen · Code <CODE>**.
- Die vollständige Gast-Push-Funktion wird bewusst **erst zum Schluss**, nach einer stabil laufenden Printer-App, im Gesamtsystem fertiggestellt.
- Bis dahin darf die Printer-App die Logik **ABHOLBEREIT** und Abholcode bereits vollständig unterstützen, ohne eine Push-Zustellung zu behaupten.

## Kundenbeleg / Rechnungsausgabe

Die bestehende Backend-Logik für Kundenbelege wird in der neuen Printer-App sichtbar gemacht und weiterverwendet.

- Jeder erfolgreich bezahlte Selfie-Auftrag besitzt einen gespeicherten Beleg mit eindeutiger Belegnummer.
- Der Beleg enthält mindestens:
  - Belegnummer
  - Veranstaltung / Event
  - Veranstalter / Verein
  - Veranstaltungsdatum
  - Abholcode
  - Anzahl der Fotoprints
  - Einzel-/Gesamtbetrag und Währung
  - Zahlungsart / Zahlungsstatus
  - Zahlungszeitpunkt
  - Positionen der bestellten Fotoprints
- In der Printer-App gibt es am Auftrag und im Abholbereich einen klaren Button **„Beleg für Kunden“**.
- Der Beleg kann angezeigt und über **„Beleg drucken / PDF“** ausgegeben werden.
- Der Foto-Drucker wird dabei nicht als Belegdrucker missbraucht. Belege gehen an einen separat gewählten Dokumentdrucker oder werden als PDF ausgegeben.
- Der Abholcode muss auf dem Beleg sichtbar sein, damit Auftrag, Kunde und Fotoausgabe eindeutig zusammenpassen.
- Bereits archivierte Aufträge behalten ihre Belegdaten unabhängig davon, ob die Fotodatei später gelöscht wird.

## Kundenabholung

Die neue App erhält einen eigenen, kompakten Arbeitsbereich **„Kundenabholung“**, ohne das festgelegte Dashboard-Design zu überladen.

- Ein vollständig gedruckter Selfie-Auftrag wechselt automatisch in **READY_FOR_PICKUP / ABHOLBEREIT**.
- Solche Aufträge verschwinden aus der normalen Druckwarteschlange und erscheinen in **Kundenabholung**.
- Im Dashboard wird nur eine kompakte Kachel / ein Zähler angezeigt, z. B. **„Kundenabholung · 7 warten“**.
- Auf dem Mac wird der Abholbereich als eigener Navigationspunkt oder kompakter Unterbereich von „Druckaufträge“ umgesetzt; auf dem Handy als entsprechende mobile Karte.
- In der Abholliste stehen gut sichtbar:
  - Abholcode
  - Event
  - Anzahl Ausdrucke
  - Status „Abholbereit“
  - Zeitpunkt der Fertigstellung
  - Button **„Beleg für Kunden“**
  - Hauptbutton **„Foto abgeholt“**
- Die Liste ist nach Abholbereitschaft sortiert; noch nicht abgeholte Fotos bleiben dort stehen, bis sie wirklich ausgegeben wurden.
- Optional kann direkt nach dem sechsstelligen Abholcode gesucht werden, damit der Mitarbeiter einen Kunden sofort findet.

## Abgeholt und Archiv

Für den Mitarbeiter soll die Ausgabe ein einziger Vorgang sein.

- Beim Klick auf **„Foto abgeholt“** prüft die App, dass der Auftrag vollständig gedruckt und **ABHOLBEREIT** ist.
- Intern wird zuerst **PICKED_UP / ABGEHOLT** mit Zeitstempel und Mitarbeiter-Audit gesetzt.
- Direkt danach wird der Auftrag automatisch auf **ARCHIVED / ARCHIVIERT** gesetzt.
- Der Mitarbeiter braucht dafür keinen zweiten Archiv-Button.
- Der Auftrag verschwindet danach aus **Kundenabholung** und erscheint im **Archiv**.
- Das Archiv bewahrt weiterhin Auftrag, Abholcode und Belegdaten auf.
- Wird ein Auftrag später bewusst aus dem Archiv endgültig gelöscht, soll er auch aus der Archivansicht verschwinden. Eine endgültige Löschung darf nicht versehentlich durch „Foto abgeholt“ ausgelöst werden; sie bleibt eine getrennte, ausdrücklich bestätigte Admin-Aktion.

## Bereits vorhandene Backend-Grundlage

Die aktuelle Supabase-Struktur enthält bereits wesentliche Teile dieser Logik:

- Druckaufträge besitzen bereits **pickup_code**, **pickup_status**, **pickup_ready_at**, **picked_up_at** und **pickup_archived_at**.
- Beim bestätigten Drucken kann der Auftrag bereits automatisch auf **READY_FOR_PICKUP** gesetzt werden.
- Es existiert bereits eine Printer-Funktion zum Markieren als **PICKED_UP** mit Mitarbeiter-/Geräte-Audit.
- Eine Archivfunktion für abgeholte Aufträge ist ebenfalls vorhanden.
- Für Belege existiert bereits eine eigene Belegtabelle mit Event-, Veranstalter-, Zahlungs-, Positions- und Abholcode-Snapshots.
- Die Printer-Schnittstelle kann bereits einen Beleg über die Order-ID laden.
- Die neue App muss diese vorhandenen Bausteine sauber in die festgelegte Benutzeroberfläche integrieren, statt eine zweite parallele Beleg-/Abhollogik zu erfinden.

## Reihenfolge

1. Endgültige Printer-App stabil fertigstellen.
2. Druck-, Mehrdrucker-, Bestands-, SD-/Fotobox-, Beleg-, Abholcode-, Abhol- und Archivlogik vollständig testen.
3. Danach Gast-Push im gesamten System fertigstellen und an **ABHOLBEREIT** anbinden.
