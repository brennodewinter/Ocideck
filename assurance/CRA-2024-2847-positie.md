# Cyberweerbaarheidsverordening — positie en leidraad

> **Status:** vastgesteld 2026-07-22 · Stichting LibreKAT · intern werkdocument
>
> Geen conformiteitsclaim en geen auditrapport. Zie [`README.md`](README.md).

## Het besluit

**De verordening ((EU) 2024/2847) legt OciDeck geen verplichtingen op.** De
software is door de stichting als opensourceproject gemaakt, is vrij
beschikbaar, en wordt niet als dienst aangeboden. Daarmee is er geen sprake van
aanbieden op de markt in de zin van de verordening, en is de stichting geen
fabrikant.

**En toch houden we hem aan, als leidraad.** Niet omdat het moet, maar omdat de
verordening redelijk goed opschrijft hoe je software fatsoenlijk onderhoudt:
weten wat je uitlevert, kwetsbaarheden zonder uitstel afhandelen, en een melder
een begaanbare weg geven. Dat zijn geen nalevingsvinkjes maar
kwaliteitseigenschappen.

Deze twee zinnen horen bij elkaar. De eerste voorkomt dat we een plicht op ons
nemen die niet bestaat; de tweede voorkomt dat "het hoeft niet" een reden wordt
om het niet te doen.

## Wat dat betekent voor wat we opschrijven

In `docs/` staat daarom **"als beschreven in de CRA"**, nooit "zoals vereist
door". Het verschil is niet cosmetisch: de tweede formulering identificeert het
project met een fabrikantsplicht, en zo'n zin wordt teruggeciteerd in een
vragenlijst of in correspondentie met een toezichthouder. Zie #532.

## De leidraad, en waar we staan

Gemeten tegen Annex I, deel II — de eisen over kwetsbaarheidsafhandeling, het
deel dat voor een project als dit inhoudelijk iets zegt.

| Wat de verordening beschrijft | Waar we staan | Open |
|---|---|---|
| §1 — componenten kennen en documenteren (SBOM) | `sbom/` in CycloneDX 1.6 + SPDX 2.3, álle componenten; `make sbom-verify` als verouderingspoort | Diepte: de graaf is één laag, en `supplier` ontbreekt (#517) |
| §2 — kwetsbaarheden zonder uitstel afhandelen | `make deps-check` (OSV) over de gebundelde JS; SBOM voedt externe scanners | Geen automatische controle op de Dart-graaf zelf (#517) |
| §3 — regelmatig testen | `make check` (analyse, conventies, volledige suite, dekkingsvloer), `make sast`, `make check-secrets` | Mutatietesten zijn handwerk en smal: één operator (`startsWith`/`endsWith`) over de Markdown-parsers — 7 vaste doelen van de 96 bestanden in `lib/` waar zo'n predicaat in staat (309 in totaal). Er is geen conditie-, grenswaarde- of retourwaardemutant en geen vastgelegde score |
| §4 — gerepareerde kwetsbaarheden openbaar maken | CHANGELOG en de tracker zijn openbaar | Geen advisory-vorm; nooit nodig gehad |
| §5 — een beleid voor gecoördineerde openbaarmaking | `SECURITY.md`, meldadres `security@librekat.nl`, eigen termijnen gemeten door `tool/check_service_norms.dart` | — |
| §6 — informatie over kwetsbaarheden delen | Openbare tracker | — |
| §7 — veilige distributie van updates | Geen releases; de gebruiker bouwt uit de bron | Onderdeel van #520 |
| §8 — patches onverwijld verspreiden | Idem — een fix staat op `main` zodra hij gemerged is | Idem |

## De leidraad, deel I — de producteisen

*Toegevoegd 2026-07-22.* De tabel hierboven meet tegen Annex I **deel II**, en
dat was een keuze: dat deel zegt inhoudelijk iets over kwetsbaarhedenbeheer. Het
gevolg was wel dat deel I — de eisen aan het product zelf — nergens stond,
terwijl dit project daar juist sterk is. De ORC WG-mapping merkt datzelfde
patroon breed op: bij een lichte attestatie staat élke regel van deel I als *not
addressed*.

Dus staat hij hier. Zelfde vorm, zelfde voorbehoud: leidraad, geen
conformiteitsclaim, geen audit.

| Wat de verordening beschrijft | Waar we staan | Open |
|---|---|---|
| Veilig bij oplevering, naar risico | Lokaal-eerst; netwerk staat uit tenzij aangewezen (NetGuard, SECURITY_DESIGN §3) | De risicoafweging zelf stond nergens — zie hieronder |
| Geen bekende exploiteerbare kwetsbaarheden | `make deps-check` (OSV) over de gebundelde JS, `make sast`, `make check-secrets` | De Dart-graaf alleen adviserend (#517) |
| Veilige standaardinstelling | Uitgaand verkeer staat standaard uit; de beveiligingsmodule is een schakelaar over ingebakken catalogi, zonder netwerkuitgang | — |
| Bescherming tegen ongeoorloofde toegang | Sleutels in de sleutelbos van het besturingssysteem, nooit in voorkeuren (§13); pakketversleuteling met WinZip-AES | PBKDF2-SHA1 op 1000 iteraties is een vastgelegde afwijking (ASVS-dossier) |
| Vertrouwelijkheid van gegevens | Geen backend, geen telemetrie; wat de deur uit gaat staat per adres in `PRIVACY.md` | — |
| Integriteit van gegevens en commando's | Zegel (SHA-512) over de canonieke inhoud, met wijzigingsdetectie (§9); atomair schrijven overal | Het zegel is bewijs van wijziging, niet van herkomst — zie §12 |
| Gegevensminimalisatie | OciWacht spoort persoonsgegevens op en toont de gevonden waarde nooit (§8); de projectiegrens is compileertijd afgedwongen | — |
| Beschikbaarheid van essentiële functies | Alles werkt offline; er is geen dienst die uit kan vallen | — |
| Beperken van schade aan andere systemen | Geen serverdeel, geen luisterende poort | — |
| Aanvalsoppervlak beperken | Webbundel gehard (§1), padinsluiting (§4), HTML-exportopschoning (§5), AI-uitgang beheerst (§7) | Eén niet-geheugenveilige afhankelijkheid op het beeldpad (§6.1) |
| Beperken van de gevolgen van een incident | Begrensde leesbewerkingen, fail-closed poorten, subproces zonder geërfde omgeving (§10.2) | — |
| Vastleggen van beveiligingsrelevante activiteit | Wat er gelogd wordt staat in §14, inclusief wat er bewust níét in gaat | Geen auditspoor als voorziening; dat past niet bij een lokale editor |
| Veilig verwijderen van gegevens | `DiskTraces` verzamelt op één plek wat er van OciDeck op schijf achterblijft en ruimt het op; `chmod 700` op de datamappen (Linux) | **Unlink, geen overschrijving.** Op een SSD met wear levelling is overschrijven ook geen garantie. Dit is de zwakste regel, en hij hoort zo gelezen te worden |

Twee dingen die deze tabel niet doet. Hij vinkt niets af — de rechterkolom is
even belangrijk als de middelste. En hij vervangt de risicoafweging niet: die is
een ánder artefact, en het feit dat hij ontbrak was de echte bevinding achter dit
punt.

## Wat hieruit volgt

Drie richtingen, uit het gesprek waarin dit besluit viel. Ze gaan niet over
naleving maar over of het werk goed genoeg is.

1. **Doorlooptijd — hoe lang staan zaken open.** Voor beveiligingsmeldingen
   bestaat dit al (`tool/check_service_norms.dart`: eerste reactie 5 werkdagen,
   oordeel 10, oplossing 90). Voor gewone issues meet niets iets. Een issue die
   maanden stil ligt is geen beveiligingsprobleem maar wel een kwaliteitssignaal,
   en het is precies wat een buitenstaander als eerste ziet.
   *Uitgevoerd (#537):* `tool/check_issue_turnaround.dart` (`make doorlooptijd`)
   meet leeftijd, tijd tot eerste reactie, het aantal open issues zonder énige
   reactie, en stilstand op `triage`. Adviserend, en dat is er de standaard:
   voor gewone issues is bewust géén termijn afgesproken — eerst een basislijn,
   dan pas het gesprek over een norm.
2. **Kwaliteitsslagen — is het goed genoeg.** De poorten meten of iets *werkt*.
   Ze meten niet of de dekking op de juiste plekken zit, of een test werkelijk
   iets bewijst, of de basislijnen krimpen in plaats van stil te blijven staan.
   Er zijn er nu zeven of acht; niets laat zien of ze de goede kant op bewegen.
   *Deels uitgevoerd (#538):* `tool/check_ratchet_trend.dart` (`make ratchets`)
   zet elke basislijn naast haar waarde op een ijkpunt, noemt de langst staande
   basislijnregels en splitst de dekking uit per map. Adviserend, om dezelfde
   reden: stilstand tot een rode bouw maken straft een rustige maand. Wat
   hiermee níét beantwoord is, blijft staan: of een test werkelijk iets bewijst
   (`make mutate`) en het maandelijkse beeld op de wiki.
3. **Documentatie — voldoende en duidelijk.** `docs_registration_test` bewaakt
   dát een document bereikbaar is, niet dát het klopt of te volgen valt. De
   d7b609bf-episode (gegenereerde gidsen die niets beschreven) laat zien dat dat
   verschil echt is.
   *Deels uitgevoerd (#539):* `test/docs_claims_match_code_test.dart` houdt de
   mechanische helft tegen de code aan — de ratchetwaarden in `CHECKS.md`, de
   dekkingsvloeren en de taaltellingen. De menselijke helft (valt het te volgen)
   is bewust niet geautomatiseerd: een test die doet alsof, verplaatst het
   probleem alleen.

Elk van de drie krijgt een eigen issue; de uitwerking hoort daar, niet hier.

## Is de stichting een rentmeester (artikel 24)?

*Toegevoegd 2026-07-22.* Het besluit hierboven beslist één rol goed — geen
fabrikant — en zweeg over de andere rol die de verordening kent. Die stilte was
dragend geworden: een vrijwillige attestatie (#549) moet in AU.01 zeggen wát de
uitgevende partij is, en "een stichting, maar geen rentmeester" is een bewering
en geen leeg vakje.

**De definitie.** Artikel 3(14) omschrijft een rentmeester als een rechtspersoon,
niet zijnde een fabrikant, die tot doel heeft om stelselmatig en duurzaam
ondersteuning te bieden aan de ontwikkeling van bepaalde producten met digitale
elementen die kwalificeren als vrije en opensourcesoftware **en bestemd zijn voor
commerciële activiteiten**, en die de levensvatbaarheid van die producten
waarborgt.

**Wat pleit vóór.** Overweging 19 noemt uitdrukkelijk "certain foundations" en de
Commissie noemde op FOSDEM 2024 als eerste voorbeeld: stichtingen die een
specifiek opensourceproject ondersteunen. Dat is letterlijk wat Stichting
LibreKAT met OciDeck doet. Dat het geld noch verkoop betreft, sluit de rol niet
uit — de rentmeester ís juist de categorie voor wie niet monetiseert.

**Wat de doorslag geeft.** De zinsnede "bestemd voor commerciële activiteiten"
gaat over de *aanbodkant*, niet over wie het gebruikt. Overweging 15 beperkt de
verordening tot producten die worden geleverd in het kader van een commerciële
activiteit, en overweging 18 zegt dat het aanbieden van vrije en
opensourcesoftware die door de fabrikant niet wordt gemonetiseerd, niet als
commerciële activiteit geldt. De ORC WG werkt dat expliciet uit: een project kan
miljoenen gebruikers hebben, ook in ondernemingen en vitale infrastructuur,
zonder daardoor onder de verordening te vallen, zolang er niet gemonetiseerd
wordt.

Daarmee valt het argument weg waarop deze vraag gesteld was — OciDeck richt zich
op pentesters en dat is commercieel werk. Dat maakt het *gebruik* commercieel,
niet de *levering*. De stichting monetiseert niet, in geen van de vormen die de
verordening als zodanig aanmerkt.

**Het oordeel: waarschijnlijk geen rentmeester — en dat blijft een oordeel.**
Niet omdat de redenering wankel is, maar omdat de bron dat zelf zegt: de
FAQ-ingang over de reikwijdte voor rechtspersonen (stichtingen, verenigingen)
staat open in afwachting van verduidelijking door de Commissie, en de
whitepaper over rentmeesters onthoudt zich uitdrukkelijk van een oordeel over
wíé rentmeester is. Dat is precies onze vraag. Wie hier een stellig ja of nee
neerzet, doet alsof hij meer weet dan de werkgroep die eraan rekent.

**Wat er verandert als het kantelt.** De verplichtingen van artikel 24 zijn een
beveiligingsbeleid, een beleid voor kwetsbaarhedenbeheer, medewerking aan
markttoezicht, en melding aan het bevoegde CSIRT en ENISA. De eerste drie hebben
we al: `SECURITY.md`, de termijnen die `tool/check_service_norms.dart` meet, en
een openbare tracker.

Het vierde bestaat niet. Er is geen route naar het CSIRT of ENISA, en er is niet
opgeschreven welk CSIRT dat zou zijn. Voor Nederland is dat het CSIRT dat onder
NIS2 als coördinator is aangewezen. Dat is de enige echte leemte, en hij is
klein: het is een adres en een afspraak, geen bouwwerk. Hij hoort er te staan
vóórdat hij nodig is, want een meldplicht die pas wordt uitgezocht op het moment
dat er iets actief misbruikt wordt, is te laat.

**Voor AU.01 betekent dit:** de attestatie noemt Stichting LibreKAT als
uitgevende rechtspersoon en beschrijft de relatie tot het project, zonder de term
rentmeester te claimen en zonder hem te ontkennen. De ORC WG's eigen voorstel
laat die ruimte: het beschrijft de niet-gerentmeesterde projecten als het lastige
geval, niet als een ongeldig geval.

## Wanneer dit besluit opnieuw op tafel moet

- Er komt geld aan OciDeck vast te zitten — betaalde inzet, gesponsorde
  ontwikkeling, dienstverlening eromheen.
- De software wordt aangeboden **als dienst** (een gehoste instantie voor
  anderen).
- Distributie loopt via een kanaal dat niet de eigen forge is, met binaries.
- De Commissie publiceert de aangekondigde leidraad over de reikwijdte voor
  opensourcesoftware.
- De statuten van de stichting wijzigen.
- **De Commissie of de ORC WG verduidelijkt wanneer een stichting rentmeester
  is.** Die ingang staat vandaag open in afwachting daarvan; zie de paragraaf
  hierboven.

Bij elk van deze zes is de vraag niet "geldt het nu wel", maar: **wat verandert
er feitelijk, en klopt de eerste alinea dan nog.**
