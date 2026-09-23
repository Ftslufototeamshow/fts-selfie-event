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
- Der Mitarbeiter gleicht bei der Ausgabe den Kunden-Abholcode mit dem Abholcode in der Printer-App ab und bestätigt danach **Abgeholt**.
- Wenn Push-Benachrichtigungen vom Kunden nicht erlaubt sind, muss der Status auf der Selfie-Seite trotzdem sichtbar sein: **Fertig zum Abholen · Code <CODE>**.
- Die vollständige Gast-Push-Funktion wird bewusst **erst zum Schluss**, nach einer stabil laufenden Printer-App, im Gesamtsystem fertiggestellt.
- Bis dahin darf die Printer-App die Logik **ABHOLBEREIT** und Abholcode bereits vollständig unterstützen, ohne eine Push-Zustellung zu behaupten.

## Reihenfolge

1. Endgültige Printer-App stabil fertigstellen.
2. Druck-, Mehrdrucker-, Bestands-, SD-/Fotobox- und Abholcode-Logik vollständig testen.
3. Danach Gast-Push im gesamten System fertigstellen und an **ABHOLBEREIT** anbinden.
