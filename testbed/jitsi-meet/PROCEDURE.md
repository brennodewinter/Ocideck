# Testprocedure — Jitsi-callproef (#2540)

Vaste stappen voor elke callproef tegen deze testomgeving. Vul per run het
formulier in `EVIDENCE_FORM.md` in; elk resultaat is expliciet
`geslaagd / gefaald / niet getest`. Een ingevuld UI-vakje telt niet: bewijs
wat er bij de **andere** client aankomt.

## Voorbereiding

1. `cd testbed/jitsi-meet && ./run.sh init && ./run.sh up && ./run.sh users`
2. `./run.sh verify` — rookproef groen (web 200, WS-antwoord, jicofo/jvb
   verbonden).
3. Kies een kamernaam, bijv. `ocideckproef-<datum>`. Noteer
   OciDeck-commit, OS/browser-versies en de image-digests
   (`./collect-evidence.sh` doet dit mee).
4. Client A = OciDeck-releasebuild **of** (zolang #2534 niet geland is) een
   tweede browser. Client B = de jitsi-web-UI uit deze stack.

## Stappen

| # | Stap | Verwacht resultaat | Bewijs |
|---|---|---|---|
| 1 | A opent `http://localhost:8000/<kamer>` en logt in als `host` | room wordt aangemaakt; A ziet eigen tegel | prosody: `Authenticated as host@meet.jitsi`; jicofo: room-allocation |
| 2 | B opent dezelfde URL anoniem | B komt binnen zodra de kamer bestaat; beide zien 2 deelnemers | roster op beide schermen; jicofo `member joined` |
| 3 | Tweeweg-audio: A speelt herkenbaar testsignaal (toon/spraak: "alfa-twee-drie") | B hoort het signaal, niet uit eigen speaker | opname/schermopname bij B |
| 4 | Tweeweg-video: A toont testsignaal (kaart/patroon, niet gezicht) | B ziet het beeld; omgekeerd idem | screenshots beide kanten |
| 5 | A mute → B bevestigt icoon + stilte; A demute → signaal terug | mute/unmute zichtbaar en hoorbaar | screenshots + audio-notitie |
| 6 | A camera uit → avatar/initialen bij B; camera aan → beeld terug | camera-toggle werkt | screenshots |
| 7 | Schermdelen vanuit A (venster of scherm) | B ziet het gedeelde scherm als tegel | screenshot bij B |
| 8 | Reconnect: `docker compose restart prosody` terwijl de call loopt | clients melden verbindingsverlies en verbinden opnieuw; call herstelt | beide schermen + prosody-log |
| 9 | B verlaat de kamer; A ziet 1 deelnemer; B joint opnieuw | leave/join-cyclus werkt herhaaldelijk | roster-schermen |
| 10 | Weigering gast vóór host: B opent een **nieuwe** kamer anoniem | "wachten op moderator", geen deelname | screenshot wachtscherm |
| 11 | Weigering account: A probeert `host` met fout wachtwoord | login geweigerd, geen deelname | screenshot foutmelding |
| 12 | Media-E2EE-status vastleggen (jitsi-e2ee in instellingen/UI) | status is `uit` in deze pin — dat is het gevraagde feit | screenshot instelling |

## Netwerkbewijs (per run scheiden)

Leg in het formulier per pad vast wat er liep:

- **Signalling:** ws naar `localhost:8000/xmpp-websocket` (via web-proxy) of
  `localhost:15280` (direct) — prosody `Client connected` /
  `Authenticated as …` in `prosody.log`.
- **SFU/JVB:** ICE op UDP `127.0.0.1:10000` — `jvb.log` toont endpoint-
  creatie + `ICE state … Running` per deelnemer.
- **TURN/STUN:** `niet aanwezig` — geen STUN-verzoeken; elk extern verzoek in
  de logs is een bevinding op de pin, niet een randgeval.

## Afbakening bewijs

- Deel je logs, gebruik dan `./collect-evidence.sh` — die redigeert
  wachtwoorden uit `.env`, `jwt=`/`token=`-parameters en niet-loopback-IP's.
- Lees de geredigeerde bestanden na: redactie is best-effort.
- Geen productieaccounts, geen productiedata, geen publieke
  Jitsi-deployment: deze proeven lopen uitsluitend tegen de gepinde stack.
  Een publieke Jitsi is hooguit een *aanvullende* compatibiliteitsproef.
