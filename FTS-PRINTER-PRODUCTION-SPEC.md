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


## SD-Karte / Kameraalbum / lokale Fotobox

Dieser Bereich ist für die professionellen Kamera-/Fotobox-Fotos vorgesehen. Diese Fotos bleiben lokal auf dem Print-Laptop und werden **nicht** in den öffentlichen Selfie-Speicher hochgeladen.

### Event-Album freigeben

- Vor dem Einsatz wird für das aktuelle Event einmal der lokale Event-Album-/Ordnerbereich **freigegeben / aktiviert**.
- Danach bleibt der Mitarbeiter innerhalb der FTS Printer App; für den normalen Arbeitsablauf ist kein Wechsel in Finder/Explorer oder ein anderes Programm nötig.
- Wird eine SD-Karte eingesetzt, erkennt die App die Karte automatisch und startet den Import-/Synchronisationsprozess für das aktivierte Event-Album.
- Bereits bekannte/importierte Fotos werden nicht noch einmal angelegt.
- Neue Fotos werden automatisch in das lokale Event-Album übernommen und erscheinen anschließend automatisch in der FTS Printer App.
- Die Übertragung zwischen Album und Printer-App erfolgt lokal. Kamera-/Fotobox-Dateien werden nicht unnötig über Supabase oder die öffentliche Selfie-Galerie geleitet.
- Die App zeigt neue Fotos fortlaufend in einer übersichtlichen Galerie; das neueste Foto steht sichtbar an erster Stelle bzw. wird deutlich hervorgehoben.



### Getrennte Quellen: SD-Karten-Album und WLAN-Kamera-Album

Für ein Event können gleichzeitig zwei lokale Eingangsquellen aktiv sein:

- **SD-Karten-Album** für Fotos, die beim Einstecken einer registrierten Karte A/B/C/D importiert werden.
- **WLAN-Kamera-Album** für Fotos, die über Canon EOS Utility bzw. die Hersteller-Übertragung automatisch in einen festgelegten lokalen Empfangsordner geschrieben werden.

Beide Quellen bleiben logisch getrennt sichtbar, laufen aber nach dem Import in dieselbe FTS-Druckwarteschlange und dieselbe Mehrdrucker-Logik.

### Alte Fotos auf einer SD-Karte sicher ignorieren

Eine SD-Karte muss technisch **nicht zwingend leer** sein. Für den Eventbetrieb wird eine leere bzw. sauber vorbereitete Karte weiterhin empfohlen, aber die App muss auch mit bereits vorhandenen Ordnern/Fotos sicher umgehen.

Beim erstmaligen Aktivieren einer Karte für ein Event erstellt die App einen **Startbestand / Baseline-Snapshot** aller bereits vorhandenen unterstützten Bilddateien auf der Karte.

- Alle Dateien, die bei der Aktivierung bereits vorhanden sind, werden als **Altbestand** markiert und nicht automatisch in das aktuelle Event importiert.
- Danach importiert die App nur Dateien, die nach diesem Startbestand neu hinzukommen und noch nicht im Import-Ledger stehen.
- Das gilt auch dann, wenn die Kamera mehrere DCIM-Unterordner verwendet oder während des Events einen neuen Unterordner anlegt.
- Die App durchsucht die relevanten Bildordner der Karte, aber sie importiert nur **neue, noch unbekannte Dateien**.
- Die Erkennung basiert nicht nur auf Dateinamen, sondern zusätzlich auf Quellkarte, Pfad, Dateigröße, Änderungs-/Aufnahmezeit und Dateifingerprint.
- Gleicher Dateiname mit anderem Inhalt darf als neues Foto erkannt werden; dieselbe Datei darf nie doppelt importiert werden.
- Wird die Karte später erneut eingesteckt, zeigt die App z. B. **„Karte A erkannt · 126 bekannte Fotos · 8 neue Fotos“**.
- Wird die Karte formatiert oder neu initialisiert, gilt die alte Baseline nicht mehr; die App verlangt eine neue Aktivierung / Zuordnung statt stillschweigend alte Regeln anzuwenden.

Damit kann eine Karte noch ältere Eventfotos enthalten, ohne dass diese in das neue Event gezogen werden. Für maximale Betriebssicherheit bleibt die Empfehlung: Karten vor dem Event sauber vorbereiten und Altbestand vermeiden.

### SD-Karten A/B/C/D registrieren

Die physischen Kamera-SD-Karten werden am Anfang des Events einmal in der Printer-App registriert.

- Karte 1 bekommt die feste FTS-Bezeichnung **Karte A**.
- Karte 2 bekommt **Karte B**.
- Karte 3 bekommt **Karte C**.
- Karte 4 bekommt **Karte D**.
- Die sichtbare Kennzeichnung A/B/C/D wird zusätzlich physisch auf der jeweiligen Karte angebracht.
- Bei der Erstregistrierung zeigt die App vorhandene Fotos als Altbestand an und legt dafür den Baseline-Snapshot an. Eine leere Karte ist empfohlen, aber technisch nicht vorgeschrieben; vorhandene Altbilder werden nicht in das neue Event importiert.
- Die App speichert für die Karte eine technische Kennung und legt zusätzlich eine kleine FTS-Kartenkennung auf der Karte ab, damit dieselbe Karte beim späteren Einstecken wieder als A/B/C/D erkannt werden kann.
- Solange die Karte nach der Registrierung **nicht in der Kamera formatiert** wird, bleibt diese Kennung erhalten, auch nachdem mit der Kamera neue Fotos aufgenommen wurden.
- Wenn die Karte formatiert wurde oder die Kennung fehlt, darf die App nicht raten. Sie zeigt **„Unbekannte Karte – erneut als A/B/C/D zuordnen“**.
- Reines Fotografieren, Löschen einzelner Fotos oder erneutes Einstecken darf die A/B/C/D-Zuordnung nicht verändern.

### Kunden-/Abholnummer 001, 002, 003 …

Die Nummer **001, 002, 003 …** ist ausdrücklich **keine JPEG-Dateinummer** und verändert keine Canon-Datei.

- Canon-Dateien bleiben unverändert, z. B. **IMG_5832.JPG**.
- Für jeden neuen Kamera-/Fotobox-Kunden schlägt die Printer-App automatisch die nächste freie laufende Kundennummer vor: **001, 002, 003 …**.
- Die Kundennummer wird zusammen mit der Kartenkennung angezeigt, z. B. **A 001**, **B 001**, **A 002**.
- Der Kunde kann auf dem Papierzettel nur seine Nummer erhalten, z. B. **001 (A)**.
- Am Druckplatz sieht der Mitarbeiter dieselbe Kombination, z. B. **A 001**.
- Die Original-JPEGs werden intern nur diesem Kundenauftrag zugeordnet; sie werden nicht umbenannt.
- Ein Kundenauftrag kann mehrere Originalfotos enthalten, jeweils mit eigener gewünschter Druckmenge.
- Beispiel:
  - **A 001**
  - IMG_5832.JPG → 3×
  - IMG_5833.JPG → 1×
- Der Mitarbeiter sieht in der Oberfläche vorrangig **A 001** und die Fotos als Bildvorschau. Der Canon-Dateiname bleibt nur technische Hintergrundinformation.
- Die App schlägt die Nummern automatisch der Reihe nach vor, damit der Mitarbeiter sie nicht jedes Mal neu erfinden muss.
- Die Zählung kann pro Event neu bei **001** starten; die Kombination aus Event + Karte + Kundennummer bleibt intern eindeutig.
- Diese Kundennummer dient auch zum Wiederfinden in Warteschlange, Druckstatus und Abholung.

### Abholung bei Kamera / SD / WLAN

- Kamera-, SD- und WLAN-Aufträge verwenden nach erfolgreichem Druck denselben Bereich **Kundenabholung** wie Selfie-Aufträge.
- Die sichtbare Kennung bleibt die lokale Kundennummer, z. B. **A001**, **B001** oder **W001**; sie wird nicht mit der sechsstelligen Selfie-Kennung vermischt.
- Erst wenn alle freigegebenen Exemplare eines lokalen Kundenauftrags erfolgreich gedruckt sind, wechselt der Auftrag auf **READY_FOR_PICKUP / ABHOLBEREIT**.
- Der Mitarbeiter bestätigt die Ausgabe mit **„Foto abgeholt“**. Danach wird der lokale Auftrag mit Audit und Zeitstempel archiviert.
- Das Archivieren des Auftrags löscht oder verschiebt die lokale Originalbilddatei nicht. Das Foto bleibt im lokalen Event-Album erhalten.
- Für diese lokalen Aufträge wird kein zweiter Umsatz und kein PayPal-Beleg erzeugt, weil die Zahlung bereits über die externe Kasse / das Terminal / Cash erfolgt ist.

### Manueller Mengenentscheid durch den Mitarbeiter

Bei Kamera-/Fotobox-Fotos kommt die Zahlung aus der externen Fotokasse / dem Terminal / Cash. Deshalb gibt es in diesem Bereich **keine zweite Zahlung** in der Printer-App.

Der Mitarbeiter macht pro ausgewähltem Foto nur zwei Dinge:

1. gewünschte Stückzahl eingeben, z. B. **1, 2, 3 …**
2. **GO / Zum Druck freigeben** drücken

- Vor GO ist die Auswahl nur vorbereitet und noch nicht an einen Drucker vergeben.
- Nach GO erzeugt die App aus der Stückzahl die entsprechende Anzahl Druckeinheiten.
- Beispiel: Foto A = 2 Exemplare, Foto B = 1 Exemplar. Nach GO entstehen drei Druckeinheiten.
- Der Mitarbeiter muss nicht für jedes Exemplar noch einmal auf Drucken tippen.
- Die Stückzahl kann nur bis zur Freigabe geändert werden. Danach wird eine Änderung über einen klaren Korrektur-/Storno-Workflow behandelt, damit keine Doppelprints entstehen.

### Gemeinsame Warteschlange und automatische Druckerverteilung

Nach GO benutzt Kamera/Album exakt dieselbe technische Mehrdrucker-Logik wie bezahlte Selfie-Aufträge.

- Freie Drucker werden automatisch erkannt.
- Jede Druckeinheit wird genau einem freien Drucker zugewiesen.
- Sind zwei oder drei Drucker frei, können verschiedene Fotos bzw. Exemplare parallel gedruckt werden.
- Derselbe Auftrag darf niemals versehentlich doppelt an zwei Drucker gesendet werden, außer die gewählte Stückzahl verlangt mehrere Exemplare.
- Ist kein Drucker frei, bleibt der Auftrag sichtbar in **Wartet auf freien Drucker**.
- Sobald ein Drucker frei wird, erhält er automatisch die nächste freigegebene Druckeinheit.
- Beispiel mit zwei Druckern:
  - Printer 01 druckt Foto A / Exemplar 1
  - Printer 02 druckt Foto A / Exemplar 2 oder das nächste freigegebene Foto B
  - der nächste wartende Auftrag startet automatisch, sobald einer der Drucker wieder frei ist.
- Die App zeigt pro Einheit bzw. Auftrag den Status **Wartet**, **Zugewiesen**, **Übertragung**, **Druckt**, **Fertig**, **Prüfen/Fehler** und die geschätzte Restzeit.
- Bei einem unklaren Druckerfehler wird nicht blind auf einem anderen Drucker erneut gedruckt. Die App verlangt zuerst eine Prüfung / bewussten Nachdruck.

### Material- und Tagesstatistik

- Jeder erfolgreich ausgeführte Kamera-/Fotobox-Print reduziert den lokalen Event-Materialbestand genau einmal.
- Kamera-/Fotobox-Prints werden in der Tagesstatistik getrennt von Selfie-Prints geführt.
- Es wird **kein zweiter Umsatz** erzeugt, da Terminal/Cash bereits außerhalb der Printer-App kassiert wurde.
- Testdruck, Fehldruck und bewusster Nachdruck bleiben eigene Materialbuchungen.

### Bedienoberfläche

Im bereits festgelegten FTS-Design bekommt der Bereich **SD-Karte / Import** nach Aktivierung des Event-Albums eine kompakte Arbeitsansicht:

- aktuelles Event / aktives Album
- SD-Karte erkannt / Import läuft / aktuell
- Galerie mit den neuesten Fotos
- ausgewähltes Foto groß sichtbar
- Mengenfeld **Anzahl**
- Hauptbutton **GO · Zum Druck**
- Status der Warteschlange
- sichtbare Druckerzustände und Restzeiten

Die Oberfläche soll den Mitarbeiter im normalen Betrieb vollständig durch diesen Ablauf führen, ohne dass er das FTS-System verlassen muss.


## Automatische App-Updates · Mac und Samsung

Die endgültige FTS Printer App muss sich selbst über neue Versionen informieren. Supabase dient als zentrale Release-/Versionsquelle für beide Plattformen.

### Allgemeine Update-Logik

- Beim Start der App und danach regelmäßig bei vorhandener Internetverbindung prüft die App die aktuell veröffentlichte FTS-Printer-Version.
- Wenn die installierte Version aktuell ist, passiert nichts.
- Wenn eine neuere Version vorhanden ist, erscheint ein klarer Dialog:
  - **„Neue FTS Printer Version verfügbar“**
  - aktuelle Version
  - neue Version
  - kurze Änderungen / Release Notes
  - Hauptbutton **„Jetzt aktualisieren“**
  - Nebenbutton **„Später“**
- „Jetzt aktualisieren“ ist optisch der klare Standardweg.
- Wird „Später“ gewählt, bleibt die installierte Version aktiv, aber die App zeigt einen dezenten dauerhaften Hinweis **„Update verfügbar“** und fragt beim nächsten sinnvollen Start / Prüfzeitpunkt erneut.
- Kritische inkompatible Versionen können zentral als **Pflichtupdate** markiert werden. Dann darf „Später“ nicht mehr angeboten werden und die App erklärt, warum das Update erforderlich ist.
- Ein Update darf laufende Druckjobs niemals abrupt abbrechen. Ist gerade etwas in **Übertragung / Druckt**, wird die Installation bis zum sicheren Leerlauf verschoben.
- Vor jedem Update wird die lokale Queue persistent gespeichert. Nach Neustart werden Event, Warteschlange, Druckzustände, SD-/WLAN-Zuordnungen und nicht abgeschlossene Jobs wiederhergestellt.

### Supabase Release-Verwaltung

Für die Produktions-App wird eine eigene FTS-Printer-Release-Struktur verwendet, getrennt von allgemeinen Test-/Nexora-Releases.

Mindestens gespeicherte Felder:

- Plattform: **macOS** / **android**
- Versionsnummer
- Buildnummer
- Veröffentlichungsstatus
- Veröffentlichungsdatum
- Download-/Storage-Pfad
- SHA-256-Prüfsumme
- Release Notes
- optional: Mindestversion / Pflichtupdate
- optional: minimale unterstützte Betriebssystemversion

Die Apps lesen nur veröffentlichte Releases. Ein noch nicht freigegebener Build darf niemals als Update angeboten werden.

### macOS

- Die endgültige Mac-App bekommt eine stabile Bundle-ID und eine dauerhaft steigende Buildnummer.
- Die Produktions-App wird mit dauerhaftem FTS Developer-ID-Zertifikat signiert und notarisiert.
- Für den eigentlichen sicheren Update-Mechanismus wird ein signierter macOS-Updater verwendet; Supabase liefert Versions-/Releaseinformationen bzw. den Update-Feed.
- Updatepakete müssen zusätzlich kryptografisch geprüft werden.
- Nach Zustimmung des Benutzers wird das Update geladen und beim sicheren Zeitpunkt installiert; anschließend startet **FTS Printer** wieder.
- Die App darf nicht jedes Update als neue, getrennte „FTS Printer 014/015“-App installieren. Es bleibt dieselbe App und dieselbe Identität.

### Samsung / Android

- Vor der ersten Produktionsversion wird die Android-App mit einer **dauerhaften privaten FTS-Signatur** signiert. Alle späteren APK-Updates müssen mit exakt derselben Signatur erstellt werden, damit Android sie als Update derselben App akzeptiert.
- Die App prüft Supabase auf eine neuere Android-Version, lädt bei Zustimmung das veröffentlichte APK und prüft dessen SHA-256-Wert.
- Anschließend wird der Android-Systeminstaller für das Update geöffnet.
- Android darf aus Sicherheitsgründen die endgültige Installation nicht ohne die erforderliche System-/Benutzerbestätigung heimlich durchführen. Der Mitarbeiter bekommt deshalb nach **„Jetzt aktualisieren“** nur noch die notwendige Android-Systembestätigung.
- Nach erfolgreicher Aktualisierung startet dieselbe FTS Printer App mit erhaltenen lokalen Daten und Einstellungen weiter.
- Die aktuelle Debug/Test-Signatur darf nicht die Signatur der ersten endgültigen Produktionsversion sein.

### Update-Sicherheit

- Niemals Update ausführen, während ein Print als **Druckt / Übertragung / Status unklar** markiert ist.
- Release-Datei vor Installation auf erwartete Version und SHA-256 prüfen.
- Fehler beim Download oder Update dürfen die aktuelle funktionsfähige App nicht beschädigen.
- Bei fehlendem Internet läuft die vorhandene Version normal weiter, sofern sie nicht zentral als nicht mehr kompatibel markiert ist.
- Nach jedem Update erfolgt ein automatischer Start-Selbsttest: lokale Datenbank lesbar, Supabase-Verbindung, angemeldetes Gerät, Printer-Konfiguration und Queue-Recovery.


## Scroll-, Klick- und Bedienlogik

Die endgültige FTS Printer App muss auf Mac/iMac und Samsung vollständig bedienbar bleiben, auch wenn Listen, Karten, Drucker, Fotos oder Archiv-Einträge länger als der sichtbare Bildschirm werden.

- Alle inhaltlich langen Arbeitsbereiche sind vertikal scrollbar.
- Horizontale Printer-/Statusreihen dürfen horizontal scrollbar sein, wenn nicht alle Karten gleichzeitig in das Fenster passen.
- Scrollleisten bzw. Scroll-Indikatoren bleiben bei Arbeitslisten sichtbar bzw. eindeutig bedienbar.
- Auf Samsung verwendet die Hauptansicht eine echte ScrollView mit sichtbarer Scrollleiste, Smooth-Scrolling und Keyboard-Resize, damit Eingabefelder nicht von der Bildschirmtastatur verdeckt werden.
- Beim Wechsel zwischen Druckaufträge / Abholung / Printer springt Samsung wieder an den Anfang des neuen Arbeitsbereichs.
- Buttons und Eingabefelder müssen vollständig anklickbar/antippbar sein und eine ausreichend große Trefferfläche besitzen.
- Kritische Aktionen werden gegen Doppel-Klick/Doppel-Tap geschützt.
- Insbesondere **GO · Zum Druck**, **Foto abgeholt**, **Aus Archiv entfernen** und Materialbuchungen dürfen durch schnelles mehrfaches Klicken niemals doppelte Aufträge oder doppelte Buchungen erzeugen.
- Während eine kritische Aktion läuft, wird der zugehörige Button deaktiviert bzw. zeigt einen laufenden Status.
- SD-Karten-Zuordnung A/B/C/D ist während eines laufenden Scans/Imports gesperrt.
- Netzwerk-/Refresh-Vorgänge dürfen die Scroll- und Klickoberfläche nicht dauerhaft blockieren.
- Die endgültige Designrunde darf diese funktionale Scroll-/Klicklogik nicht entfernen oder überdecken.

## Reihenfolge

1. Endgültige Printer-App stabil fertigstellen.
2. Druck-, Mehrdrucker-, Bestands-, SD-/Fotobox-, Beleg-, Abholcode-, Abhol- und Archivlogik vollständig testen.
3. Danach Gast-Push im gesamten System fertigstellen und an **ABHOLBEREIT** anbinden.
