# Supabase-Aufruf-Audit – FTS Selfie Event

Stand: 22.10.2026

## Ziel

Unnötige periodische Supabase-Abfragen im bestehenden FTS Selfie Event / Selfie Studio / Print Station entfernen, ohne MySelfie, Zahlungen, Online-Druckaufträge, QR-Code, Materialverwaltung oder bestehende Eventfunktionen abzuschalten.

## Gefundene Hauptursachen vor der Änderung

### Print Station

`print.html` enthielt eine Aktualisierung alle 5 Sekunden. Zusätzlich überschrieb `print-pickup-station-v57.js` später `loadCore()` und startete ebenfalls den 5-Sekunden-Zyklus.

Der dortige Zyklus lud:

1. Eventliste
2. Druckaufträge
3. Jahresübersicht
4. Materialbestand

Bei dauerhaft geöffneter Station:

- 86.400 Sekunden / 5 = 17.280 Zyklen pro Tag
- 17.280 × 4 RPCs = **69.120 RPCs pro Tag**

### FTS Cockpit / Dashboard

`dashboard.html` aktualisierte alle 8 Sekunden. Pro Zyklus wurden regelmäßig geladen:

1. Dashboard-Events
2. Event-Modi
3. Scan-Statistik
4. LUMOREX-Status

Die Fehlerübersicht wurde zusätzlich ungefähr alle 16 Sekunden neu geladen.

Bei dauerhaft geöffnetem Cockpit:

- 86.400 / 8 = 10.800 Zyklen
- 10.800 × 4 = 43.200 RPCs
- 86.400 / 16 = ca. 5.400 Fehlerübersichts-RPCs
- zusammen ca. **48.600 RPCs pro Tag**

### Plausibilitätsvergleich

Nur Print Station + Cockpit ergeben rechnerisch:

**69.120 + 48.600 = 117.720 RPCs pro Tag**

Damit ist die früher beobachtete Größenordnung von ungefähr 116.000 Aufrufen pro Tag technisch plausibel. Weitere periodische Seiten (Poster-Zähler, Gast-Abholstatus, mobile Printer-Admin-Ansicht) konnten den Verbrauch zusätzlich erhöhen.

Die historische Tageszahl lässt sich aus den aktuell verfügbaren Logs nicht mehr exakt rückwirkend reproduzieren; der Codepfad und seine mathematische Aufruffrequenz sind jedoch eindeutig.

## Änderungen

### Print Station

- Kein 5-Sekunden-Polling mehr.
- Kein verstecktes erneutes Polling aus `print-pickup-station-v57.js`.
- Realtime-Signal `fts_selfie_print_signal_v150`.
- Neue/aktualisierte Druckaufträge, Zahlung, Print-Settings und Materialänderungen erhöhen nur eine kleine Signal-Revision.
- Erst dann lädt die Print Station die betroffenen Betriebsdaten neu.
- Manueller Refresh, Sichtbarwerden der Seite und kontrollierter Reconnect bleiben erhalten.

### Cockpit

- Kein 8-Sekunden-Polling mehr.
- Realtime-Signal `fts_selfie_ops_signal_v152`.
- Event-, Foto-, LUMOREX- und relevante Issue-Änderungen lösen gezielte Aktualisierung aus.
- Manueller Refresh und einmaliger Reconnect-Abgleich bleiben erhalten.

### Poster

- Kein 10-Sekunden-Selfie-Zähler-Polling mehr.
- Initialer Zählerstand + Realtime-Signal.
- Die 3-Sekunden-Werberotation bleibt bestehen, ist aber rein lokal im Browser und erzeugt keinen periodischen Supabase-Read.

### Gast-Abholstatus

- Kein 10-Sekunden-Polling mehr.
- Realtime-Signal der Print Station.
- Aktualisierung bei echter Statusänderung, Sichtbarwerden oder Reconnect.

### Mobile Printer Admin

- Kein 5-Sekunden-Detail-Polling mehr.
- Realtime-Signal `fts_selfie_printer_admin_signal_v152`.
- Relevante Printer-, Material-, Issue-, Zahlungs- und Druckänderungen lösen Aktualisierung aus.

## Nachher – Leerlauf

Bei unveränderten Daten entstehen durch die oben genannten Ansichten **keine periodischen REST/RPC-Lesezyklen mehr**.

Es bleibt jeweils eine Realtime-Verbindung für die benötigte kleine Signalzeile. Daten werden nur neu geladen bei:

- relevanter Datenänderung
- bewusstem manuellen Refresh
- Sichtbarwerden nach Hintergrundzustand
- Wiederherstellung einer unterbrochenen Verbindung
- transaktionsbezogenen, begrenzten Zahlungsprüfungen

Lokale UI-Timer für Werbung, Cache-Aufräumen, Druckfortschritt, SD/WLAN/USB-Erkennung und lokale Printer-Hardware sind keine periodischen Supabase-Abfragen.

## Offline-/Hybrid-Speicherung

Die macOS-Printer-App unterstützt die drei Event-Speichermodi:

- `local` – Nur Laptop
- `online` – Nur Online
- `hybrid` – Laptop und Online

Lokale Eventdaten werden dauerhaft im Dateisystem gespeichert. Bilder und Einstellungen liegen nicht nur in Browser-`localStorage`.

Lokale Eventstruktur enthält unter anderem:

- Kamera Original
- Druckfotos mit Design
- Layout und Banner
- Veranstaltungseinstellungen / event.json
- WLAN Kamera Eingang
- Druckbereit
- Archiv

Der lokale Eventordner bleibt nach der ersten Anlage stabil, auch wenn Eventname oder Datum später geändert werden.

## Verifikation

- JavaScript-Syntax der geänderten Kernseiten geprüft.
- Unkontrollierte 5-/8-/10-Sekunden-Supabase-Polling-Schleifen in den geprüften Betriebsseiten entfernt.
- Realtime-Signaltabellen und Trigger in FTS Office Pro verifiziert.
- Realtime-Publikation für die Signaltabellen verifiziert.
- Native macOS-App wird über GitHub Actions als Universal-Build für arm64 und x86_64 kompiliert.
- Physischer Canon SELPHY CP1500, echte SD-Karten und echte Kamera-Hardware müssen vor Eventeinsatz weiterhin als Hardware-Smoke-Test am Mac geprüft werden.
