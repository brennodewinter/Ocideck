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
| §3 — regelmatig testen | `make check` (analyse, conventies, volledige suite, dekkingsvloer), `make sast`, `make check-secrets`, mutatietesten | — |
| §4 — gerepareerde kwetsbaarheden openbaar maken | CHANGELOG en de tracker zijn openbaar | Geen advisory-vorm; nooit nodig gehad |
| §5 — een beleid voor gecoördineerde openbaarmaking | `SECURITY.md`, meldadres `security@librekat.nl`, eigen termijnen gemeten door `tool/check_service_norms.dart` | — |
| §6 — informatie over kwetsbaarheden delen | Openbare tracker | — |
| §7 — veilige distributie van updates | Geen releases; de gebruiker bouwt uit de bron | Onderdeel van #520 |
| §8 — patches onverwijld verspreiden | Idem — een fix staat op `main` zodra hij gemerged is | Idem |

## Wat hieruit volgt

Drie richtingen, uit het gesprek waarin dit besluit viel. Ze gaan niet over
naleving maar over of het werk goed genoeg is.

1. **Doorlooptijd — hoe lang staan zaken open.** Voor beveiligingsmeldingen
   bestaat dit al (`tool/check_service_norms.dart`: eerste reactie 5 werkdagen,
   oordeel 10, oplossing 90). Voor gewone issues meet niets iets. Een issue die
   maanden stil ligt is geen beveiligingsprobleem maar wel een kwaliteitssignaal,
   en het is precies wat een buitenstaander als eerste ziet.
2. **Kwaliteitsslagen — is het goed genoeg.** De poorten meten of iets *werkt*.
   Ze meten niet of de dekking op de juiste plekken zit, of een test werkelijk
   iets bewijst, of de basislijnen krimpen in plaats van stil te blijven staan.
   Er zijn er nu zeven of acht; niets laat zien of ze de goede kant op bewegen.
3. **Documentatie — voldoende en duidelijk.** `docs_registration_test` bewaakt
   dát een document bereikbaar is, niet dát het klopt of te volgen valt. De
   d7b609bf-episode (gegenereerde gidsen die niets beschreven) laat zien dat dat
   verschil echt is.

Elk van de drie krijgt een eigen issue; de uitwerking hoort daar, niet hier.

## Wanneer dit besluit opnieuw op tafel moet

- Er komt geld aan OciDeck vast te zitten — betaalde inzet, gesponsorde
  ontwikkeling, dienstverlening eromheen.
- De software wordt aangeboden **als dienst** (een gehoste instantie voor
  anderen).
- Distributie loopt via een kanaal dat niet de eigen forge is, met binaries.
- De Commissie publiceert de aangekondigde leidraad over de reikwijdte voor
  opensourcesoftware.
- De statuten van de stichting wijzigen.

Bij elk van deze vijf is de vraag niet "geldt het nu wel", maar: **wat verandert
er feitelijk, en klopt de eerste alinea dan nog.**
