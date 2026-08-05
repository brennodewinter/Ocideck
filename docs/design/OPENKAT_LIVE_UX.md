# OpenKAT live-koppeling — gebruikersreis en teksten (v1)

> **Status:** ontwerpappendix bij bouw · **Datum:** 2026-08-05 · **Taal:** NL
> (bron voor `l10n.d`) · **Payload-pad v1:** **B** (begeleidde JSON-export);
> A (REST-JSON) en C (sessie-download) zijn follow-up, niet stil gebouwd.

Dit document is de gebruiksgemak-oplevering vóór code: stappen zoals de
gebruiker ze beleeft, standaardwaarden, en de exacte interface-teksten.
Technisch contract: [OPENKAT_ROCKY_REPORT_API.md](OPENKAT_ROCKY_REPORT_API.md).

---

## Wat eruit is gelaten (bewust)

- Recipe aanmaken / plannen vanuit OciDeck
- Multi-organisatie-rapport / ReportData-upload
- Octopoes of Bytes rechtstreeks
- Stille sessie-/cookie-login voor `?json=true` (pad C)
- Globale “actieve server” die stil wisselt
- Portfolio/vergelijking over meerdere installaties in één run
- Knox-/OOI-/viewset-jargon in de UI

---

## Productkeuze payload

Rocky REST levert metadata, niet de JSON-envelope die OciDeck importeert.

| Pad | v1 | Toelichting |
|---|---|---|
| **B — begeleidde export** | **default** | Lijst orgs/rapporten via API; gebruiker exporteert JSON in Rocky en kiest bestand/map in OciDeck |
| A — REST `…/json/` | follow-up | Client heeft al `fetchReportJson`; gebruikt zodra upstream het heeft |
| C — sessie-download | follow-up | Alleen als veilig en onderhoudbaar; nooit als verborgen 2FA-hack |

---

## Standaardwaarden

| Keuze | Standaard | Waarom |
|---|---|---|
| Integratie OpenKAT | uit | Zelfde patroon: niet iedereen heeft dit nodig |
| Eigen netwerk (LAN) | uit | HTTPS verplicht; privé-IP alleen met expliciete toestemming |
| Token-veld bij bewerken | leeg = ongewijzigd | Voorkomt per ongeluk wissen |
| Rapportfilter | alleen aggregaat-organisatierapport | Zelfde vorm als map-import vandaag |
| Web | zichtbaar, uitgeschakeld | Keychain niet veilig op web (LibrePlan-patroon) |

---

## Reis 1 — Integratie aanzetten

**Intentie:** OpenKAT gebruiken zonder dat het de rest van de app vervuilt.

1. Instellingen → Integraties → schakelaar **OpenKAT** aan.
2. Body toont twee blokken onder één hiërarchie (geen twee concurrerende
   hoofdknoppen):

### Blok A — Vanuit een map

- Titel: `Vanuit een map`
- Uitleg: `Kies de map waarin OpenKAT de rapportages heeft geplaatst. OciDeck leest deze map alleen; er wordt niets gewijzigd of verstuurd.`
- Knoppen: `Map kiezen…` · `Wissen` · `Rapportages controleren…`
- Lege padtekst: `Geen map gekozen`

### Blok B — Vanuit een OpenKAT-server

- Titel: `Vanuit een OpenKAT-server`
- Uitleg: `Sluit één of meer OpenKAT-omgevingen aan (bijvoorbeeld productie en acceptatie). OciDeck toont beschikbare rapportages; de inhoud haalt u binnen via een JSON-export uit OpenKAT.`
- Lege staat: `Nog geen OpenKAT-server aangesloten.` + knop `Server toevoegen…`
- Met servers: lijst kaarten + `Server toevoegen…` + `Rapportage van server…`

### Kaartintegratie (bestaand, bijgewerkt)

- Titel: `OpenKAT`
- Ondertitel: `Lees OpenKAT-rapportages in als één managementoverzicht — vanuit een map of vanaf een server.`
- Inhoudsnote (uit, maar map of server bekend): `Er staat al een OpenKAT-bron ingesteld; de koppeling blijft daarom bereikbaar, zodat een bestaand OpenKAT-deck bij te werken blijft.`
- Web-ondertitel: `De OpenKAT-koppeling is alleen beschikbaar in de desktopversie.`

---

## Reis 2 — Server toevoegen (max. 3 stappen)

Dialoogtitel: `OpenKAT-server toevoegen`

### Stap 1 — Naam en adres

- Label naam: `Weergavenaam`
- Hint naam: `Bijvoorbeeld Productie of Acceptatie`
- Label URL: `Adres van OpenKAT`
- Hint URL: `https://openkat.voorbeeld.nl`
- Onder URL (genormaliseerde host): `Verbinding met: {host}`
- Schakelaar: `Eigen netwerk (LAN)`
- Schakelaar-uitleg: `Alleen voor OpenKAT op het eigen netwerk. Staat HTTP toe en laat privé-adressen toe. Uitgeschakeld: alleen HTTPS.`
- Primair: `Volgende`
- Secundair: `Annuleren`

Vroege URL-fouten:

- `Vul een adres in, bijvoorbeeld https://openkat.voorbeeld.nl`
- `Het adres moet met https:// beginnen, of zet Eigen netwerk aan voor HTTP op het eigen netwerk.`
- `Dit adres is niet geldig. Controleer of u een volledige URL heeft ingevuld.`

### Stap 2 — Toegang

- Label: `Toegangstoken`
- Hint: `Plak het token hier`
- Uitleg: `Vraag uw OpenKAT-beheerder om een API-token in het beheerdersscherm. Het token blijft op dit apparaat, in de sleutelhanger van uw besturingssysteem — niet in het deck.`
- Primair: `Volgende`
- Secundair: `Terug`

Fouten:

- `Plak een toegangstoken om verder te gaan.`

### Stap 3 — Verbinding testen

- Status bezig: `Verbinding wordt getest…`
- Succes met orgs: `Verbonden met {host}. {n} organisatie(s) bereikbaar.`
- Succes zonder orgs: `Verbonden met {host}. Er zijn nog geen organisaties zichtbaar voor dit token.`
- Primair bij succes: `Opslaan`
- Primair bij falen / voor test: `Verbinding testen`
- Secundair: `Terug`

Fouten (wat mis is + wat te doen):

| Situatie | Tekst |
|---|---|
| Geen token | `Er is geen toegangstoken. Plak het token van uw beheerder en probeer opnieuw.` |
| 401/403 | `OpenKAT weigerde het token. Vraag uw beheerder om een geldig API-token en plak het opnieuw.` |
| Host geweigerd (privé) | `Dit adres ligt op een privé-netwerk. Zet Eigen netwerk aan als OpenKAT op uw LAN staat, of gebruik een openbaar HTTPS-adres.` |
| Host onbekend | `Dit adres is niet bereikbaar. Controleer de spelling van de hostnaam en of u op het juiste netwerk zit.` |
| Timeout | `OpenKAT reageerde niet op tijd. Controleer of de server bereikbaar is en probeer opnieuw.` |
| Netwerk algemeen | `De verbinding met OpenKAT is mislukt. Controleer het adres en uw netwerk, en probeer opnieuw.` |
| HTTP zonder LAN | `Alleen HTTPS is toegestaan, tenzij Eigen netwerk aan staat.` |
| Onverwachte status | `OpenKAT gaf een onverwacht antwoord ({code}). Probeer later opnieuw of vraag uw beheerder om hulp.` |

---

## Reis 3 — Server bewerken / verwijderen / testen

### Installatiekaart

- Regel 1: weergavenaam
- Regel 2: host
- Statuspunt + label:
  - `Verbonden` (laatst gecontroleerd gelukt)
  - `Token ontbreekt`
  - `Laatst gecontroleerd mislukt`
  - `Nog niet gecontroleerd`
- Acties: `Testen` · `Bewerken` · `Verwijderen`

### Bewerken

Dialoogtitel: `OpenKAT-server bewerken`

Zelfde velden als toevoegen; token-hint: `Laat leeg om het opgeslagen token te behouden`

### Verwijderen

Titel: `OpenKAT-server verwijderen?`

Body: `Dit verwijdert “{name}” en het bijbehorende toegangstoken van dit apparaat. Dat kunt u niet ongedaan maken.`

- Bevestigen: `Verwijderen`
- Annuleren: `Annuleren`

---

## Reis 4 — Rapportage van server

Dialoogtitel: `Rapportage van OpenKAT-server`

Altijd zichtbaar welke installatie: `Server: {name}` (`{host}`)

### Stap A — Kies server (als er ≥2 zijn)

- Lege staat: `Nog geen OpenKAT-server aangesloten.` + `Server toevoegen…`
- Primair: `Volgende`

### Stap B — Kies organisatie

- Bezig: `Organisaties worden opgehaald…`
- Leeg: `Er zijn geen organisaties zichtbaar voor dit token. Vraag uw beheerder om toegang, of kies een andere server.`
- Rij: `{name}` · code subtiel
- Primair: `Volgende`

### Stap C — Kies rapportage

- Alleen aggregaat; rij: naam + nette datum
- Bezig: `Rapportages worden opgehaald…`
- Leeg: `Er staan geen organisatierapportages klaar op deze server. Maak in OpenKAT eerst een aggregaat-organisatierapport, of kies een andere organisatie.`
- Primair: `Doorgaan`

### Stap D — Inhoud binnenhalen (pad B)

Titel in dialoog: `JSON-export uit OpenKAT`

Uitleg:

`OpenKAT levert de rapportage-inhoud als JSON-bestand. Exporteer in OpenKAT het gekozen rapport als JSON, en wijs dat bestand of de map hieraan.`

Gekozen rapport (terugkoppeling): `Gekozen: {reportName} · {orgName} · {serverName}`

Knoppen:

- `JSON-bestand kiezen…` (primair)
- `Map met exports kiezen…` (secundair — bestaande map-pijplijn)
- `Terug`

Na bestand/map → bestaande wizard / importverslag (geen tweede datamodel).

Als later pad A werkt: primaire knop wordt `Rapportage ophalen` en B blijft als
terugval zichtbaar.

---

## Reis 5 — Meerdere installaties

- Opgeslagen servers blijven staan; per run kiest u één server.
- Geen stille “actieve server”: bij elke stap `Server: {name}`.
- Portfolio over meerdere servers: later, niet v1.

---

## Commandopalet / menu

| Commando | Wanneer zichtbaar |
|---|---|
| `OpenKAT-server toevoegen…` | Integratie aan of inhoud; desktop |
| `Rapportage van OpenKAT-server…` | Idem |
| Bestaand: `OpenKAT-rapport maken…` / `bijwerken…` | Map-flow (ongewijzigd) |

---

## Toegankelijkheid

- Focusvolgorde: titel → velden → primaire knop → secundair
- Geen vaste knopbreedtes; `Wrap` bij actierijen
- Status niet alleen kleur: tekstlabel + icoon
- Contrast via `AppTheme`; tekst schaalt mee bij 200%

---

## Acceptatie (UX)

- [ ] Twee bronblokken leesbaar zonder jargon
- [ ] Toevoegen in ≤3 stappen, met test vóór opslaan
- [ ] Foutmeldingen hebben altijd een volgende handeling
- [ ] Lege staten hebben één duidelijke CTA
- [ ] Gekozen server blijft zichtbaar tijdens rapportkeuze
- [ ] Web: nette disabled-staat, geen half werkende knoppen
