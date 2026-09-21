# FTS MySelfie · PayPal Sandbox Fotodruck (v45)

## Status

Die Integration ist absichtlich **Sandbox-only**. Live-PayPal ist nicht aktiviert.

Preisregel:
- 1 Ausdruck = 2,00 EUR
- Gesamtbetrag = serverseitig ermittelte Gesamtanzahl × 2,00 EUR
- der Browser übermittelt nur Foto-IDs und Mengen, niemals den vertrauenswürdigen Endbetrag

## Supabase Edge Functions

### Checkout
`paypal-selfie-checkout`

URL:
`https://hivmiqktbaatghuaxfvg.supabase.co/functions/v1/paypal-selfie-checkout`

Aufgaben:
- Sandbox-Konfiguration an den Browser liefern
- PayPal Order serverseitig erstellen
- Fotos gegen Event + anonyme Gast-Sitzung validieren
- Preis serverseitig berechnen
- PayPal Capture serverseitig durchführen
- Status abfragen / lokalen Abbruch speichern

### Webhook
`paypal-selfie-webhook`

URL:
`https://hivmiqktbaatghuaxfvg.supabase.co/functions/v1/paypal-selfie-webhook`

`verify_jwt=false`, weil PayPal den Endpoint öffentlich erreichen muss. Die Echtheit wird stattdessen serverseitig über PayPals Verify Webhook Signature API geprüft.

Abonnierte Events:
- `PAYMENT.CAPTURE.COMPLETED`
- `PAYMENT.CAPTURE.PENDING`
- `PAYMENT.CAPTURE.DENIED`
- `PAYMENT.CAPTURE.REFUNDED`
- `PAYMENT.CAPTURE.REVERSED`

Nicht `All Events` verwenden.

## Benötigte Supabase Edge Function Secrets

Diese Werte niemals in GitHub, Frontend oder Chat speichern:

- `PAYPAL_SELFIE_SANDBOX_CLIENT_ID`
- `PAYPAL_SELFIE_SANDBOX_CLIENT_SECRET`
- `PAYPAL_SELFIE_SANDBOX_WEBHOOK_ID`

Die Webhook-ID entsteht nach dem Anlegen des Webhooks in der PayPal Sandbox-App.

## Zahlungs-/Druck-Gate

Ein Druckauftrag startet als:
- `payment_status=CREATED`
- `print_status=BLOCKED`

Nur eine serverseitig verifizierte Zahlung mit:
- Status `COMPLETED`
- erwarteter Währung `EUR`
- exakt erwartetem Betrag

darf den Auftrag auf:
- `payment_status=COMPLETED`
- `print_status=READY`

setzen.

`PENDING`, `DENIED`, Abbruch und Fehler bleiben gesperrt.

`REFUNDED` / `REVERSED` sperren einen noch nicht gedruckten Auftrag wieder.

## Idempotenz

- PayPal Order-ID ist eindeutig.
- PayPal Capture-ID ist eindeutig.
- PayPal Webhook Event-ID ist eindeutig.
- Pro bezahltem Druckauftrag gibt es maximal einen Datensatz in `fts_selfie_print_jobs`.
- Create/Capture Requests verwenden stabile `PayPal-Request-Id` Werte.

Damit dürfen wiederholte Captures oder Webhook-Retries keinen zweiten Druckauftrag erzeugen.

## Event-Steuerung

Im Event-Editor:
- `Fotodruck vor Ort · PayPal Sandbox` AN/AUS
- optional `Druck verfügbar ab`
- optional `Druck verfügbar bis`

Der Besucher sieht die Druckauswahl nur, wenn die Event-Freigabe aktuell aktiv ist.

## FTS Cockpit

Pro Event gibt es `Druckaufträge`.

Dort erscheinen:
- Zahlungstatus
- Druckstatus
- Gesamtanzahl / Betrag
- die konkreten Fotos mit jeweiliger Druckmenge
- `Als gedruckt markieren` nur bei `COMPLETED + READY`

## Vor Live-Schaltung

Sandbox vollständig testen:
1. 1 Foto × 1 = 2,00 EUR
2. 1 Foto × 3 = 6,00 EUR
3. mehrere Fotos mit unterschiedlichen Mengen
4. PayPal Abbruch
5. PENDING / DENIED soweit in Sandbox simulierbar
6. COMPLETED => genau ein READY-Job
7. wiederholte Webhook-Auslieferung => kein doppelter Job
8. Refund/Reversal => Status korrekt

Erst danach getrennte Live-Credentials und Live-Webhook einrichten.
