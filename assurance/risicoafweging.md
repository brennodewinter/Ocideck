# Risicoafweging

> **Status:** eerste opzet 2026-07-22 · Stichting LibreKAT · intern werkdocument
>
> Geen conformiteitsclaim en geen auditrapport. Zie [`README.md`](README.md).

## Waarom dit een ander document is dan het dreigingsmodel

`docs/SECURITY_DESIGN.md` heeft een *threat model*: wie valt aan, en langs welk
pad. Dat is een goede vraag en niet deze vraag.

Een risicoafweging vraagt iets anders: **wat kan er misgaan, hoe erg is dat voor
wie het overkomt, en wat hebben we besloten te doen — inclusief wat we bewust
hebben aanvaard.** Dat laatste is de reden dat dit bestaat. Er stonden al drie
aanvaarde afwijkingen in dit dossier (S3, loopback, PBKDF2) zonder dat er een
kader was waarin ze thuishoorden, en een aanvaard risico dat nergens als
aanvaard staat opgeschreven, is over een jaar niet te onderscheiden van een
vergeten risico.

## Wat dit product bijzonder maakt voor de afweging

OciDeck is een editor voor pentestrapporten. Dat verschuift de weegschaal op één
punt scherp: **de gevoeligste gegevens in het product zijn niet van de
gebruiker.** In een deck staan bevindingen over andermans systemen, namen van
medewerkers, schermafdrukken met echte gegevens erop. De persoon die het meeste
risico loopt bij een fout, is niet degene die de knop indrukt.

Dat is de reden dat de privacyprojectie een compileertijdgrens is en geen
instelling, en dat een overgeslagen redactie zwaarder weegt dan een
crash.

## De weging

Kans en gevolg zijn hier grof — laag/midden/hoog — en dat is opzet. Preciezere
getallen zouden nauwkeurigheid suggereren die er niet is; wat telt is de
volgorde, niet de decimaal.

| # | Wat er mis kan gaan | Gevolg | Kans | Wat we doen |
|---|---|---|---|---|
| R1 | Ongeredigeerde persoonsgegevens komen in een export of op het publieksscherm | **Hoog** — treft iemand die er niet om vroeg, en is niet terug te draaien | Laag | `AudienceDeck` is de enige weg naar een ontvangend oppervlak, en `check_audience_boundary` dwingt af dat elk uitvoerkanaal geclassificeerd is |
| R2 | Een deck van een ander opent en leest bestanden buiten het project | Hoog | Laag | Padinsluiting (`resolveSlideAssetPath`), begrensde leesbewerkingen, geen padtraversal in pakketten |
| R3 | Het product gaat het netwerk op zonder dat de gebruiker het aanwees | Hoog — het botst frontaal met de belofte | Laag | NetGuard met socket-pinning, `network_sink_guard_test` als poort over élke uitgang, inclusief subproces en WebView |
| R4 | Een kwaadaardige afbeelding sloopt de native decoder | Midden — procesverlies, geen gegevensverlies | Laag | Poort op omvang en afmetingen vóór de decode; **aanvaard**: een verminkte JPEG bereikt de C++-decoder, en een crash daarbinnen neemt het proces mee (§6.1) |
| R5 | Werk van de gebruiker raakt kwijt bij opslaan | Midden — zijn eigen werk, meestal te herstellen | Midden | Atomair schrijven overal; wat niet is ingelezen wordt niet overschreven; crashherstel |
| R6 | Een geheim lekt via een logregel of een subproces | Hoog | Laag | `log_no_content_test` verbiedt inhoud in logregels; `git` draait zonder geërfde omgeving zodat een `GIT_TRACE_*` het token niet wegschrijft |
| R7 | Een afhankelijkheid draagt een bekende kwetsbaarheid | Midden | Midden | SBOM met verouderingspoort, `make deps-check` over de gebundelde JS; **aanvaard**: de Dart-graaf wordt alleen adviserend gescand, want pub-advisorydekking is dun |
| R8 | Een verzegeld rapport wordt gewijzigd zonder dat het opvalt | Hoog voor de bewijswaarde | Laag | SHA-512-zegel over de canonieke inhoud; **aanvaard**: dit is bewijs van wijziging en niet van herkomst — er is geen echte ondertekening, en dat besluit staat in SECURITY_DESIGN §12 |
| R9 | Het project valt stil en niemand merkt het | Midden — maar het raakt alles hierboven | **Hoog** | Dit is het grootste risico en het minst technische: één beheerder, zelf mergen. Zie `CONTRIBUTING.md`. Wat eraan gedaan is: alles wat te automatiseren valt zit in `make check`, en het einde-van-leven-beleid staat in `SECURITY.md` |
| R10 | Gegevens blijven op schijf achter na verwijderen | Midden | Midden | `DiskTraces` ruimt op één plek op; **aanvaard**: unlink, geen overschrijving — op moderne opslag is overschrijven geen garantie, en de suggestie ervan zou schadelijker zijn dan de eerlijke zin |

## De aanvaarde risico's, bij elkaar

Vijf, en ze staan hier bij elkaar omdat dat de enige manier is om ze samen te
kunnen wegen: **R4** (de native decoder), **R7** (de Dart-graaf),
**R8** (zegel zonder ondertekening), **R10** (geen overschrijving), plus de drie
die al in [`ASVS-5.0.0-afwijkingen.md`](ASVS-5.0.0-afwijkingen.md) stonden
(S3, loopback, PBKDF2).

Wat ze gemeen hebben: geen ervan is aanvaard omdat het lastig was, en bij elk
staat opgeschreven waaronder het besluit terug op tafel komt. Dat onderscheid —
aanvaard versus vergeten — is het hele punt van dit document.

## Een tweede lens: outcome in plaats van proces

De ORC WG bracht op zijn werkbijeenkomst van oktober 2025 het **Eclipse Trustable
Software Framework** in als tegenhanger van een proceschecklist. Het vraagt niet
"welke stappen heb je gevolgd" maar "waarom zou ik dit vertrouwen", langs vijf
lijnen: herkomst, constructie, bijwerkbaarheid, vertrouwen dat het doet wat het
zegt, en een menselijke inschatting van mogelijke schade.

Op de eerste drie doet dit project het redelijk: de herkomst is een openbare
repo met SBOM, de constructie is een poort die groen moet zijn, de
bijwerkbaarheid is `git pull` en herbouwen — mager, maar eerlijk opgeschreven.

De laatste twee zijn de vragen die onze poorten **niet** stellen, en het is de
moeite ze hardop te noemen:

- *Doet het wat het zegt?* De tests bewijzen dat de code doet wat de tests
  zeggen. Of dat hetzelfde is als wat de interface belooft, is precies waarvoor
  `docs_claims_match_code_test` bestaat — en die dekt de mechanische helft. De
  menselijke helft is niet geautomatiseerd, met opzet: een test die doet alsof,
  verplaatst het probleem.
- *Welke schade kan dit aanrichten?* Dit is gereedschap dat gebruikt wordt op
  systemen van anderen, en het verzamelt bevindingen daarover in één bestand.
  Het ergste geval is niet dat OciDeck omvalt, maar dat een compleet
  pentestrapport bij de verkeerde persoon terechtkomt — en dat is een gevolg van
  hoe makkelijk het is om een deck te delen, wat tegelijk de bedoeling van het
  product is. Daar zit geen technische oplossing op. Wat er wél is: de
  privacyprojectie, de TLP-classificatie en de pakketversleuteling — drie
  hulpmiddelen die het makkelijker maken om het goede te doen, en géén van drie
  een garantie.

Er wordt hier niets van dat framework overgenomen als norm. Het staat er omdat
de twee vragen die het stelt en wij niet, het opschrijven waard zijn.

## Wanneer dit document herzien wordt

- Bij een nieuw uitvoerkanaal of een nieuwe netwerkuitgang — dan verschuift R1
  of R3.
- Bij een afhankelijkheid erbij die niet-geheugenveilig is — dan verschuift R4.
- Bij een tweede actieve beheerder — dan zakt R9, en dat is de enige regel in
  deze tabel die door mensen verandert in plaats van door code.
- Bij releases met artefacten — dan komt er een risico bij dat er nu niet is:
  distributie-integriteit.
