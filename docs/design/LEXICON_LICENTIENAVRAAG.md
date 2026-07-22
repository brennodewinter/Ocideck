# OciDeck — Licentienavraag voor drie lexiconbronnen

> **Status:** dossier; drie navragen die openstaan · **Status laatst herzien:** 22-07-2026 · **Uitgever:** Stichting LibreKAT · **Language:** Nederlands

Drie bronnen zouden het art. 9-lexicon van OciDeck fors verrijken, en van geen
van drieën is de licentie rond genoeg om te bundelen. Dit document bevat per
bron wat er precies aan de hand is, bij wie je moet zijn, en wat je moet vragen —
zodat het navragen niet opnieuw uitgezocht hoeft te worden.

**De regel waar dit allemaal aan hangt:** kosteloos is niet hetzelfde als
herdistribueerbaar. OciDeck is een publieke repo onder EUPL-1.2, en alles wat
meegebundeld wordt moet dáárin mogen zitten en dóór mogen worden gegeven. Op
precies dat onderscheid knapt SNOMED CT NL af, en het is de reden dat deze drie
wachten.

> **Ter vergelijking, wat wél doorging.** Orphanet is inmiddels gebundeld
> (62.490 aandoeningsnamen in negen talen). Dat kon omdat de licentie niet
> afgeleid hoefde te worden: **CC-BY-4.0 staat in het XML-bestand zelf**, onder
> `<Availability><Licence><ShortIdentifier>`. Dat is het niveau van zekerheid
> waar je bij de drie hieronder naartoe wilt. De generator weigert zelfs te
> bouwen als de bron ooit iets anders declareert.

---

## 1. Homosaurus — IHLIA (seksuele geaardheid)

**Waarom interessant.** Via het RCE/NDE-endpoint 5.811 SKOS-concepten, állemaal
met een Nederlandse `prefLabel`, plus 3.187 Nederlandse `altLabel`s, en actief
onderhouden. Veruit de beste bron voor `special.sexlife` — een categorie waar het
huidige lexicon zes termen heeft.

**Het probleem: de licentie spreekt zichzelf tegen.**

| Vindplaats | Wat er staat |
| --- | --- |
| [homosaurus.org/about](https://homosaurus.org/about) | **CC BY-NC-ND 4.0** |
| IHLIA's eigen dataset-metadata, live opgevraagd | `dcterms:license → CC BY 4.0` |

Dat verschil is niet academisch. **BY-NC-ND is dodelijk voor ons**: `NC` sluit
commercieel gebruik uit (en OciDeck kan door wie dan ook zakelijk gebruikt
worden), en `ND` verbiedt afgeleide werken — terwijl een lexicon per definitie
een bewerking is: wij filteren, normaliseren en hangen er matchmodi aan. **BY 4.0
zou wél kunnen**, met naamsvermelding.

De plausibele verklaring is dat de internationale redactieraad BY-NC-ND hanteert
en IHLIA zijn eigen Nederlandse dataset onder BY 4.0 publiceert. Maar dat is een
gok, en op een gok mag dit niet mee.

**Bij wie.** IHLIA LGBTI Heritage, via de contactgegevens op hun eigen site.

> Bewust geen e-mailadres in dit document. Toen dat er een keer wél in stond,
> sloeg de vals-positievencorpustest erop aan: de co-occurrence-escalator telt
> een e-mailadres als "identificeert een persoon", en tilde daarmee élk artikel
> 9-trefwoord in dat document naar `zeker`. In een tekst over artikel 9 staan die
> woorden in elke alinea. De controle ving dus haar eigen documentatie, precies
> zoals bedoeld — en de les is blijven staan.

**Wat je wilt vragen.**

1. Welke licentie geldt voor de **Nederlandse Homosaurus-dataset** zoals IHLIA
   die publiceert — de `dcterms:license` in de metadata (CC BY 4.0), of de
   BY-NC-ND 4.0 van homosaurus.org?
2. Als dat CC BY 4.0 is: mag die dataset **herdistribueerd** worden als
   onderdeel van een open source-applicatie (EUPL-1.2, publieke repo), in
   **bewerkte vorm** — gefilterd op bruikbare termen, genormaliseerd naar kleine
   letters, zonder de begripsstructuur?
3. Welke **naamsvermelding** wilt u precies zien, en waar? (Wij zetten hem in het
   databestand zelf én in `docs/LICENSE_COMPLIANCE.md`.)

**Wat het antwoord betekent.** BY 4.0 → bundelen kan. BY-NC-ND → niet bundelen,
punt; dan blijft `special.sexlife` bij de handgeschreven termen.

---

## 2. Religietaxonomieën — IISG (religie en levensovertuiging)

**Waarom interessant.** Twee datasets: een religietaxonomie van 288 SKOS-concepten
(schoon en tweetalig) en een denominatielijst van 3.219 concepten, inclusief
historische spellingsvarianten. Dat laatste is precies wat een lexicon wil, want
oude spellingen komen in archief- en dossiermateriaal voor.

**Het probleem: er staat helemaal geen licentie bij.** Beide datasets declareren
er geen. Geen tegenstrijdigheid dus, maar een leegte — en een leegte is geen
toestemming. Zonder verklaring is het standaard auteursrecht, en dan mag er niets.

**Let op bij gebruik, ná toestemming.** De denominatielijst is vervuild met
transcriptie-afval (`!geen<`, kale interpunctie). Filter op minstens drie letters
voordat er iets in het lexicon belandt.

**Bij wie.** Internationaal Instituut voor Sociale Geschiedenis (IISG),
Amsterdam.

**Wat je wilt vragen.**

1. Onder welke licentie publiceert het IISG de **religietaxonomie** en de
   **denominatielijst**? (Er staat op dit moment geen licentieverklaring bij de
   datasets.)
2. Mogen die als onderdeel van een open source-applicatie (EUPL-1.2, publieke
   repo) **herdistribueerd** worden, in **bewerkte vorm** — gefilterd en
   genormaliseerd tot een trefwoordenlijst?
3. Welke **naamsvermelding** wilt u daarbij?

**Wat het antwoord betekent.** Een expliciete open licentie (CC BY, CC0, of een
schriftelijke toestemming) → bundelen kan. Geen antwoord of geen toestemming →
niet bundelen.

---

## 3. Thesaurus Zorg en Welzijn — Nictiz (gezondheid)

**Waarom interessant.** Ongeveer **50.000 Nederlandse termen** en daarmee veruit
het rijkste NL-corpus voor de gezondheidscategorie, in SKOS-RDF. Dat is een
andere orde dan wat we nu hebben: Orphanet dekt zeldzame aandoeningen, deze
thesaurus dekt de gewone zorg- en welzijnstaal.

**Het probleem: "kosteloos" is geen licentie.** Sinds 1 januari 2023 wordt de
thesaurus beheerd door Nictiz en kosteloos beschikbaar gesteld. Maar de tekst van
de bilaterale overeenkomst is nergens gepubliceerd, en dus is er geen
voorwaardentekst die wij kunnen lezen en naleven.

Dat is exact het patroon waar **SNOMED CT NL** op afknapt: gratis, maar
sublicentiehouders moeten geadministreerd worden en aan Nictiz worden overlegd —
onverenigbaar met een publieke repo waar iedereen anoniem kan klonen. Als de
Thesaurus Zorg en Welzijn dezelfde constructie kent, valt hij om dezelfde reden af.
Daarom moet de vraag **expliciet over herdistributie** gaan en niet over gebruik.

**Bij wie.** De servicedesk van Nictiz.

**Wat je wilt vragen.**

1. Onder welke **licentie of voorwaarden** wordt de Thesaurus Zorg en Welzijn
   sinds het beheer door Nictiz beschikbaar gesteld? Is die tekst ergens te
   raadplegen?
2. Is **herdistributie** toegestaan — dus niet alleen gebruik, maar het meeleveren
   van (een deel van) de termen als databestand in een open source-applicatie
   onder EUPL-1.2, in een publieke repository die iedereen zonder registratie kan
   klonen?
3. Geldt er een **administratieplicht voor sublicentiehouders**, zoals bij
   SNOMED CT NL? (Zo ja, dan kunnen wij de thesaurus niet bundelen, en horen we
   dat liever nu dan achteraf.)
4. Welke **naamsvermelding** hoort erbij?

**Wat het antwoord betekent.** Een publiceerbare open licentie zonder
registratieplicht → bundelen kan, en dat zou de grootste enkele verbetering van
het Nederlandse lexicon zijn. Registratieplicht of geen publiceerbare tekst →
niet bundelen.

---

## Wat er gebeurt als een antwoord binnenkomt

De machinerie ligt klaar; het is een datawijziging, geen codewijziging.

1. Zet de bron in `tool/build_privacy_lexicon.dart` naast Orphanet, met dezelfde
   licentiepoort: **weigeren te bouwen als de bron iets anders declareert dan
   afgesproken.**
2. Voeg de attributie toe aan het gegenereerde asset én aan
   `docs/LICENSE_COMPLIANCE.md`.
3. Zet de bron in `lib/services/reference_standards.dart` met `advisory: true` —
   een lexicon hoort in `make catalogs-outdated` en niet in de blokkerende poort
   (zie `docs/CHECKS.md`).
4. **Lees de termdiff en draai `privacy_false_positive_corpus_test`.** Bij een
   lexicon vuurt elke term; dit is de stap die niet overgeslagen mag worden.

Blijft een antwoord uit, dan is dat ook een uitkomst: de taaldekkingsmeter in het
kwaliteitspaneel meldt eerlijk waar het lexicon dun is, dus het gat is zichtbaar
in plaats van verborgen.
