# MySelfie → LUMOREX Live-Show (read-only)

Diese Schnittstelle gehört ausschließlich zu **MySelfie**. Sie verändert keine Fotos, Events oder Kundendaten.

## Link

Im MySelfie-Admin-Cockpit besitzt jede Veranstaltung einen eigenen geheimen LUMOREX-Link:

```
https://<supabase-project>/functions/v1/fts-lumorex-feed?t=<EVENT-TOKEN>
```

Der Token ist zufällig und eindeutig pro MySelfie-Veranstaltung.

## Antwortformat

GET liefert JSON:

```json
{
  "ok": true,
  "schema": "fts-lumorex-feed/v1",
  "read_only": true,
  "event": {
    "event_id": "uuid",
    "event_token": "e_...",
    "short_code": "EVENTCODE",
    "title": "Event"
  },
  "poll": {
    "generated_at": "2026-09-20T...",
    "requested_since": null,
    "requested_revision": null,
    "revision": "24:2026-09-20T...:photo-uuid",
    "has_new": true,
    "photo_count_total": 24,
    "returned_count": 24,
    "latest_photo_at": "2026-09-20T...",
    "next_since": "2026-09-20T...",
    "limit": 500,
    "truncated": false
  },
  "photos": [
    {
      "photo_id": "uuid",
      "event_id": "uuid",
      "event_token": "e_...",
      "image_url": "https://...",
      "image_source": "designed",
      "created_at": "2026-09-20T...",
      "event_day": "2026-09-20"
    }
  ]
}
```

Es werden ausschließlich Fotos ausgegeben, die:

- zur verknüpften MySelfie-Veranstaltung gehören,
- **kein Testfoto** sind,
- **nicht im Papierkorb** liegen.

Für `image_url` wird `designed_path` bevorzugt. Wenn kein Designpfad vorhanden ist, wird `original_path` verwendet.

## Neue Fotos erkennen

LUMOREX kann auf zwei Arten pollen:

### 1. Revision vergleichen

Jede Antwort enthält `poll.revision`. LUMOREX speichert die letzte Revision und kann sie bei der nächsten Abfrage mitsenden:

```
?revision=<LETZTE_REVISION>
```

Dann zeigt `poll.has_new`, ob sich der Fotobestand seit dieser Revision verändert hat.

### 2. Nur neue Fotos seit Zeitpunkt abrufen

LUMOREX kann den Wert aus `poll.next_since` speichern und beim nächsten Abruf mitsenden:

```
?since=2026-09-20T14%3A00%3A27.908028%2B00%3A00
```

Dann enthält `photos` nur später hinzugekommene Fotos und `poll.has_new` zeigt, ob neue Fotos vorhanden sind.

Optional:

```
&limit=500
```

Erlaubter Bereich: 1–1000.

## Event-Freigabe

Im MySelfie-Event-Editor gibt es pro Veranstaltung den Schalter **„LUMOREX / VIMA Show freigeben“**.

- **AN**: Der bestehende Read-only-Feed dieses Events ist erreichbar.
- **AUS**: Der Feed dieses Events wird sofort gesperrt und liefert keinen Fotobestand an die Live-Show-Software.
- Der Schalter kann jederzeit über **Bearbeiten** geändert werden.
- Andere MySelfie-Funktionen wie Upload, Kundenportal, Gastseite und interne Galerie bleiben davon unberührt.

## Sicherheit

- Nur GET ist erlaubt.
- Kein Upload.
- Kein Löschen.
- Keine Änderung von Fotos.
- Keine Änderung von Events oder Kundendaten.
- Keine Kundendaten werden im Feed ausgegeben.
- Der geheime Event-Link sollte wie ein Zugangsschlüssel behandelt und nicht öffentlich veröffentlicht werden.
