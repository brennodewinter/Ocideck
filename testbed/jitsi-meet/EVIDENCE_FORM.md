# Bewijsformulier — Jitsi-callproef (#2540)

Kopieer per proefrun. Eén regel per stap uit `PROCEDURE.md`; status is
altijd expliciet `geslaagd`, `gefaald` of `niet getest` — nooit blanco.

## Identiteit van de proef

| Veld | Invulling |
|---|---|
| Datum + tester | |
| OciDeck-commit / releaseartefact | |
| Client A (type + versie) | bijv. `ocideck@<commit>` of `Chrome 155 headless` |
| Client B (type + versie) | |
| OS + versie | |
| Jitsi-image-versie (`.env`) | `stable-…` |
| Image-digests (4 services) | uit `evidence/images.txt` |
| Kamernaam | `ocideckproef-…` |
| Randapparaten | mic/camera of `fake-device` |

## Resultaten

| # | Stap (PROCEDURE.md) | Status | Waarneming / logreferentie |
|---|---|---|---|
| 1 | host join + room-allocatie | | |
| 2 | guest anoniem binnen | | |
| 3 | tweeweg-audio testsignaal | | |
| 4 | tweeweg-video testsignaal | | |
| 5 | mute/demute | | |
| 6 | camera uit/aan | | |
| 7 | schermdelen | | |
| 8 | reconnect na `restart prosody` | | |
| 9 | leave + rejoin | | |
| 10 | gast geweigerd vóór host | | |
| 11 | fout wachtwoord geweigerd | | |
| 12 | media-E2EE-status | | |

## Netwerkbewijs

| Pad | Verwacht | Waargenomen |
|---|---|---|
| Signalling | ws → :8000/xmpp-websocket of :15280 | |
| SFU | UDP → 127.0.0.1:10000 | |
| TURN/STUN | geen verkeer | |
| Extern egress | geen | |

## Bijlagen en conclusie

- Bewijsmap (`collect-evidence.sh`): `evidence/…` — bevat context, digests,
  geredigeerde servicelogs, verify-uitvoer.
- Redactie nagelezen: `ja / nee`
- Conclusie: `geslaagd / gefaald` + één regel waarom.
