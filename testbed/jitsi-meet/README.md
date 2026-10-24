# Gepinde Jitsi-testomgeving voor OciDeck-callproeven

Een herhaalbare, volledig lokale Jitsi-deployment waarmee een echte
OciDeck-client straks tegenover een tweede, onafhankelijke client getest kan
worden (issue #2540; ontwerp `docs/design/NATIVE_CALLS.md` §11: *a local
docker-jitsi-meet stack, never a public service*).

Dit is **niet** het Prosody-only testbed uit `testbed/docker-jitsi-meet/` —
die is bewust kaal omdat Jitsi's eigen Prosody-modules de collab-test breken.
Hier draait juist de echte volle stack: Prosody + Jicofo + JVB + jitsi-web.

## Opzetten

```sh
cd testbed/jitsi-meet
./run.sh init     # .env + gegenereerde servicewachtwoorden (eenmalig)
./run.sh up       # stack starten + wachten tot hij antwoordt
./run.sh users    # testaccounts host@meet.jitsi en guest@meet.jitsi
./run.sh verify   # rookproef: web-UI, WebSocket, jicofo/jvb-verbinding
```

Open daarna `http://localhost:8000/<willekeurige-kamernaam>` in twee browsers.
De eerste deelnemer logt in als `host` (wachtwoord in `.env` onder
`TEST_HOST_PASSWORD`); de tweede komt als anonieme gast binnen. Wachtwoorden
van de testaccounts staan alleen in `.env` — nooit in git of in de docs.

## Wat is gepind — en wat betekent dat voor het bewijs

| Wat | Waarde | Waar vastgelegd |
|---|---|---|
| Image-versie (4 services) | `stable-11248` | `.env` → `JITSI_IMAGE_VERSION` |
| Compose-wiring | eigen minimale compose | `docker-compose.yml` |
| Jitsi-domain / MUC | `meet.jitsi` / `muc.meet.jitsi` | upstream defaults |
| Signalling client→server | `ws://127.0.0.1:8000/xmpp-websocket` (via web) | `custom-config.js` |
| Signalling direct | `ws://localhost:15280/xmpp-websocket` | `PROSODY_WS_PORT` |
| Media client→SFU | UDP `127.0.0.1:10000` | `JVB_PORT`, `JVB_ADVERTISE_IPS` |
| TURN/STUN | **bewust geen** (zie grenzen) | `JVB_DISABLE_STUN=1` |
| Auth | `internal`, `ENABLE_GUESTS=1` | `.env` |
| P2P | **uit** — media loopt altijd via de JVB | `ENABLE_P2P=0` |

`stable-11248` is het docker-jitsi-meet-release van 2026-09-14 (jitsi-meet
r.11248, JVB 2.3-x, Jicofo 1.1-x, Prosody 0.13.x — de exacte digests legt
`collect-evidence.sh` vast per run). Een nieuwe claim tegen een andere versie
vereist een bewuste pin-bump én een nieuw bewijsformulier: een stille upgrade
maakt oud bewijs niet stilletjes actueel. De unittest
`test/jitsi_meet_testbed_test.dart` bewaakt dat de pin-structuur intact blijft.

## Configuratiegrenzen (wat deze omgeving níet dekt)

- **Loopback-only.** Alle poorten binden op `127.0.0.1`; het bewijs geldt
  "zelfde machine, echte stack", geen LAN/NAT-scenario's.
- **Geen TURN/STUN.** `JVB_DISABLE_STUN=1` en `DISABLE_AWS_HARVESTER=1` houden
  de stack hermetisch — geen verkeer naar buiten om te bewijzen. Een client
  achter echte NAT die de JVB niet rechtstreeks bereikt, valt buiten deze
  omgeving; dat is voor latere platformproeven met een bewuste TURN.
- **Geen opname.** Opname is hier bewust uitgelaten; die proeven starten
  apart (#2526+).
- **Plain HTTP op localhost.** Browsers behandelen `http://localhost` als
  secure context, dus WebRTC werkt. Certificaat-/TLS-gedrag van de
  signaallaag wordt apart getest (#2533 acceptatie: geweigerd certificaat).
- **Auth-model:** `internal` met lobby-voor-gasten. JWT/matrix-auth van een
  echte deployment valt buiten deze pin.

## Verkeersbeeld (voor het netwerkgedeelte van het bewijsformulier)

```
browser ──ws──> web:8000 ──proxy──> prosody:5280   (XMPP-signalling)
browser ──udp──> jvb:10000                        (RTP-media via SFU)
ocideck ──ws──> prosody:15280                     (directe XMPP-WS, #2533+)
jicofo/jvb ──xmpp──> prosody:5222 (intern netwerk meet.jitsi)
```

Extern egress: **geen** — alle verkeer blijft op loopback en het interne
docker-netwerk. Dat is een eigenschap van deze pin, geen toeval.

## Geautomatiseerde tweepersoonsproef (optioneel)

`probe/join.js` start twee echte Chrome-instanties met synthetische
fake-camera/-microfoon, logt de host in en laat de guest anoniem joinen.
Handig om snel te bewijzen dat de stack compleet werkt vóór een handmatige
proef — géén vervanging voor de handmatige matrix in `PROCEDURE.md`.

Vereist: systeem-Chrome + `npm --prefix probe install` (eenmalig; installeert
`playwright-core`, géén browserdownload).

```sh
set -a && . ./.env && set +a    # laadt TEST_HOST_PASSWORD
node probe/join.js              # exit 0 als beide clients joinen
```

`probe/wire-capture.js` (en variant `wire-mute.js`) is hetzelfde tweepersoonsspel
plus CDP-logging van elke WebSocket-frame naar `/tmp/jitsi-wire*/` — zo is de
echte Jicofo-wire vastgelegd waarop `lib/meetings/providers/jitsi/` is gebouwd.
Draai hem opnieuw bij een Jitsi-versiebump om het wire-contract opnieuw te
verifiëren; twee bevindingen staan alleen hier zichtbaar (`machine-uid` is
verplicht in de conference-IQ; MUC-resources mogen geen streepjes bevatten).

## Herhaalbaarheid

- `./run.sh down` / `up` houdt accounts en config; `./run.sh reset` maakt
  álles schoon (daarna `init` + `up` + `users`).
- Netwerkuitval opnieuw testen: `docker compose restart prosody` (signalling
  weg → clients reconnecten zelf) of `stop jvb` (media weg). Geen handmatige
  toestandsschoonmaak nodig; kamers worden bij join opnieuw gealloceerd.
- `./collect-evidence.sh` schrijft een geredigeerde bewijsmap onder
  `evidence/` (gitignored) voor bij `EVIDENCE_FORM.md`.
