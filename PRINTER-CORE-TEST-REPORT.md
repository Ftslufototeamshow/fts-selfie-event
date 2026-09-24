# FTS Printer – Functional Core Test Report

Stand: 2026-09-24  
Branch: `printer-core-v1`

## Scope

This report covers the production functional core before the final visual design pass. It does not claim a physical Canon SELPHY CP1500 hardware test; that requires the real Mac/printer/USB/Wi‑Fi setup.

## Automated build checks

The macOS and Android native projects are compiled by GitHub Actions on every relevant branch change.

Known green checkpoints during this hardening pass:
- macOS build run 64: success
- Android build run 41: success
- macOS build run 65: success
- Android build run 43: success
- macOS build run 67: success
- Android build run 44: success
- macOS build run 75: success
- Android build run 48: success
- Android build run 49: success

Later commits continue to use the same CI build gates.

## Supabase rollback integration tests

All database integration tests below were executed inside transactions and rolled back. No synthetic event/order/customer test rows were retained.

### Selfie quantity and multi-printer queue
PASS:
- paid quantity 3 expands to exactly 3 independent print work units
- one printer cannot claim two concurrent work units
- two different printers can claim distinct units in parallel
- order remains READY until every paid copy is completed
- after final copy: PRINTED + READY_FOR_PICKUP
- per-printer paper and film counters decrement once per physical print

### Crash and duplicate-print protection
PASS:
- stale CLAIMED unit that never started returns to READY
- stale PRINTING unit becomes UNCERTAIN, never auto-reprinted
- UNCERTAIN unit can return to READY only after explicit “not printed” confirmation

### Local SD/WLAN jobs
PASS:
- source numbering: A001, A002, B001
- safe-stock reservation blocks a local job when insufficient guaranteed stock remains
- completed local job enters pickup queue
- camera print material consumption is booked exactly once
- pickup automatically archives the job
- printer admin can remove an item from the operational archive without deleting receipt/accounting records
- invalid printer session is rejected

### RP-108 / per-printer material
PASS:
- known empty paper/film blocks new automatic claim with MATERIAL_EMPTY
- 18-sheet paper pack and 54-print film cassette are tracked independently
- local job reservation lasts across the event window instead of expiring after an arbitrary short period
- even an expired reservation that already physically printed is reconciled to the material ledger exactly once

### Queue state transitions
PASS:
- completed Selfie order disappears from active print queue
- completed Selfie order appears in customer pickup
- canceled/refunded READY/CLAIMED work units are made ineligible/cancelled by queue synchronization
- active queue only exposes orders still in READY / WAITING_PRINT

### Update metadata
PASS:
- latest published release lookup returns the highest published build
- release metadata supports platform, version/build, mandatory flag, URL/storage path, SHA-256 and notes
- Mac and Android clients validate SHA-256 before installing downloaded updates

## macOS production-core safeguards

Implemented:
- persistent local queue per event
- app restart converts a locally printing unit to UNCERTAIN instead of auto-reprinting
- silent photo spooling: system print panel stays closed
- 100×148 mm / 10×15 family output with fill crop and 1.8% overscan bleed
- conservative physical-completion floor for CP1500 jobs
- learned ETA per printer
- CUPS queue observation
- printer acceptance preflight before claiming a job
- multiple enabled printers receive different work units in parallel
- each Mac gets a stable host ID so identical queue names on another Mac do not collide
- automatic dispatcher reads authoritative queue before feeding the next job
- dispatcher does not spin when the queue is empty
- known empty paper/film blocks that printer
- temporary network outage does not create repeating modal error dialogs
- login/session/device expiry recovers to the appropriate login flow

## SD-card / WLAN safeguards

Implemented:
- separate SD and WLAN local inputs
- event-specific local album
- A/B/C/D SD card marker
- baseline snapshot prevents old card photos being imported into the current event
- SHA-256 duplicate protection
- existing Canon JPEG filename is preserved
- A/B/C/D customer code is separate from file name
- duplicate A/B/C/D card assignment is blocked
- an existing card letter can only be replaced through an explicit confirmation workflow
- formatted/lost marker is treated as unknown rather than guessed

## Android role

The Samsung app is deliberately a control/monitor/pickup station. The normal production UI no longer exposes a separate emergency phone-photo print route that could bypass the central Mac queue and create duplicate physical output.

## Remaining physical acceptance test

Before calling the functional/hardware phase fully signed off, test on the real event setup:
1. one CP1500 over USB
2. one CP1500 over Wi‑Fi
3. two printers simultaneously
4. optional third printer
5. quantity 1 / 2 / 3+ Selfie orders
6. SD card A/B/C/D import and customer numbering
7. WLAN camera input
8. paper empty and film empty
9. printer power/network interruption during PRINTING
10. app restart during an active job
11. customer pickup and receipt
12. update prompt while printers are idle vs. active

Expected safety behavior: any physically ambiguous print must end in UNCERTAIN / Prüfen, never an automatic duplicate print.
