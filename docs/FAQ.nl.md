> 🤖 Machinevertaling — het Engelse bronbestand is leidend.
>
> _Machine translation — the English source document is authoritative. _

# OciDeck — Veelgestelde vragen

> **Status:** antwoorden over de huidige stand van zaken; waar een antwoord botst met de code, wint de code · **Status laatst nagekeken:** 2026-07-22 · **Uitgegeven door:** Stichting LibreKAT

Dit document beantwoordt veelgestelde vragen over de functies, het gebruik en de werking van OciDeck.

## Algemeen gebruik

### Hoe ondersteunt OciDeck informatieautonomie?
OciDeck ondersteunt informatieautonomie via een aantal kernprincipes:
1. **Datasoevereiniteit**: Alle presentatie-inhoud blijft op je eigen apparaat — er is geen applicatie-backend die je gegevens zou kunnen inzien of opslaan
2. **Privacy by design**: Ingebouwde privacyscanning helpt gebruikers gevoelige informatie in hun presentaties te herkennen en te beheersen
3. **Controle bij de gebruiker**: Gebruikers houden volledige controle over wat er wordt geëxporteerd, gedeeld of gepubliceerd
4. **Minimale gegevensverzameling**: Geen telemetrie, analytics of tracking van welke aard dan ook
5. **Open standaarden**: Gebruikt het standaard Marp-Markdownformaat voor maximale uitwisselbaarheid

### Waarin verschilt OciDeck van andere presentatieprogramma's?
- **Beveiligingsgericht**: Er is geen applicatie-backend voor het bewerken; je deck wordt
  op je eigen apparaat verwerkt. De netwerkverzoeken die wél plaatsvinden — inclusief de
  enkele waarvan je het adres niet zelf koos — staan opgesomd in
  [PRIVACY.md](PRIVACY.md#what-leaves-your-device--and-only-when-you-ask).
- **Privacy voorop**: Ingebouwde privacyscanning (OciWacht) om gevoelige informatie te detecteren
- **Marp-compatibel**: Leest en schrijft standaard Marp-Markdown, zodat een deck bruikbaar
  blijft in andere Marp-programma's
- **Cross-platform**: Bouwt voor macOS, Windows en Linux desktop, en voor de
  browser
- **Geen telemetrie**: Nul tracking of analytics van welke aard dan ook

### Is OciDeck gratis te gebruiken?
Ja. OciDeck wordt uitgebracht onder de opensourcelicentie EUPL-1.2, die niets
kost en je toestaat het te gebruiken, te bestuderen, te wijzigen en te herdistribueren.

Over ondertekening: het releasemanifest `SHA256SUMS` is ondertekend met minisign, zodat de
herkomst van een download verifieerbaar is (zie
[BUILD.md](BUILD.md#signing-status-of-the-published-artifacts)). Releases worden
getagd (laatste `0.1.1`, 2026-07-27) en bevatten de app voor alle vier de platformen; de
macOS-build is bovendien ondertekend en genotariseerd en opent normaal, terwijl de
**Windows- en Linux-binaries niet code-signed zijn** — Windows waarschuwt bij de eerste
start. Je kunt een releasebuild downloaden of vanuit de bron bouwen; hoe dan ook, zie
[BUILD.md](BUILD.md) en de sectie *Getting started* van de
[README](../README.md). *Gecorrigeerd 2026-07-28: hier stond "nog niets om te downloaden"
en "er is geen versie getagd" — verouderd sinds `0.1.0` op 2026-07-25.
De eerdere correctie (2026-07-21) over "volledig gratis te downloaden" blijft
staan conform de huisregel.*

## Beveiliging en privacy

### Welke beveiligingsmaatregelen implementeert OciDeck?
OciDeck implementeert diverse beveiligingslagen:
- Geen applicatie-backend voor het bewerken. Het enige optionele component aan de serverkant is
  de CORS-fetch-proxy van de webbuild (`server/fetch-proxy/`), die uitsluitend ruwe
  bytes doorgeeft — zie [ARCHITECTURE.md](ARCHITECTURE.md#runtime--network-model)
  *(gecorrigeerd 2026-07-22: hier stond "client-side only architecture with no
  backend", wat de sectie twee koppen hierboven al tegensprak)*
- Strikte netwerkcontroles via NetGuard die SSRF-aanvallen voorkomen  
- Asset-insluiting die bestanden van buiten de projectmappen tegenhoudt
- Privacyscanning (OciWacht) om gevoelige informatie te detecteren
- Classificatie-handhaving om het vrijgeven van inhoud te beheersen

### Hoe verhoudt OciDeck zich tot het OSCAR-raamwerk?
OciDeck belichaamt principes uit het OSCAR-raamwerk (Open, Secure, Control, Autonomous, Responsible), met name in zijn ontwerpfilosofie:
1. **Open**: Gebruikt open standaarden (Marp-Markdown) en is volledig opensource
2. **Secure**: Implementeert robuuste beveiligingsmaatregelen zonder applicatie-backend
3. **Control**: Geeft gebruikers volledige controle over hun gegevens en privacy-instellingen
4. **Autonomous**: Maakt gebruikersautonomie mogelijk door informatiesoevereiniteit te waarborgen
5. **Responsible**: Gebouwd met verantwoorde ontwerpprincipes en minimale gegevensverzameling

### Hoe werkt de privacyscanner?
De OciWacht-privacyscanner detecteert automatisch patronen van persoonsgegevens, waaronder:
- E-mailadressen, telefoonnummers en IBAN/bankrekeningnummers  
- Nationale identificatienummers zoals het BSN
- Adresgegevens en postcodes
- Namen in verschillende vormen

De scanner kan mogelijke problemen markeren voor beoordeling of, afhankelijk van de instellingen, gevoelige inhoud automatisch redigeren.

### Hoe verhoudt OciDeck zich tot begrippen uit 'Informatieautonomie'?
OciDeck weerspiegelt de kernprincipes die in 'Informatieautonomie' (Information Autonomy) worden verkend, door het volgende te implementeren:
1. **Gebruikerssoevereiniteit**: Gebruikers houden volledige controle over hun informatieomgeving, net zoals het boek pleit voor individuele soevereiniteit over persoonsgegevens
2. **Privacy by design**: Het programma integreert privacybescherming vanaf de basis in plaats van als bijzaak, in lijn met de nadruk van het boek op proactieve privacymaatregelen
3. **Informatiecontrole**: Biedt hulpmiddelen waarmee gebruikers controle houden over welke informatie ze delen en hoe die wordt verwerkt
4. **Digitale zelfbeschikking**: Stelt gebruikers in staat weloverwogen beslissingen over hun gegevens te nemen, ter ondersteuning van het begrip digitale zelfbeschikking uit het boek
5. **Transparantie**: Het opensourcekarakter stelt gebruikers in staat precies te begrijpen hoe hun gegevens worden behandeld, aansluitend bij de oproep van het boek tot transparantie in informatiesystemen

### Wat is TLP (Traffic Light Protocol)?
TLP staat voor Traffic Light Protocol, een classificatiesysteem dat regelt hoe informatie wordt gedeeld:
- **CLEAR**: Geen beperkingen  
- **GREEN**: Delen met collega's
- **AMBER**: Delen binnen de organisatie  
- **AMBER+STRICT**: Alleen delen met directe medewerkers
- **RED**: Alleen delen met specifieke personen

### Hoe gaat OciDeck om met gevoelige gegevens in exports?
OciDeck handhaaft strikte exportcontroles:
- Classificatiebeleid voorkomt het exporteren van inhoud boven het opgegeven TLP-niveau
- Privacyredactie kan worden toegepast om gevoelige informatie automatisch te verbergen  
- Exports worden geschoond om mogelijk onveilige elementen te verwijderen

## Bestandsformaat en compatibiliteit

### Welke bestandsformaten ondersteunt OciDeck?
- **Primair**: Markdown (.md) met Marp-formaatcompatibiliteit
- **Pakketten**: .ocideck (pakketten in één bestand)
- **Stijlprofielen**: .ocideckstyle voor het delen van thema's  
- **Afbeeldingen**: PNG, JPEG, GIF, BMP, WebP (gevalideerd op inhoud/magic bytes, niet op bestandsextensie)
- **Video/audio**: Diverse formaten ondersteund via onderliggende bibliotheken
- **Alleen importeren**: PowerPoint (.pptx), Apple Keynote (.key) en LibreOffice Impress (.odp), omgezet naar gewone OciDeck-decks achter de optionele importmodule. Alleen-lezen in één richting: OciDeck importeert deze, en exporteert PPTX, maar schrijft nooit .key of .odp. De conversie is standaard een best-effort, en bij het importeren van één bestand wordt per verliesgevoelige slide gevraagd of je die zo compleet mogelijk wilt behouden, alleen de afbeeldingen wilt behouden, of wilt overslaan — zie [Presentaties importeren](USER_GUIDE.md#importing-presentations-powerpoint-keynote-impress) in de gebruikershandleiding voor wat het wel en niet overleeft. *(Toegevoegd 2026-07-24.)*

### Hoe worden assets in OciDeck beheerd?
Assets worden georganiseerd in projectmappen met aparte submappen:
- `images/` - Afbeeldingsbestanden
- `data/` - CSV-gegevens voor grafieken  
- `logos/` - Logoafbeeldingen
- `themes/` - Thema-CSS-bestanden

Alle assetpaden zijn relatief ten opzichte van de projectmap, wat toegang buiten de aangewezen mappen voorkomt.

### Zijn OciDeck-presentaties compatibel met andere programma's?
Ja, omdat OciDeck het standaard Marp-Markdownformaat gebruikt:
- Presentaties kunnen rechtstreeks worden bewerkt in elke Marp-compatibele editor  
- HTML-exports werken in elke moderne browser
- PDF/PPTX-exports zijn compatibel met standaardsoftware

## Technische functies

### Wat is de presentatormodus met twee schermen?
De presentatormodus met twee schermen laat je twee beeldschermen tegelijk gebruiken:
- Primair scherm: Presentatorweergave met notities, timer en bediening
- Secundair scherm: Volledig scherm met de slide voor het publiek  
- Werkt op de desktopbuilds voor macOS, Windows en Linux

### Hoe werkt het knippen van video's?
OciDeck ondersteunt het "knippen" van video's over slides heen:
1. Speel een video af in het voorbeeld 
2. Klik op "Hier knippen" om op de huidige positie te splitsen
3. Het restant wordt een nieuwe slide met dezelfde bron  
4. Tijdens de presentatie stoppen segmenten op de knippunten en gaan automatisch verder

### Welke grafiektypen worden ondersteund?
OciDeck ondersteunt de volgende grafiektypen:
- Staafdiagrammen (verticaal, gestapeld, horizontaal, horizontaal gestapeld)
- Lijn- en vlakdiagrammen  
- Taart- en donutdiagrammen
- Radar-/spindiagrammen
- Spreidingsdiagrammen
- Watervaldiagrammen
- Heatmaps (die tevens als risicomatrix dienen)
- Combinatiediagrammen (staven plus de laatste reeks getekend als een lijn op een tweede as)

### Hoe werkt de AI-assistent?
De optionele AI-ondersteuning vereist expliciete toestemming van de gebruiker:
1. Ingeschakeld als module onder **Instellingen → Uitbreidingen (Extensions)** (standaard
   uit; met de module uit is er helemaal geen AI-tab in de zijbalk).
   Inschakelen laat een tab **Instellingen → AI-assistentie** verschijnen voor de backend
2. Vereist het configureren van een lokaal model of een uitgaand eindpunt; het gebruik van een
   cloud-/uitgaand eindpunt vereist daarnaast de algemene toestemming voor uitgaande privacy
   onder **Instellingen → Licentie en privacy**
3. Gebruikt voor het genereren van tekstsuggesties en alt-tekst voor afbeeldingen  
4. Alle gegevensverwerking blijft binnen de controle van de gebruiker

## Platformondersteuning

### Welke platformen ondersteunt OciDeck?
- **Desktop**: macOS, Windows, Linux (native desktopbuilds)
- **Web**: Browserversie met beperkte functies vergeleken met desktop
- **Mobiel**: Momenteel niet ondersteund als primair platform  

### Waarom verschilt de webbuild van de desktopversie?
De webbuild heeft beperkingen vanwege browserrestricties:
- Geen native toegang tot het bestandssysteem
- Geheugenbeperkingen bij grote presentaties  
- Beperkte prestaties vergeleken met de desktopversies
- Andere assetverwerking en beveiligingsbeleid

### Wat zijn de systeemvereisten voor OciDeck?
Desktopversie:
- macOS: Recente versie met Apple Silicon- of Intel-ondersteuning
- Windows: Windows 10 of nieuwer
- Linux: Moderne distributie met GTK-omgeving
- Minimaal RAM: 4GB (aanbevolen 8GB+)
- Schijfruimte: Het minimum benodigd voor applicatie + projecten

### Hoe installeer ik OciDeck op macOS met Homebrew?
Gebruik je [Homebrew](https://brew.sh/), dan installeer je OciDeck op macOS met
één commando:

```sh
brew install --cask brennodewinter/ocideck/ocideck
```

Homebrew haalt de nieuwste release rechtstreeks uit onze eigen forge en
controleert de checksum automatisch. De macOS-build is getekend met een Apple
Developer ID en genotariseerd, dus hij opent met een gewone dubbelklik. Later
bijwerken doe je met `brew upgrade --cask ocideck`.

De cask is alleen een verwijzing naar diezelfde ondertekende, genotariseerde
release — Homebrew host de app niet zelf en er komt geen extra tussenpartij bij.
Homebrew Cask bestaat alleen voor macOS; op Windows en Linux download je OciDeck
rechtstreeks van de
[releasespagina](https://pawprint.vigilis.online/LibreKAT/Ocideck/releases). Zie
[BUILD.md](BUILD.md#homebrew-cask-macos) voor hoe de cask wordt gebouwd en
gepubliceerd.

## Prestaties en optimalisatie

### Waarom rendert mijn presentatie traag?
Mogelijke oorzaken zijn:
- Grote afbeeldingen die gedecodeerd moeten worden  
- Complexe grafieken of animaties
- Veel slides in één bestand
- Beperkingen in het systeemgeheugen

Optimalisatiesuggesties:
1. Comprimeer foto's met hoge resolutie
2. Vereenvoudig complexe grafiekvisualisaties  
3. Splits grote presentaties op in kleinere decks
4. Sluit andere applicaties tijdens het bewerken/presenteren  

### Hoe ondersteunt OciDeck collaboratieve informatieomgevingen?
OciDeck ondersteunt collaboratieve informatieomgevingen via diverse mechanismen:
1. **Gedeelde standaarden**: Het gebruik van het Marp-Markdownformaat maakt samenwerking met andere programma's en teams mogelijk
2. **Integratie met versiebeheer**: Git-integratie maakt teamgebaseerd documentbeheer mogelijk
3. **Veilig delen**: Exportcontroles helpen beheersen wat er in samenwerkingssituaties wordt gedeeld
4. **Privacybeheersing**: Teamleden kunnen bepalen hoeveel gevoelige informatie voor anderen zichtbaar is
5. **Opensource**: Het programma zelf ondersteunt transparante samenwerking en gemeenschapsontwikkeling

### Hoe varieert de exportprestatie?
De exporttijd hangt af van:
- Aantal en complexiteit van de slides  
- Vereisten voor het renderen van grafieken
- Media-elementen in de presentatie
- Beschikbare systeembronnen

PDF/PPTX-exports zijn over het algemeen sneller dan HTML, maar alle formaten kennen een voorbewerkingsstap.

## Problemen oplossen

### Waarom kan ik een deck niet vanaf een URL importeren?
Veelvoorkomende redenen:
1. CORS-beperkingen op de bronserver (gebruik de fetch-proxy)
2. Ongeldige of ontoegankelijke URL  
3. Problemen met de netwerkverbinding
4. Beveiligingsinstellingen die de verbinding blokkeren

### Hoe los ik exportfouten op?
Stappen om het probleem op te lossen:
1. Controleer de TLP-classificatieniveaus en privacy-instellingen
2. Vereenvoudig complexe slides of grafieken vóór het exporteren
3. Controleer of er voldoende systeembronnen zijn (geheugen/CPU)
4. Probeer een ander exportformaat  

### Wat te doen als OciDeck crasht tijdens het bewerken?
1. Start de applicatie opnieuw op  
2. Controleer op beschadigde bestanden met herstelmomentopnamen
3. Exporteer je werk direct als dat mogelijk is
4. Meld problemen via de officiële kanalen met foutgegevens

In de browser zijn er geen herstelmomentopnamen — de app heeft nergens om ze
weg te schrijven — dus stap 2 is daar niet van toepassing en niet-opgeslagen werk is weg. De app zegt dat
bij je eerste bewerking, en de browser vraagt het voor je een tabblad sluit dat nog
niet-opgeslagen werk bevat. Sla vroeg op als je in een browsertab werkt.

## Configuratie en instellingen

### Hoe kies ik het cockpituiterlijk?

Open **Instellingen → Cockpit → Weergave**. **Authentieke cockpit** is de standaard;
**Klassiek** houdt de eerdere kaartachtige meters aan. Dit is één keuze voor de hele app,
dus elke cockpitslide volgt die — hij wordt niet in het deck opgeslagen. Het
cockpitkleurenschema onder de keuzelijst is een aparte keuze voor de hele app.

De slide-editor bepaalt het gedrag bij binnenkomst: **Animeren bij binnenkomst** schakelt
de opstartsequentie in, en de duur ervan kan het stijlprofiel erven of per slide worden
overschreven. Een cockpit accepteert maximaal zes instrumenten, gekozen uit
zeven typen. De volledige lijst en het verschil tussen presentator- en statische
exports staan in [Cockpitdashboards](USER_GUIDE.md#cockpit-dashboards).

### Hoe werkt Git-integratie?
OciDeck ondersteunt opslag in een Git-repository:
- Configureer het als een verbinding onder *Instellingen → Opslag*, naast mappen,
  WebDAV en S3 *(gecorrigeerd 21-07-2026; er is geen aparte "Git-repository"-
  tab — opslag is één lijst)*
- Sla decks op in externe repositories via REST-API of native Git
- Ondersteunt zowel publieke als private repositories  
- Biedt toegang tot de versiegeschiedenis
- Let op wat een commit meeneemt: de markdown, de gepoolde afbeeldingen en de gekoppelde
  grafiekgegevens. Video, audio, de tekeningen op je slides en de gebruikersnotities reizen
  **niet** op deze manier mee; OciDeck telt ze en vraagt het voordat het commit. Sla
  op naar een map of een `.ocideck`-pakket als je die wilt laten meekomen.

### Waar zijn de WebDAV-instellingen voor?

Met WebDAV kun je presentaties rechtstreeks op je eigen server opslaan. Nextcloud is
de meest voorkomende, maar elke WebDAV-server werkt:
1. Kies het servertype — *Nextcloud of ownCloud* (het DAV-pad wordt afgeleid) of
   *Andere WebDAV-server* (het pad in de server-URL is de WebDAV-root)
2. Configureer de server-URL, inloggegevens en een optionele submap in Instellingen
3. Open decks via "Openen vanaf…" en kies de server
4. Sla terug op met de gewone opslaan-knop; "Opslaan naar…" zet het ergens anders neer
5. Ondersteunt zowel het platte formaat (.md + assets) als de pakketformaten

### Hoe werkt S3-opslag?

Met S3 kun je decks in een bucket bewaren — AWS S3, of elke S3-compatibele dienst zoals
MinIO of een Europese aanbieder:

1. Voeg een S3-verbinding toe in Instellingen → Opslag
2. Vul het eindpunt, de bucket, de regio, de access key ID en de secret access key in.
   Het eindpunt is een vrij tekstveld in plaats van een lijst met AWS-regio's, omdat
   zelf-gehoste en niet-AWS-eindpunten het interessante geval zijn
3. Kies de adresseringsstijl: bucket in de hostnaam (AWS) of in het pad (de meeste
   zelf-gehoste eindpunten)
4. Openen en opslaan via "Openen vanaf…" en "Opslaan naar…"

Je secret access key gaat naar de OS-sleutelbos; het eindpunt, de bucket en de access
key ID zijn gewone instellingen. Een MinIO-box op je eigen LAN heeft het vinkje *vertrouwde
interne server* nodig, omdat privéadressen standaard worden geblokkeerd.

Eén verschil is het waard om te weten: S3 is objectopslag, geen bestandssysteem, dus het
heeft geen echte mappen. Een prefix gedraagt zich als een map, en bij het opsommen wordt een
scheidingsteken gebruikt zodat prefixen zich tonen alsof ze mappen zijn.

## Toekomstige functies en roadmap

### Wat staat er gepland voor toekomstige ontwikkeling?
Wat er gepland is, wordt in de issuetracker bepaald, in de openbaarheid. Er is geen
apart roadmapdocument, omdat een roadmap die niemand onderhoudt erger is dan
geen — deze sectie was daar zelf het bewijs van: hij vermeldde versleutelde pakketexport
als gepland tot maanden nadat die al was uitgebracht, en "aanvullende grafiek-
visualisaties" terwijl er al dertien grafiektypen in de app zaten.

Wat OciDeck nog *niet* doet, is opgeschreven, op één plek:
[KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).

*Gecorrigeerd 2026-07-22: dit antwoord noemde drie verouderde roadmapitems. De
eerdere correctie van 2026-07-18, over de reeds uitgebrachte versleutelde
pakketexport, is in deze notitie opgenomen.*

### Zijn er plannen voor mobiel?
Er is niets gepland. De ondersteunde doelen zijn macOS, Windows, Linux en de
browser: dat zijn de doelen met een `make build-*`-recept, de doelen die de CI-
workflow noemt, en de doelen waarop überhaupt iets wordt getest. De repository bevat wel
mappen `android/` en `ios/`, maar alleen omdat `flutter create` ze aanmaakt —
geen enkel builddoel wijst ernaar, er draait geen test, en het desktop-bestandsmodel
(assetmappen naast de geopende `.md`) past niet in een mobiele sandbox.

*(Gecorrigeerd 2026-07-22: dit antwoord zei "the team continues to evaluate mobile
platform support based on community feedback and requirements". Noch het team
noch het beschreven feedbackproces bestaat — twaalf regels verderop zegt dit
zelfde bestand dat er geen discussieforum, mailinglijst of chatkanaal is.)*

## Bijdragen en gemeenschap

### Hoe kan ik bijdragen aan de ontwikkeling van OciDeck?  
Bijdragen vanuit de gemeenschap zijn welkom via:
- Bugmeldingen en functieverzoeken via de issuetracker van het project (Forgejo)
- Codebijdragen volgens de projectrichtlijnen
- Documentatieverbeteringen 
- Het testen van nieuwe functies in ontwikkelbuilds

Er is geen discussieforum, mailinglijst of chatkanaal — de issuetracker
is het enige kanaal voor vragen en meldingen.

Voor **beveiligingsnieuws** is dat niet het hele antwoord, en enkel het bovenstaande zeggen was
misleidend: je zou geen tracker in de gaten hoeven houden om te vernemen dat een kwetsbaarheid
is verholpen. De forge serveert een releasesfeed waarop je je kunt abonneren, en
`SECURITY.md` legt uit wat die vandaag wel en niet bevat. Gecorrigeerd
2026-07-22.

### Waar vind ik meer informatie?
De documentatie in deze repository is alles: de map `docs/` en de
broncode zelf. Er is geen aparte documentatiesite, geen gemeenschapsforum,
en geen mailinglijst. Releasenotes staan in [`CHANGELOG.md`](../CHANGELOG.md).
*Gecorrigeerd 2026-07-28: hier stond "no release notes — nothing has been tagged as
a release yet" — verouderd sinds `0.1.0` op 2026-07-25.*

### Hoe past OciDeck in professioneel informatiebeheer?
OciDeck is ontworpen om professioneel informatiebeheer te ondersteunen door:
1. **Veilige documentatie**: Stelt professionals in staat presentaties te maken zonder zorgen over datalekken
2. **Ondersteuning bij naleving**: Ingebouwde classificatie- en exportcontroles helpen aan de beveiligingseisen van de organisatie te voldoen
3. **Samenwerkingshulpmiddelen**: Git-integratie ondersteunt teamgebaseerde workflows met behoud van privacybeheersing
4. **Informatiesoevereiniteit**: Professionals houden controle over de inhoud en metadata van hun presentaties
5. **Transparante werkwijze**: Het opensourcekarakter stelt organisaties in staat beveiligingspraktijken te verifiëren en naar behoefte aan te passen
