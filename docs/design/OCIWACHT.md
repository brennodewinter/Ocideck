# OciDeck — OciWacht (ontwerp)

Detectie van privacygevoelige informatie in slides, met per-slide afhandeling:
accepteren, waarschuwen met een shield-badge, of redigeren op scherm en in export.

## Status

| Onderdeel | Stand |
| --- | --- |
| §6 De projectiegrens (`AudienceDeck`, afgedwongen door de conventiecheck) | **geleverd** |
| §6.4 Handmatige redactie `[[…]]` | **geleverd** |
| §3 Scanner: checksums, nepwaardelijst, contextpoorten | **geleverd** |
| §3-A NL + vijftien Europese landpakketten (BE/DE/FR/ES/PT/PL/IT/HR/BG/RO/SE/FI/EE/GB) | **geleverd** |
| §3-C/D Financieel en contact (IBAN, e-mail) | **geleverd** |
| §3-F Secrets-familie (leverancierstokens, PEM, JWT, connection strings, wachtwoorden) | **geleverd** |
| §3-G Bijzondere categorieën + co-occurrence-escalator | **geleverd** |
| §4 Standen: accept / shield / redact, per slide en per deck | **geleverd** |
| §4.5 Export-gate: uit / waarschuwen / blokkeren | **geleverd** |
| §6.6 Redactiemanifest met gesalte commitments + `IntegrityStatus.redactedDerivative` | **geleverd** |
| §7 Per-regel uitschakelen (met de drie art. 9-categorieën standaard uit) | **geleverd** |
| §3-I Structurele regels (gebruikerspaden, URL-tokens, share-links, data-URI's) | **geleverd** |
| §5.4 De eigen-identiteitslijst | **geleverd** |
| §4.0 Exportprofielen (volledig / geredigeerd) | **geleverd** |
| §3-H Massa-persoonsgegevens (tabelkolommen, herhaalde treffers) | **geleverd** |
| §3-D Adres, NL-postcode en gelabelde persoonsnaam (postcode + huisnummer escaleert via nabijheid) | **geleverd** |
| §13.1 Matcher met woordgrenzen + `PrivacyTermRole` (aanwijzing versus gegeven) | **geleverd** |
| §13.5 Beeldcontrole: herkenbare gezichten op afbeeldingen (YuNet, lokaal) | **geleverd** |
| §3-B `doc.mrz`: machine-readable zone (TD1/TD2/TD3) | **geleverd** |
| §3-E Digitale identificatoren (IP, MAC, IMEI, ICCID, IMSI, handle, device-ID) | **geleverd** |
| §3-D `contact.birthdate` + `contact.geo` | **geleverd** |
| §3-D kenteken (`nl.plate`) + buitenlandse postcodes (`<land>.postcode`) | **geleverd** |
| §13.2 Persoonskoppelingspoort (naam als koppeling, mededeling als bereik) | **geleverd** |
| §13.2 Lexiconmodel als data (`role`/`match`/`weight`/`lang`) | **geleverd** |
| §3-G `special.icd10` + `special.atc` (notatie met contextpoort) | **geleverd** |
| §13.6 fase 14 Rolonderscheid verdachte/aangever/getuige (ConText, drieweg) | **geleverd** |
| §13.3 Taaldekking zichtbaar in het paneel | **geleverd** |
| §5.7/§7 Regiopakketten werkend (instelling + poort) | **geleverd** |
| §13.3 Gebundeld gezondheidslexicon (Orphanet, 62.490 namen, 9 talen) | **geleverd** |
| §13.3 EuroVoc voor religie/politiek/vakbond/etniciteit (27 talen) | **geleverd** |
| §14 Onderzoeksdossier DLP-technieken (annex, geen ontwerp) | naslag |

De genomen beslissingen staan in §11; die zijn niet meer open.

---

## 1. Uitgangspunten

1. **De bron is heilig.** De `.md` op schijf verandert nooit door een privacybeslissing. Dit is
   een harde invariant en krijgt een eigen test.
1b. **Niet beschikbaar is niet beschikbaar.** Redactie is géén cosmetische laag over de
   gegevens heen. Wat geredigeerd is, mag een ontvangend oppervlak niet *bereiken* — niet als
   tekst onder een zwarte rechthoek, niet in de semantics-tree, niet in XML, niet in metadata,
   niet in een klembordbuffer, niet in een API-payload. Dit is architectuur, geen detail: zie §6.
2. **Detectie is geen oordeel.** De scanner meldt; de auteur beslist. Een politiebriefing
   bevat per definitie persoonsgegevens en een pentestrapport bevat per definitie buitgemaakte
   credentials — de tool mag daar niet tegen vechten, maar moet wél kunnen laten zien dát het
   erin zit, en de ontvanger kunnen waarschuwen.
2b. **Redactie hoort bij de ontvanger, niet bij de slide.** Dezelfde bron gaat volledig naar de
   opdrachtgever (anders kan die de bevinding niet natrekken) en geredigeerd naar de brede kring.
   Eén bron, meerdere versies, per doelgroep — en die versies moeten aantoonbaar bij elkaar horen
   (§4.0, §6.6).
3. **Vals-positieven zijn duurder dan vals-negatieven.** Een scanner die bij elk
   ordernummer "BSN!" roept, wordt binnen een week uitgezet, en dan detecteert hij niets
   meer. Het FP-budget is daarom een expliciet ontwerpdoel (§5), geen bijzaak.
4. **Internationaal by default.** Ocideck draait in 31 talen. De regels zijn opgedeeld in
   *universele* regels (IBAN, creditcard, e-mail, secrets, MRZ) die altijd draaien, en
   *landpakketten* die per regio aan/uit gaan. Zonder die scheiding lopen we bij 40
   landnummerformaten tegelijk vast in de FP's.
5. **Alles wat gerenderd wordt, wordt gescand.** Titel, subtitel, bullets, tabelcellen,
   bijschriften, alt-teksten, quotes, code, vrije markdown, sprekersnotities, en de
   deck-frontmatter. Notities zijn in de praktijk het vuilste veld én ze belanden in
   PPTX-export (`export_service.dart:298`) — juist die mogen niet vergeten worden.
6. **Geen nieuwe dependencies.** Checksums, MRZ-validatie en telefoonvalidatie schrijven we
   zelf. Elke pubspec-wijziging trekt de SBOM-gate open; dat is het niet waard voor
   algoritmes van twintig regels.

---

## 2. Architectuur

### 2.1 Eigen engine, bestaande UI

De detectie wordt een **eigen familie** (zoals `miauw_compliance_analyzer.dart` dat al is),
niet een uitbreiding van `SlideQualityAnalyzer`. Redenen:

- `SlideQualityIssue` heeft geen tekstbereik (`start`/`end`). Redactie heeft dat nodig.
- De regelverzameling wordt groot (~90 regels); de conventiecheck kapt `lib/`-bestanden af
  op 1000 regels.
- Privacy heeft eigen state die kwaliteit niet heeft: dispositie per slide, ignore-lijsten,
  landpakketten.

Maar de bevindingen **landen wél in het bestaande kwaliteitspaneel**, want daar kijkt de
gebruiker al. Dat doen we met een adapter: elke `PrivacyFinding` wordt gemapt naar een
`SlideQualityIssue` met een nieuwe `SlideQualityCategory.privacy`, precies zoals
`combinedSlideQualityResult()` nu al de asynchrone contrastcheck inmengt
(`slide_quality_panel.dart:20-26`).

`SlideQualityIssueKind` is een gesloten enum met een exhaustieve switch. We voegen er dus
**niet** 90 waarden aan toe, maar zes:

```
privacyIdentifier      — direct identificerend nummer/gegeven
privacySecret          — credential, sleutel, token
privacySpecialCategory — AVG art. 9/10
privacyBulk            — massa-persoonsgegevens (tabel, lijst)
privacyStructural      — lek via metadata, pad, URL
privacyUnscannable     — inhoud die we niet kúnnen controleren (data-URI, remote media)
```

De concrete regel zit in `args['rule']` (bijv. `nl.bsn`) en wordt gelokaliseerd via een
aparte `privacyRuleLabel(l10n, ruleId)`-map. Zo blijft de exhaustieve switch klein en
groeit de regelset zonder de compile te breken.

### 2.2 Bestanden

> **Implementatienoot (2026-07-15).** De indeling hieronder week bij de bouw af van
> dit ontwerp: er is géén data-driven `PrivacyRule`-descriptor en géén
> `privacy_lexicon.dart` gekomen. De detectors zijn methodes in de scanner, met de
> data (patronen, contextwoorden) in een bestand per familie. Dit zijn de
> feitelijke bestanden. De regelcatalogus in §3 beschrijft de vólledig ontworpen
> dekking; wat daarvan gebouwd is, staat in de Status-tabel bovenaan en in de code.

| Pad | Rol |
| --- | --- |
| `lib/models/privacy_finding.dart` | `PrivacyFinding`, `PrivacyFamily`, `PrivacyConfidence`, `PrivacyScanResult`, `maskValue`, `defaultDisabledPrivacyRules` |
| `lib/models/privacy_disposition.dart` | `PrivacyDisposition` + `effectivePrivacyDisposition` (deck- en slide-stand samen) |
| `lib/services/privacy/privacy_scanner.dart` | Orkestratie én de inline-detectors: e-mail, telefoon, IBAN, BSN, EU-nummers, secrets, bijzondere categorieën, adres/postcode, naam, structureel — plus allowlist en co-occurrence-escalatie |
| `lib/services/privacy/privacy_contact_rules.dart` | Adres (straat + huisnummer), NL-postcode, gelabelde persoonsnaam: patronen, straatachtervoegsels, placeholder-personen |
| `lib/services/privacy/privacy_phone_rules.dart` | Telefoon: E.164, nationale vorm, contextwoorden, toegekende landnummers, gereserveerde reeksen |
| `lib/models/privacy_lexicon.dart` | `PrivacyLexiconEntry`, `PrivacyTermMatch` (word/prefix/compound), `PrivacyLexiconRole`, `kMinCompoundLength` |
| `lib/services/privacy/privacy_plate_rules.dart` | Kenteken (sidecodes 1-14, verplicht contextwoord) en buitenlandse postcodes per land |
| `lib/services/privacy/privacy_regions.dart` | Landpakketten: welke regio's aan staan, en welke regels daaraan hangen |
| `lib/services/privacy/privacy_context_role.dart` | ConText: rolherkenning (verdachte/aangever/getuige) met terminatiewoorden en drieweg-uitkomst |
| `lib/services/privacy/privacy_lexicon_data.dart` | Het gebundelde art. 9/10-lexicon: term, categorie, taal, matchmodus, gewicht, rol |
| `lib/services/privacy/privacy_digital_rules.dart` | Digitale identificatoren: IPv4/IPv6, MAC, IMEI, ICCID, IMSI, social handles, device-ID's |
| `lib/services/privacy/privacy_location_rules.dart` | Geboortedatum en coördinaten: datumvormen, contextwoorden, lat/lon, `geo:`-URI, plus-code, what3words |
| `lib/services/privacy/privacy_scanner_detectors.dart` | `part of` de scanner: de detectoren voor MRZ, digitaal, geboortedatum en geo — puur om het hoofdbestand onder de 1000-regelgrens te houden |
| `lib/services/privacy/privacy_document_rules.dart` | Reisdocumenten: de machine-readable zone (TD1/TD2/TD3) met de ICAO 9303-controlecijfers |
| `lib/services/privacy/privacy_eu_rules.dart` | Europese landpakketten: BE/BG/DE/EE/ES/FI/FR/HR/IT/PL/PT/RO/SE + UK (NHS/NINO) |
| `lib/services/privacy/privacy_checksums.dart`, `privacy_checksums_eu.dart` | 11-proef, mod-97, Luhn, ISO 7064, geboortedatum-validatie, enz. |
| `lib/services/privacy/privacy_secret_rules.dart` | Leverancierstokens, PEM, JWT, connection strings, wachtwoorden |
| `lib/services/privacy/privacy_special_rules.dart` | Art. 9/10-trefwoorden, genetische notatie, parketnummer, `statementSpan`, `identifiesAPerson` |
| `lib/services/privacy/privacy_structural_rules.dart` | Gebruikerspaden, URL-tokens, share-links, mailto, data-URI |
| `lib/services/privacy/privacy_bulk_rules.dart` | Massa-persoonsgegevens: tabelkolommen uit het lexicon, herhaalde treffers |
| `lib/services/privacy/privacy_allowlist.dart` | Testwaarden, gereserveerde reeksen, placeholder-e-mails/IBANs/kaarten |
| `lib/services/privacy/privacy_own_identity.dart` | De eigen-identiteitslijst (naam, e-mail, telefoon, domein) |
| `lib/services/privacy/privacy_projection.dart` | **De grens.** `AudienceDeck` (private constructor) + `forAudience()` / `forExternalProcessing()` |
| `lib/services/privacy/privacy_export_policy.dart` | Export-gate, spiegelt `ClassificationEnforcementPolicy` |
| `lib/services/privacy/privacy_quality_bridge.dart` | `PrivacyFinding` → `SlideQualityIssue` voor het kwaliteitspaneel |
| `lib/services/privacy/redaction_manifest_service.dart` | Redactiemanifest met gesalte commitments |
| `lib/state/privacy_provider.dart` | Riverpod: scanner-config uit settings, gememoiseerde deck-scan |
| `lib/l10n/slide_quality_localization.dart` | `privacyRuleLabel` (regel-labels) en de meldingteksten |
| `lib/widgets/panels/editor_panel_slide_settings.dart`, `lib/widgets/slides/slide_preview.dart` | Per-slide dispositie (accepteren / shield / redigeren) en de shield-badge in de preview |

Uitbreidingen aan bestaande bestanden: `slide_quality.dart` (categorie + 6 kinds),
`slide.dart` (veld `privacy`), `deck.dart` (veld `privacy` + `privacyIgnore`),
`markdown_service*.dart` (directives lezen/schrijven), `markdown_validator.dart`
(`_supportedCommentDirectives`), `inline_markdown.dart` (`InlineRun.redacted`),
`overlays.dart` (shield-badge + watermerk), `settings.dart` + `settings_provider.dart` +
`settings_dialog_security.dart`, `export_service.dart` (gate + redactie).

### 2.3 Wanneer draait het

Zoals de kwaliteitsanalyse: synchroon op elke deck-mutatie, met een `Expando`-memo per
slide. **Let op de bekende valkuil**: elke instelling die de scan beïnvloedt (actieve
landpakketten, uitgezette regels, eigen-identiteitslijst) moet ín de memo-sleutel, anders
blijven bevindingen hangen nadat de gebruiker een regel uitzet
(`slide_quality_analyzer.dart:617-643`).

Prestatiebudget: < 5 ms per slide van 2 kB. Haalbaar met (a) statisch gecompileerde
regexes, (b) een goedkope prefilter per familie (bevat de tekst een cijfer? een `@`? een
`:`? een `/`?) zodat de meeste slides 80% van de regels overslaan, en (c) de memo. De
redactie-renderer hergebruikt exact dezelfde gememoiseerde bevindingen, dus rendering kost
niets extra.

---

## 3. De detectiecatalogus

Kolom **Zekerheid**: `zeker` = checksum- of structureel gevalideerd, praktisch geen FP's ·
`waarschijnlijk` = sterk formaat zonder checksum · `mogelijk` = context-/woordgedreven.
Kolom **Std.**: staat de regel standaard aan (✓), aan binnen het regiopakket (◐), of uit (○).

### A. Nationale identificatienummers — met checksum

Deze zijn goud waard: een checksum drukt de FP-kans van "elk getal van 9 cijfers" naar bijna
nul. Waar géén checksum bestaat (US SSN, V-nummer), is een contextwoord verplicht.

| Regel-id | Wat | Validatie / FP-guard | Zekerheid | Std. |
| --- | --- | --- | --- | --- |
| `nl.bsn` | Burgerservicenummer | 11-proef (gewichten 9-8-7-6-5-4-3-2, laatste ×−1, som mod 11 = 0). **Kritiek:** ~9% van willekeurige 9-cijferige getallen slaagt hiervoor. Dus óók vereist: contextwoord binnen 40 tekens (`bsn`, `burgerservice`, `sofinummer`, `sofi`) **of** een veldpositie (label vóór een dubbele punt, eigen tabelkolom). Zonder context: `mogelijk`, alleen info. Testreeks `999999xxx` uitgesloten. | zeker | ✓ |
| `nl.btw_id_legacy` | Oud btw-identificatienummer van een eenmanszaak | `NL\d{9}B\d{2}` waarvan de 9 cijfers de 11-proef doorstaan → dit **is** het BSN van de ondernemer. Escaleert naar `error`. | zeker | ✓ |
| `nl.vnummer` | Vreemdelingennummer | 10 cijfers beginnend met 2, contextwoord verplicht (`v-nummer`, `vreemdeling`) | waarschijnlijk | ◐ |
| `nl.anummer` | A-nummer (BRP) | 10 cijfers, 11-proef-variant | waarschijnlijk | ◐ |
| `nl.big` | BIG-nummer (zorgverlener) | 11 cijfers, contextwoord `big` | waarschijnlijk | ◐ |
| `nl.agb` | AGB-code | 8 cijfers, contextwoord `agb` | mogelijk | ◐ |
| `be.rijksregister` | Rijksregisternummer | mod-97 over de eerste 9 cijfers (met `2`-prefix voor geboorten ≥ 2000); bevat geboortedatum en geslacht | zeker | ◐ |
| `de.steuer_id` | Steuerliche Identifikationsnummer | 11 cijfers, ISO 7064 MOD 11,10 + de cijferherhalingsregel (precies één cijfer komt 2-3× voor, één cijfer ontbreekt) | zeker | ◐ |
| `de.svnr` | Sozialversicherungsnummer | gewogen mod-10, bevat geboortedatum | zeker | ◐ |
| `fr.nir` | Numéro INSEE / sécurité sociale | 13 cijfers + 2 controlecijfers = 97 − (n mod 97). Bevat geslacht, geboortejaar/-maand, departement → is zelf al bijna een bijzonder gegeven | zeker | ◐ |
| `es.dni` / `es.nie` | DNI / NIE | 8 cijfers mod 23 → letter uit `TRWAGMYFPDXBNJZSQVHLCKE`; NIE: X/Y/Z → 0/1/2 | zeker | ◐ |
| `pt.nif` | Número de identificação fiscal | 9 cijfers, gewogen mod 11 | zeker | ◐ |
| `it.codice_fiscale` | Codice fiscale | 16 tekens, even/oneven-tabellen, mod 26 → controleletter. Codeert geboortedatum, geslacht, geboorteplaats | zeker | ◐ |
| `pl.pesel` | PESEL | gewichten 9-7-3-1…, mod 10. Codeert geboortedatum + geslacht | zeker | ◐ |
| `se.personnummer` | Personnummer | Luhn over 10 cijfers, geldige geboortedatum | zeker | ◐ |
| `no.fodselsnummer` | Fødselsnummer | twee mod-11-controles | zeker | ◐ |
| `dk.cpr` | CPR-nummer | mod-11 **is sinds 2007 losgelaten** — dus alleen datumvalidatie + contextwoord. Bewust `waarschijnlijk`, nooit `zeker`. | waarschijnlijk | ◐ |
| `fi.hetu` | Henkilötunnus | mod-31 met de tekentabel `0123456789ABCDEFHJKLMNPRSTUVWXY` | zeker | ◐ |
| `gr.amka` | ΑΜΚΑ | Luhn, eerste 6 = geboortedatum | zeker | ◐ |
| `ie.pps` | PPS Number | mod-23 controleletter | zeker | ◐ |
| `hr.oib` | OIB | ISO 7064 MOD 11,10 | zeker | ◐ |
| `cz.rodne_cislo` / `sk.rodne_cislo` | Rodné číslo | mod 11 (na 1954), geboortedatum + geslacht | zeker | ◐ |
| `hu.taj` | TAJ-szám | gewogen mod 10 | zeker | ◐ |
| `bg.egn` | ЕГН | gewichten 2-4-8-5-10-9-7-3-6, mod 11 | zeker | ◐ |
| `ro.cnp` | CNP | sleutel `279146358279`, mod 11 | zeker | ◐ |
| `si.emso` | EMŠO | mod 11 | zeker | ◐ |
| `ee.isikukood` / `lv.pk` / `lt.ak` | Baltische persoonscodes | mod-11 dubbele pas | zeker | ◐ |
| `at.svnr` | Sozialversicherungsnummer | gewichten 3-7-9-5-8-4-2-1-6, mod 11 | zeker | ◐ |
| `ch.ahv` | AHV-Nummer | `756.xxxx.xxxx.xx`, EAN-13-controlecijfer | zeker | ◐ |
| `mt.id` / `cy.id` / `lu.matricule` | Maltese/Cypriotische/Luxemburgse ID | formaat + context | mogelijk | ◐ |
| `uk.nino` | National Insurance Number | formaat `QQ123456A` + uitgesloten prefixen (BG, GB, NK, KN, TN, NT, ZZ), geen D/F/I/Q/U/V als eerste letter, geen O als tweede | waarschijnlijk | ◐ |
| `uk.nhs` | NHS-nummer | mod-11 (gewichten 10…2), rest 10 = ongeldig | zeker | ◐ |
| `us.ssn` | Social Security Number | géén checksum. Area ≠ 000/666/900-999, groep ≠ 00, serie ≠ 0000. **Contextwoord verplicht** (`ssn`, `social security`), anders veel te veel FP's op datums en ordernummers | waarschijnlijk | ◐ |
| `us.ein` | Employer ID Number | formaat + geldige prefixen | mogelijk | ◐ |
| `ca.sin` | Social Insurance Number | Luhn | zeker | ◐ |
| `in.aadhaar` | Aadhaar | **Verhoeff**-checksum (niet Luhn!), begint niet met 0 of 1 | zeker | ◐ |
| `in.pan` | PAN | formaat `AAAAA9999A` met geldige vierde letter | waarschijnlijk | ◐ |
| `br.cpf` | CPF | twee mod-11-controles | zeker | ◐ |
| `za.id` | ID Number | Luhn + geldige geboortedatum | zeker | ◐ |
| `au.tfn` | Tax File Number | gewogen mod 11 | zeker | ◐ |
| `au.medicare` | Medicare-nummer | gewogen checksum | zeker | ◐ |
| `cw.sedula` / `aw.persoonsnummer` | Curaçao / Aruba | formaat + contextwoord; geen gedocumenteerde checksum, dus bewust nooit `zeker` | mogelijk | ◐ |

> **Ontwerpnotitie.** De regiopakketten worden standaard geactiveerd op basis van de
> app-taal, plus altijd het pakket van de gebruiker zelf. Een Nederlandse gebruiker draait
> `nl` + universeel; wie in een internationale context werkt, vinkt extra pakketten aan, of
> kiest "alle landen" en accepteert de hogere FP-ruis. Dit is de belangrijkste knop tegen
> internationale ruis.

### B. Reis- en identiteitsdocumenten

| Regel-id | Wat | Validatie / FP-guard | Zekerheid | Std. |
| --- | --- | --- | --- | --- |
| `doc.mrz` | Machine-readable zone van paspoort/ID (TD1/TD2/TD3) | Twee of drie regels van 30/36/44 tekens, `P<` + ISO-3166-landcode, plus de mod-7-3-1-controlecijfers over documentnummer, geboortedatum, vervaldatum en het samengestelde cijfer. **Bijna nul FP's** en het is meteen `error`: een MRZ in een slide is een gescande identiteitskaart. **Geleverd** (`privacy_document_rules.dart`), getest tegen de ICAO 9303-specimens. | zeker | ✓ |
| `doc.passport_nl` | Nederlands paspoort-/ID-nummer | 9 alfanumeriek, contextwoord | waarschijnlijk | ◐ |
| `doc.driving_licence` | Rijbewijsnummer | landformaat + context | mogelijk | ◐ |
| `doc.residence` | Verblijfsdocument / visumnummer | formaat + context | mogelijk | ◐ |

### C. Financieel

| Regel-id | Wat | Validatie / FP-guard | Zekerheid | Std. |
| --- | --- | --- | --- | --- |
| `fin.iban` | IBAN | mod-97 = 1 na herschikking + landspecifieke lengtetabel. Bekende voorbeeld-IBANs uitgesloten (`NL91ABNA0417164300`, `DE89370400440532013000`, `GB82WEST…`) | zeker | ✓ |
| `fin.pan` | Creditcardnummer | Luhn + geldig IIN-bereik (Visa/Mastercard/Amex/Discover/JCB/UnionPay/Maestro). Testkaarten uitgesloten (`4111111111111111`, `4242424242424242`, `5555555555554444`, `378282246310005`). Staat er ook een CVV (`cvv`, `cvc` + 3-4 cijfers) of vervaldatum bij → `error` | zeker | ✓ |
| `fin.cvv` | CVV/CVC | alleen in combinatie met `fin.pan`; los is `123` betekenisloos | zeker (in combinatie) | ✓ |
| `fin.bic` | BIC/SWIFT | formaat `AAAABBCC(XXX)`, geldige landcode. Los is dit bedrijfsdata → `info`; naast een IBAN → escaleert | waarschijnlijk | ✓ |
| `fin.nl_bankrekening` | Oud NL-rekeningnummer | 9-10 cijfers, 11-proef | zeker | ◐ |
| `fin.us_routing` | ABA routing number | mod-10-checksum | zeker | ◐ |
| `fin.sepa_mandate` | SEPA-mandaat-ID / incassomachtiging | contextwoord + identificatiepatroon | mogelijk | ✓ |
| `fin.crypto_btc` | Bitcoin-adres | base58check (dubbele SHA-256) of bech32-checksum (BIP-173). Checksum ⇒ geen FP's | zeker | ✓ |
| `fin.crypto_eth` | Ethereum-adres | `0x` + 40 hex; bij gemengde casing de EIP-55-checksum verifiëren | zeker | ✓ |
| `fin.crypto_xmr` | Monero-adres | base58, lengte 95, prefix `4`/`8` | waarschijnlijk | ✓ |
| `fin.salary` | Salaris-/inkomensgegeven | bedrag + contextwoord (`brutoloon`, `salaris`, `jaarinkomen`, `uitkering`, `schuld`) **en** een identificerende bevinding op dezelfde slide | mogelijk | ✓ |

### D. Contact en locatie

| Regel-id | Wat | Validatie / FP-guard | Zekerheid | Std. |
| --- | --- | --- | --- | --- |
| `contact.email` | E-mailadres | RFC-light + geldig TLD. Uitgesloten: `example.*`, `test`, `localhost`, `*.invalid`, `noreply@`/`no-reply@`, en alles op de eigen-identiteitslijst uit de instellingen (zie §5.4) | zeker | ✓ |
| `contact.phone` | Telefoonnummer | **E.164** (`+CC…`): een tóégekend landnummer uit de ITU-lijst plus een geldige lengte (8–15 cijfers, minstens 4 na het landnummer) → **zeker**; dat is een structurele validatie, geen gok. **Nationaal** (`06-24681357`, `020 123 4567`): nul-trunkprefix, 9–13 cijfers, mét scheidingsteken → waarschijnlijk. **Kaal** (`0624681357`): alleen met een contextwoord (`tel`, `mobiel`, `phone`, …). **Uitgesloten:** datums (die halen de negen cijfers niet), ISBN's (`0-306-…` heeft geen cijfer achter de nul), bedragen/versienummers/tijdstippen (geen `+` en geen nul-trunk), en de gereserveerde "drama"-reeksen (US `555-01xx`, UK `07700 900xxx` / `020 7946 0xxx` / `01632 960xxx`, DE `+49 30 23125 xx`) | zeker / waarschijnlijk | ✓ |
| `contact.address` | Straat + huisnummer | straatnaampatroon + huisnummer + (postcode óf plaatsnaam) | mogelijk | ◐ |
| `contact.postcode_nl` | NL-postcode | `\d{4}\s?[A-Z]{2}`, met de verboden lettercombinaties SA/SD/SS eruit. **Postcode + huisnummer is in Nederland vrijwel uniek identificerend** → escaleert naar `warning` zodra beide op dezelfde slide staan | waarschijnlijk | ◐ |
| `contact.postcode_intl` | Postcodes per land | DE/FR/BE/PL/UK/US/CA-formaten binnen het regiopakket | mogelijk | ◐ |
| `contact.birthdate` | Geboortedatum | datum + contextwoord (`geboren`, `geb.`, `dob`, `geboortedatum`, `°`, `*`) óf een datum in een tabelkolom met kop "geboortedatum" | waarschijnlijk | ✓ |
| `contact.name` | Persoonsnaam | Zie §5.5 — bewust géén NER. Alleen: aanhef (`dhr.`, `mevr.`, `Herr`, `Sra.`, `Dr.`), naamlabel (`naam:`, `contactpersoon:`, `auteur:`), of een tabelkolom met een naamkop. Placeholder-personen uitgesloten (`Jan Jansen`, `John Doe`, `Max Mustermann`, `Mario Rossi`, `Jean Dupont`, …) | mogelijk | ✓ |
| `contact.geo` | Coördinaten | lat/lon-paar in plausibel bereik, `geo:`-URI, plus-code, what3words. Uitgesloten wanneer het een grafiek-as of een chart-dataset is | waarschijnlijk | ✓ |
| `contact.plate` | Kenteken | NL-sidecodes met de juiste letteruitsluitingen; overige landen binnen het regiopakket. Contextwoord aanbevolen (`kenteken`, `nummerbord`) omdat `XX-99-99` ook een artikelcode kan zijn | mogelijk | ◐ |

> **Gebouwd (2026-07-15):** `contact.email`, `contact.phone`, `contact.address`,
> `contact.postcode_nl` en de gelabelde `contact.name`. Adres en NL-postcode zijn
> elk `possible`; staan een straat-met-huisnummer en een postcode binnen ±40 tekens
> van elkaar, dan escaleren beide naar `certain` — postcode plus huisnummer wijst
> in Nederland één woonadres aan. Nog niet gebouwd: `contact.postcode_intl`,
> `contact.birthdate`, `contact.geo`, `contact.plate`.
>
> **Bijgewerkt (2026-07-19):** `contact.birthdate` en `contact.geo` zijn er, met
> tegengestelde poorten — en dat verschil is de kern van beide regels. De
> geboortedatum **eist** een contextwoord, want een datum is de meest voorkomende
> getalsvorm in een zakelijk deck (releases, deadlines, kwartalen) en zonder die
> poort meldt de regel de agenda. Coördinaten eisen er juist géén: twee
> kommagetallen met minstens vier decimalen binnen het bereik van de aardbol
> komen in gewone tekst niet voor. Vier decimalen is bewust de ondergrens —
> ongeveer elf meter; met minder wijst het paar een dorp aan in plaats van een
> deur, en dan is het geen persoonsgegeven meer. `geo:`-URI en what3words zijn
> `certain` (het formaat zégt dat het een plaats is), een plus-code blijft
> `possible` omdat zijn beperkte alfabet met productcodes botst.
>
> **Bijgewerkt (2026-07-19, fase 11):** `contact.name` kent vier poorten, en géén
> ervan kijkt naar de naam zelf — het blijft dus géén NER. Label en aanhef leveren
> `likely` (de auteur schrijft er letterlijk bij dát het een persoon is; dat is een
> structurele uitspraak). Nieuw zijn een **persoonspredicaat** — "wordt verdacht
> van", "meldde zich ziek", een werkwoordsvorm die geen ander onderwerp dan een
> mens kan hebben — dat óók `likely` geeft, en een **bevestigend e-mailadres**
> ("Marieke de Vries" naast `m.devries@example.com`) dat `certain` geeft, want daar
> bevestigen twee onafhankelijke structuren elkaar. De kále naam zonder één van
> deze vier valt er nog steeds buiten; daarvoor is de handmatige
> `[[…]]`-markering.

### E. Digitale identificatoren

| Regel-id | Wat | Validatie / FP-guard | Zekerheid | Std. |
| --- | --- | --- | --- | --- |
| `digital.ipv4` | IPv4-adres | Uitgesloten: RFC 5737-documentatiereeksen (`192.0.2.x`, `198.51.100.x`, `203.0.113.x`), `127.0.0.1`, `0.0.0.0`, `255.255.255.255`, en alles wat op een versienummer lijkt (voorafgegaan door `v`, of vier delen waarvan er één > 255). RFC 1918-adressen zijn instelbaar: standaard `info` (interne infra, geen persoonsgegeven), publiek IP = `warning` | waarschijnlijk | ✓ |
| `digital.ipv6` | IPv6-adres | `2001:db8::/32` (RFC 3849) uitgesloten | waarschijnlijk | ✓ |
| `digital.mac` | MAC-adres | `00:00:00:00:00:00` en `ff:ff:…` uitgesloten; niet matchen binnen een hex-dump | waarschijnlijk | ✓ |
| `digital.imei` | IMEI | Luhn over 15 cijfers | zeker | ✓ |
| `digital.iccid` | SIM-ICCID | Luhn, prefix `89` | zeker | ✓ |
| `digital.imsi` | IMSI | 15 cijfers, geldige MCC/MNC | waarschijnlijk | ◐ |
| `digital.handle` | Social handle / profiel-URL | `@naam` + LinkedIn/X/Facebook/Instagram/Mastodon/Telegram/Discord-profiel-URL's. `@` in een e-mail of een code-mention (`@override`, `@param`) uitgesloten | waarschijnlijk | ✓ |
| `digital.deviceid` | Advertising-ID / device-ID | UUID **met** contextwoord (`idfa`, `gaid`, `device`, `advertising`). Een kale UUID is te generiek → geen melding | mogelijk | ✓ |

> **Gebouwd (2026-07-19):** de hele familie, in `privacy_digital_rules.dart`.
> Drie dingen die de bouw opleverde en die niet uit het ontwerp volgden:
>
> * **De korte IPv6-regex matcht MAC-adressen en tijdstippen.** "Twee tot zeven
>   groepen hex met dubbele punten" dekt óók `00:00:00:00:00:00` en `01:02:03`.
>   De discriminant is dat een echt IPv6-adres altijd óf een `::` bevat óf uit
>   acht volle groepen bestaat; een MAC heeft er zes en een tijdstip drie, geen
>   van beide met `::`. Daarom staat de volledige grammatica in de code en niet de
>   korte versie.
> * **Een Amex-nummer is niet van een IMEI te onderscheiden.** Beide zijn vijftien
>   cijfers met een geldige Luhn. Amex is het enige kaartmerk met die lengte, dus
>   het IIN-bereik `34`/`37` uitsluiten ruimt de hele botsing op. De corpustest
>   vond dit meteen: het Amex-testnummer staat in §3-C van dit document.
> * **GitHub hoort niet bij de profiel-URL's.** Een `github.com/…`-link is in een
>   technisch deck vrijwel altijd een repository. Ook dat ving de corpustest, op
>   onze eigen `PENTEST_MIAUW.md`. De profiel-URL is bovendien `likely` en niet
>   `certain`: dát er een profiel staat is zeker, dat het een natuurlijk persoon
>   is niet — organisaties hebben ook accounts. Daarmee telt hij ook niet mee als
>   persoonskoppeling voor artikel 9, en dat is de juiste uitkomst.

### F. Credentials en secrets

De goedkoopste, hoogst renderende familie: prefix-gebonden tokens hebben vrijwel geen FP's.

| Regel-id | Wat | Validatie / FP-guard | Zekerheid | Std. |
| --- | --- | --- | --- | --- |
| `secret.aws` | AWS access key + secret | `AKIA`/`ASIA` + 16, plus een 40-teken base64-secret in de buurt. `AKIAIOSFODNN7EXAMPLE` (AWS' eigen documentatiesleutel) uitgesloten | zeker | ✓ |
| `secret.gcp` | Google API-key / service-account | `AIza…`, of een JSON met `"type": "service_account"` en `"private_key"` | zeker | ✓ |
| `secret.azure` | Azure connection string / SAS-token | `DefaultEndpointsProtocol=…;AccountKey=…`, of `sv=…&sig=…` | zeker | ✓ |
| `secret.github` | GitHub-token | `ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`, `github_pat_` | zeker | ✓ |
| `secret.gitlab` | GitLab-token | `glpat-` | zeker | ✓ |
| `secret.slack` | Slack-token / webhook | `xox[baprs]-`, `hooks.slack.com/services/…` | zeker | ✓ |
| `secret.stripe` | Stripe-sleutel | `sk_live_`, `rk_live_` (test-sleutels `sk_test_` → alleen `info`) | zeker | ✓ |
| `secret.llm` | LLM-API-sleutels | `sk-ant-` (Anthropic), `sk-` (OpenAI), `hf_` (Hugging Face) | zeker | ✓ |
| `secret.other_vendor` | Overige leveranciers | Twilio (`AC…`/`SK…`), SendGrid (`SG.`), Mailgun (`key-`), npm (`npm_`), PyPI (`pypi-`), Docker Hub, Datadog, Cloudflare | zeker | ✓ |
| `secret.jwt` | JSON Web Token | `eyJ…` waarvan de header base64url-decodeert naar geldige JSON met een `alg`-veld. Bijna nul FP's. **Bonus:** decodeer óók de payload en scan die op PII (`sub`, `email`, `name`) — een JWT is een PII-container | zeker | ✓ |
| `secret.private_key` | Private key | `-----BEGIN (RSA\|EC\|DSA\|OPENSSH\|PGP) PRIVATE KEY-----`, PuTTY `.ppk`, PKCS#12 | zeker | ✓ |
| `secret.connection_string` | Connection string met wachtwoord | `postgres://user:pass@`, `mysql://`, `mongodb+srv://`, `redis://`, `amqp://`, plus HTTP basic-auth in een URL | zeker | ✓ |
| `secret.env_assignment` | `.env`-achtige toekenning | `(PASSWORD\|SECRET\|TOKEN\|API_KEY\|PRIVATE_KEY)\s*[=:]\s*<niet-placeholder>`. Placeholders (`xxx`, `<your-key>`, `YOUR_API_KEY`, `changeme`, `***`) → `info` in plaats van `warning` | waarschijnlijk | ✓ |
| `secret.password_plain` | Wachtwoord in klare taal | Contextwoord uit het **meertalige** lexicon (`wachtwoord`, `password`, `passwort`, `mot de passe`, `contraseña`, `senha`, `hasło`, `salasana`, `lösenord`, `adgangskode`, `heslo`, `jelszó`, `κωδικός`, `пароль`, …) gevolgd door een waarde | waarschijnlijk | ✓ |
| `secret.hash` | Wachtwoordhash | `$2[aby]$` (bcrypt), `$argon2`, `$6$` (sha512-crypt), NTLM, `/etc/shadow`-regels | zeker | ✓ |
| `secret.totp` | TOTP-seed / herstelcodes | `otpauth://`, `secret=` in een otpauth-URI, blokjes herstelcodes | zeker | ✓ |
| `secret.entropy` | Generieke hoog-entropie-string | Shannon-entropie ≥ 4.0, lengte ≥ 20, gemengde casing + cijfers, én een secret-achtig contextwoord in de buurt. Uitgesloten: hashes van bekende lengtes (git-SHA's), base64-afbeeldingen, UUID's, checksums. Bewust **alleen `info`** — dit is het vangnet, geen scherprechter | mogelijk | ✓ |

### G. Bijzondere categorieën (AVG art. 9 en 10)

Hier zit de grootste FP-val: een slide *over* de AVG noemt "gezondheidsgegevens" zonder er
een te bevatten. De oplossing is de **co-occurrence-escalator** (§5.6): een art. 9-trefwoord
op zichzelf is hooguit `info`; pas wanneer op dezelfde slide óók een direct identificerend
gegeven staat (naam, BSN, e-mail, geboortedatum), wordt het `warning`/`error` —
"bijzonder gegeven gekoppeld aan een geïdentificeerde persoon".

| Regel-id | Wat | Validatie / FP-guard | Zekerheid | Std. |
| --- | --- | --- | --- | --- |
| `special.health_keyword` | Gezondheid | Meertalig lexicon: diagnose, medicatie, ziekteverzuim, zwangerschap, GGZ, psychiatrisch, verslaving, therapie, opname | mogelijk | ✓ |
| `special.icd10` | ICD-10-code | `[A-TV-Z]\d{2}(\.\d{1,2})?` — **zeer** FP-gevoelig (matcht `A12` in een tabelverwijzing). Contextwoord (`icd`, `diagnose`, `hoofddiagnose`) verplicht | waarschijnlijk | ◐ |
| `special.atc` | ATC-geneesmiddelcode | `[A-V]\d{2}[A-Z]{2}\d{2}` + context | waarschijnlijk | ◐ |
| `special.genetic` | Genetische gegevens | `rs\d{4,}` (dbSNP-identificatoren), HGVS-notatie (`c.123A>G`, `p.Val600Glu`) — laag FP-risico en onmiskenbaar genetisch | waarschijnlijk | ✓ |
| `special.biometric` | Biometrie | Trefwoorden (vingerafdruk, irisscan, gezichtsherkenning, stemprofiel) + biometrische template-blobs | mogelijk | ✓ |
| `special.criminal` | Strafrechtelijke gegevens | Trefwoorden (verdachte, veroordeling, strafblad, VOG, proces-verbaal, aanhouding) | mogelijk | ✓ |
| `nl.parketnummer` | Parketnummer | `\d{2}/\d{6}-\d{2}` — sterk, landspecifiek formaat. Direct art. 10 | waarschijnlijk | ◐ |
| `nl.pv_nummer` | Proces-verbaal-/BVH-nummer | formaat + context | mogelijk | ◐ |
| `special.religion` | Religie / levensovertuiging | lexicon | mogelijk | ✓ |
| `special.politics` | Politieke opvatting | lexicon (partijnamen + `stemde op`, `lid van`) | mogelijk | ○ |
| `special.union` | Vakbondslidmaatschap | lexicon | mogelijk | ✓ |
| `special.ethnicity` | Ras / etnische afkomst | lexicon — **hoog FP-risico**, standaard `info` en makkelijk uit te zetten | mogelijk | ○ |
| `special.sexlife` | Seksuele geaardheid / seksleven | lexicon | mogelijk | ○ |

> De regels met ○ staan standaard uit omdat hun FP-ratio op normale zakelijke slides te hoog
> is (een slide over diversiteitsbeleid gaat *over* etniciteit zonder etnische gegevens te
> bevatten). Ze zijn met één vinkje aan te zetten voor wie in die hoek werkt.

### H. Massa-persoonsgegevens en aggregatie

| Regel-id | Wat | Validatie / FP-guard | Zekerheid | Std. |
| --- | --- | --- | --- | --- |
| `bulk.table_column` | Tabelkolom met persoonsgegevens | Kolomkop uit het lexicon (`naam`, `name`, `nom`, `nombre`, `e-mail`, `bsn`, `geboortedatum`, `telefoon`, `adres`, …) **of** ≥ 60% van de cellen in een kolom matcht dezelfde regel → de hele kolom is PII | zeker | ✓ |
| `bulk.repeat` | Dezelfde regel ≥ N keer op één slide | N standaard 3. Eén e-mailadres = `warning`; veertig e-mailadressen = `error` en de melding zegt "massa-persoonsgegevens" | zeker | ✓ |
| `bulk.k_anonymity` | Kleine cellen in een tabel | Tabel met quasi-identificatoren (leeftijd/postcode/geslacht) en groepsgroottes < 5 → herleidbaar ondanks "geanonimiseerd" | mogelijk | ○ |
| `bulk.quasi_combo` | Combinatie van quasi-identificatoren | Geboortedatum + postcode + geslacht op één slide → praktisch uniek identificerend (Sweeney). Dit is de klassieke "maar het is toch geanonimiseerd"-val | waarschijnlijk | ✓ |

### I. Structurele lekken — de verstopplekken in markdown

Dit is de familie die generieke PII-scanners missen en die voor Ocideck juist eigen is.

| Regel-id | Wat | Validatie / FP-guard | Zekerheid | Std. |
| --- | --- | --- | --- | --- |
| `struct.user_path` | Gebruikerspad met een naam erin | `/Users/<naam>`, `/home/<naam>`, `C:\Users\<naam>` in afbeeldingspaden, codeblokken en stacktraces. Generieke accounts uitgesloten (`user`, `runner`, `ubuntu`, `jenkins`, `admin`, `root`) | waarschijnlijk | ✓ |
| `struct.url_token` | Token in een URL-query | `token`, `access_token`, `id_token`, `api_key`, `key`, `secret`, `sig`, `signature`, `X-Amz-Signature`, `X-Amz-Credential`, `sv=`+`sig=` (Azure SAS) | zeker | ✓ |
| `struct.url_pii` | Persoonsgegeven in een URL-query | `?email=`, `?user=`, `?phone=`, plus een JWT of e-mailadres in het pad | zeker | ✓ |
| `struct.share_link` | Deellink met ingebakken toegang | SharePoint/OneDrive/Google Drive/Dropbox/WeTransfer-links met een token-segment. Wie de link heeft, heeft het bestand | waarschijnlijk | ✓ |
| `struct.mailto` | `mailto:`-link | idem `contact.email`, maar ook in de link-URL en niet alleen in de tekst | zeker | ✓ |
| `struct.notes_leak` | Sprekersnotities met een bevinding | Elke bevinding in `notes` krijgt een eigen accent in de melding: notities zijn onzichtbaar in de preview **maar gaan mee in PPTX-export** (`export_service.dart:298`). Dit is de meest onderschatte lek | zeker | ✓ |
| `struct.strike_not_redaction` | Doorhaling als "redactie" | Een bevinding binnen `~~…~~` → "doorhalen verwijdert de tekst niet". Idem voor tekst die in de themakleur van de achtergrond is gezet | zeker | ✓ |
| `struct.data_uri` | Base64 data-URI-afbeelding | Onscanbaar. Melding is `privacyUnscannable`/`info`: "deze afbeelding kan niet gecontroleerd worden; controleer zelf op zichtbare persoonsgegevens" | zeker | ✓ |
| `struct.remote_media` | Remote afbeelding/video | Lekt het IP-adres van de kijker naar een derde bij het openen. Bestaat al als instelling (`allowRemoteMedia`); hier wordt het een privacybevinding | zeker | ✓ |
| `struct.filename` | Bestandsnaam van het deck | `briefing-jansen-bsn123.md` — de naam lekt buiten het document om, in mailbijlagen en bestandslijsten | waarschijnlijk | ✓ |
| `struct.frontmatter_author` | `author:` in de frontmatter | Meestal legitiem (de auteur zelf) → standaard `info`, en de eigen-identiteitslijst onderdrukt het volledig | mogelijk | ✓ |
| `struct.exif` | EXIF in een gelinkte afbeelding | GPS-coördinaten, camera-eigenaar, oorspronkelijke bestandsnaam. Vereist een minimale JPEG/APP1-lezer — **fase 2** | zeker | ✓ |

### J. Wat we bewust *niet* detecteren

Eerlijk zijn over de grenzen voorkomt vals vertrouwen. De documentatie en de lege-toestand
van het paneel zeggen dit expliciet:

- **Tekst in afbeeldingen.** Een screenshot van een CRM-scherm vol namen is voor ons een
  blob pixels. Geen OCR (te zwaar, te veel FP's, en offline-first is een uitgangspunt van
  Ocideck). We melden wél dát er een niet-controleerbare afbeelding staat (`struct.data_uri`,
  en bij fase 2 een informatieve melding per afbeelding).
- **Inhoud van gelinkte bestanden** (PDF's, video's, spreadsheets).
- **Vrije-tekstcontext zonder trefwoord.** "Hij is er slecht aan toe sinds de behandeling" is
  een gezondheidsgegeven zonder één term uit ons lexicon.
- **Gepseudonimiseerde maar herleidbare data.** We benaderen dit met `bulk.quasi_combo` en
  `bulk.k_anonymity`, maar echte herleidbaarheidsanalyse vergt de sleutel die wij niet hebben.
- **Namen zonder context.** Zie §5.5.

---

## 4. Openbaarmaking: wat gebeurt er ná detectie

### 4.0 Redactie is een eigenschap van de uitvoer, niet van de slide

De voor de hand liggende opzet — "zet deze slide op `redact`" — is te grof, en breekt op het
eerste serieuze gebruiksscenario: het pentestrapport.

Daar is dezelfde inhoud voor de **opdrachtgever** volledig zichtbaar (anders kan hij de
bevinding niet natrekken), voor een **certificerende instantie** zichtbaar onder NDA, en in de
**publieke samenvatting** geredigeerd. Eén bron, meerdere ontvangers, verschillende versies. Een
gevonden wachtwoord in een bewijsbijlage is daar geen lek maar het product: het is het bewijs
waarop een derde partij moet kunnen controleren of de bevinding klopt.

Dus: een bevinding krijgt geen *stand*, maar een **openbaarmakingsniveau** — wie mag dit zien.
En bij export kies je een **doelgroepprofiel**: een plafond. De projectie (§6) redigeert alles
wat boven dat plafond ligt.

Dat is precies de as die Ocideck al heeft: **TLP**. `slideVisibleAtTlp` (`deck.dart:15-16`)
laat bij export al slides vallen die strenger geclassificeerd zijn dan het exportniveau. Wij
hangen de redactie aan diezelfde ladder in plaats van er een tweede, concurrerende as naast te
zetten.

| Exportprofiel | Wie | Wat gebeurt er met de bevindingen |
| --- | --- | --- |
| `full` / TLP:RED | Opdrachtgever, auditor onder NDA | Niets geredigeerd. Dit is het exemplaar waarmee een derde partij een bevinding kan verifiëren |
| `restricted` / TLP:AMBER | Bredere kring binnen de organisatie | Persoonsgegevens geredigeerd; de bevindingen zelf blijven leesbaar en verifieerbaar |
| `public` / TLP:CLEAR | Publieke samenvatting, brede verspreiding | Alles boven het plafond weg; onredigeerbare slides (bewijs-screenshots) vallen wég in plaats van te doen alsof |

Voor een gewoon deck dat niets met de informatieveiligheidsmodule te maken heeft, blijft dit simpel: twee
profielen, "volledig" en "geredigeerd", en de auteur merkt niets van de onderliggende ladder.

### 4.1 De standen per slide

De per-slide-stand bepaalt niet *of* er geredigeerd wordt, maar hoe de bevinding wordt
behandeld en op welk niveau hij wordt vrijgegeven.

| Stand | Betekenis | Op de slide | In het `full`-profiel | In een lager profiel |
| --- | --- | --- | --- | --- |
| `warn` (standaard) | Nog geen beslissing genomen | niets | ongewijzigd | export-gate klaagt (§4.5) |
| `accept` | Bewust aanwezig, hoort hier | niets | ongewijzigd | geredigeerd |
| `shield` | Bewust aanwezig, ontvanger wordt gewaarschuwd | privacy-badge, optioneel watermerk | ongewijzigd + badge | geredigeerd + badge |
| `evidence` | Dit *is* de bevinding (pentest) | badge "bewijsmateriaal" | ongewijzigd | geredigeerd, of de slide valt weg als hij niet te redigeren is |
| `redact` | Nooit tonen, aan niemand | blokken | geredigeerd | geredigeerd |

`redact` is dus de enige stand die óók in het volledige exemplaar redigeert — voor gegevens die
in het rapport terecht zijn gekomen maar er nooit hadden mogen staan. De politiebriefing uit de
oorspronkelijke vraag is `accept` op deckniveau, geëxporteerd op `full`.

**Bewijs is geen lek.** Bevindingen op een slide met `FindingRole.evidence` (`slide.dart:58`)
krijgen automatisch de stand `evidence` in plaats van een waarschuwing. Een gevonden wachtwoord
in een bewijsbijlage moet niet als op te lossen probleem in het paneel staan; het moet een
openbaarmakingsniveau krijgen. Dat schrapt in één klap de grootste vals-positievenklasse in
precies de module waar persoonsgegevens verwacht worden.

**Onredigeerbaar bewijs valt weg, het wordt niet weggemoffeld.** Een bewijs-screenshot met
namen erin kunnen wij niet redigeren (§J: geen OCR). In het `public`-profiel verdwijnt zo'n
slide dan volledig — precies zoals het TLP-filter nu al slides laat vallen. Kun je het niet
redigeren, dan lever je het niet. Fail-closed.

### 4.2 Syntax in de markdown

Deckniveau, in de frontmatter (naast het bestaande `tlp:`):

```yaml
---
marp: true
theme: ocideck
title: Pentestrapport Acme
tlp: amber+strict
privacy: accept                  # warn | accept | shield | evidence | redact
privacy_disclosure: red          # het niveau waarop bevindingen vrijgegeven worden
privacy_ignore: nl.kenteken      # regels die deck-breed nooit melden
---
```

Slideniveau, als HTML-comment (naast het bestaande `<!-- tlp: red -->`):

```markdown
<!-- ocideck_privacy: evidence -->
<!-- ocideck_privacy_disclosure: red -->
<!-- ocideck_privacy_ignore: fin.iban, contact.phone -->
```

En met een regelfilter, voor het briefing-scenario "namen mogen, BSN's niet":

```markdown
<!-- ocideck_privacy: redact=nl.bsn,fin.iban -->
```

Plus de handmatige markering uit §6.4, die onafhankelijk van de detector werkt:

```markdown
De verdachte, [[Jan de Vries]], is aangehouden.
```

Regels: de slide-stand overschrijft de deck-stand. De directives moeten in
`_supportedCommentDirectives` (`markdown_validator.dart:111-142`), anders waarschuwt de
validator, en ze moeten door de round-trip-test (`make test-contracts`) heen.

### 4.3 Het shield op de slide

Een `_OciWachtOverlay` naast de bestaande `_TlpOverlay` in
`lib/widgets/slides/previews/overlays.dart:119-152`. De overlays wijken al voor elkaar (de
TLP-badge voor het logo, de footer voor de badge); het shield krijgt een eigen plek in die dans,
standaard linksonder.

Inhoud: een schildpictogram met een korte, gelokaliseerde tekst en de zwaarste gevonden familie
als subtekst ("Bevat persoonsgegevens" / "Bevat bijzondere persoonsgegevens" /
"Bevat bewijsmateriaal"). Kleuren uit `AppTheme`-tokens — rauwe `Color(0x…)`-literals zijn
verboden buiten de palette-bestanden.

Analoog aan `showClassificationWatermark` een optioneel diagonaal watermerk. In de HTML-export
een banner naast de bestaande `.tlp-export-banner` (`marp_html_service.dart:123-125`) plus een
`<meta name="privacy">`, en een keyword in de documentmetadata (`export_metadata.dart:40-74`) —
zodat de classificatie mee-reist met het bestand.

### 4.4 Redactie

Zie §6 — dat is de architectuur, en het is de kern van de feature.

### 4.5 De export-gate

Spiegelt `ClassificationEnforcementPolicy` en hangt op hetzelfde fail-closed chokepoint
(`ExportService.export`, `export_service.dart:134-137`). Drie standen:

- **Uit** — nooit iets van zeggen.
- **Waarschuwen** (standaard) — een samenvatting vóór het exporteren: "Profiel: geredigeerd.
  12 bevindingen, waarvan 9 geredigeerd, 2 als bewijs vrijgegeven, 1 nog niet afgehandeld."
  Met een doorklik naar de slides.
- **Blokkeren bij onafgehandelde bevindingen** — export weigert zolang er bevindingen met
  zekerheid `zeker` in stand `warn` staan.

"Afgehandeld" = de slide heeft een stand, of de regel staat op de ignore-lijst. Slides die door
het TLP-filter of `skipped` toch al buiten de export vallen, tellen niet mee.

## 5. De vals-positieven-strategie

Dit is waar de feature staat of valt. Zeven mechanismen, in volgorde van effect:

### 5.1 Checksums boven regexes
Elke regel die een checksum kán hebben, krijgt er één, en een regel zonder geldige checksum
haalt nooit zekerheid `zeker`. Dit alleen al elimineert het leeuwendeel van de ruis:
IBAN, PAN, IMEI, MRZ, en 30 van de 40 nationale nummers zijn zelfvalidereend.

### 5.2 Contextpoorten waar de checksum te zwak is
De 11-proef laat ~9% van alle willekeurige 9-cijferige getallen door. Een BSN-melding op elk
ordernummer is precies het scenario waarin de gebruiker de check uitzet. Daarom: 11-proef
**plus** een contextwoord binnen 40 tekens, óf een veldpositie die het gegeven als zodanig
labelt (`BSN: …`, een tabelkolom met de kop "BSN"). Zonder context blijft het `info`, niet
`warning`. Hetzelfde geldt voor US SSN (helemaal geen checksum) en ICD-10.

### 5.3 De registry van bekende nep-waarden
Eén centrale allowlist, want een demodeck dat op zijn eigen voorbeelden rood kleurt,
ondermijnt het vertrouwen in alle andere meldingen:

- `example.com/.org/.net`, `*.invalid`, `test`, `localhost`
- RFC 5737 (`192.0.2.x`, `198.51.100.x`, `203.0.113.x`), RFC 3849 (`2001:db8::`)
- Testcreditcards (`4111…`, `4242…`, `5555…`, `3782…`), voorbeeld-IBANs (`NL91ABNA0417164300`)
- De officiële NL-test-BSN-reeks (`999999xxx`)
- Gereserveerde "drama"-telefoonnummers (US `555-01xx`, UK `07700 900xxx`, DE `+49 30 23125 xx`)
- Documentatiesleutels (`AKIAIOSFODNN7EXAMPLE`) en placeholders (`<your-key>`, `YOUR_API_KEY`,
  `xxx`, `changeme`, `***`)
- Cijferreeksen zonder informatie (`000000000`, `123456789`, `111111111`)

### 5.4 De eigen-identiteitslijst
De grootste praktische FP-bron is de auteur zelf: zijn naam op de titelslide, zijn e-mailadres
in de footer, zijn telefoonnummer op de contactslide. Dat zijn geen bevindingen — dat is de
afzender. In de instellingen komt een lijstje "eigen gegevens" (naam, e-mailadres,
telefoonnummer, organisatiedomein), en alles wat daarop staat wordt onderdrukt. Zonder deze
knop vuurt vrijwel élk deck onterecht.

### 5.5 Namen: geen NER, wél context
Volledige named-entity-recognition offline in Flutter is niet realistisch, en een
voornamenlijst per taal is een licentie- en onderhoudsmoeras. In plaats daarvan detecteren we
namen alleen waar de *structuur* het zegt:

- na een aanhef (`dhr.`, `mevr.`, `Herr`, `Sra.`, `Dr.`, `Mr.`)
- na een naamlabel (`naam:`, `contactpersoon:`, `betrokkene:`, `auteur:`)
- in een tabelkolom met een naamkop (§H — dit is meteen de sterkste variant, want een
  geplakte CSV is precies het scenario dat je wilt vangen)
- naast een e-mailadres dat de naam bevestigt (`jan.jansen@…` naast "Jan Jansen")

Plus een uitsluitingslijst van placeholder-personen per taal: `Jan Jansen`, `John/Jane Doe`,
`Max/Erika Mustermann`, `Mario Rossi`, `Jean Dupont`, `Juan Pérez`, `Kalle Svensson`. Die
lijst is meteen een leuke bijvangst van de 31-talenopzet.

### 5.6 De co-occurrence-escalator
Het slimste mechanisme in het hele ontwerp, en de reden dat art. 9-detectie hier bruikbaar is
waar hij dat elders niet is. Losse trefwoorden ("diagnose", "vakbond") melden op zichzelf
hooguit `info`. Zodra op dezelfde slide óók een **direct identificerend** gegeven staat, gaat
de melding omhoog:

```
identificator ∧ art.9-trefwoord  →  error: "bijzonder persoonsgegeven, herleidbaar tot een persoon"
identificator ∧ salaris/schuld   →  warning
geboortedatum ∧ postcode ∧ geslacht → warning: praktisch uniek identificerend
PAN ∧ CVV                        →  error
IBAN ∧ naam                      →  warning
```

Een slide *over* privacywetgeving noemt "gezondheidsgegevens" zonder één identificator — die
blijft dus stil. Een slide met "Jan de Vries, BSN 123456782, diagnose F32.1" schreeuwt.

**De escalatie verbreedt ook het bereik.** Dit is niet cosmetisch, en de eerste versie had het
mís. Een bijzonder persoonsgegeven is geen wóórd maar een **mededeling**: lak je alleen het
trefwoord weg, dan houd je dit over —

```
Marieke de Vries meldde zich ziek met een ████████
```

— en dan staat de naam er nog, staat de ziekmelding er nog, en staat `diabetes-` er zelfs
letterlijk nog. Er is niets weggehaald; er is een woord bedekt. Zodra het gegeven herleidbaar
is tot een persoon beslaat de redactie daarom de hele **regel** waarin de treffer staat: één
bullet, één tabelcel, één alinea — de eenheid waarin de auteur de mededeling heeft
opgeschreven. Bewust de regel en niet de zin: zinsgrenzen zijn niet te vertrouwen ("Zie dhr.
Jansen. De diagnose is diabetes." splitst op de afkorting en laat de naam búíten de redactie),
en dat is de gevaarlijke kant om ernaast te zitten. Te ruim redigeren is hinderlijk; te krap
redigeren is een lek.

Hetzelfde geldt voor de patroonregels in deze familie. "Zaak 01/234567-19 tegen M. de Vries"
met alleen het parketnummer weg laat nog steeds zien dát zij verdachte is — en dát is het
art. 10-gegeven; het nummer is er hooguit het bewijs van.

### 5.7 Regiopakketten
Standaard draaien alleen de universele regels plus het landpakket van de app-taal (en het
door de gebruiker gekozen thuisland). Alle 40 landen tegelijk aanzetten is mogelijk, maar
kost FP-precisie — en dat staat er ook bij in de instellingen, in gewone taal.

### 5.8 Codeblokken krijgen een ander profiel
In een codeblok zijn secrets zéér relevant, maar telefoonnummers, postcodes en namen bijna
altijd ruis (constanten, testdata, voorbeeldwaarden). Per veld een regelprofiel:
`code`/`customMarkdown` draaien wél de secrets- en structurele families, maar niet
contact/identifiers — tenzij de gebruiker dat expliciet aanzet.

---

## 6. De redactie-architectuur

> **Het uitgangspunt: niet beschikbaar is niet beschikbaar.**
> Een zwarte balk over leesbare tekst is geen redactie — dat is de klassieke fout waar
> overheden en advocatenkantoren met enige regelmaat op stuklopen. Geredigeerde gegevens
> mogen een ontvangend oppervlak niet *bereiken*: niet als tekstlaag onder een rechthoek,
> niet in de semantics-tree, niet in een XML-onderdeel, niet in metadata, niet in een
> klembordbuffer, en niet in een API-request.

### 6.0 Eén grens, geen N transformaties

De naïeve opzet — "redigeer bij het renderen, en redigeer bij elk exportformaat" — is
fundamenteel onveilig, ook als je hem in eerste instantie compleet krijgt. Elk nieuw
uitvoerkanaal dat een toekomstige bijdrage toevoegt, is dan standaard een lek: de auteur
daarvan moet zich actief herinneren dat er zoiets als redactie bestaat. Dat is fail-open, en
dat is precies verkeerd om.

In plaats daarvan: **één projectiegrens.**

```
Deck (bron, echte gegevens)          ── blijft in de editor, gaat 1-op-1 naar de .md
  │
  └── PrivacyProjection.forAudience(deck, findings, settings)
        │
        └── AudienceDeck  ── de gevoelige substrings zijn hier al vervangen
              │              door blokken. De echte tekens bestaan niet meer
              │              in dit object.
              ├── SlidePreviewWidget (preview, thumbnail, presentatie, publieksvenster)
              ├── SlideRasterizer  → PDF, PPTX-afbeeldingen
              ├── MarpHtmlService  → HTML
              ├── PPTX-sprekersnotities (notesSlide*.xml)
              ├── ExportMetadata   → titel, onderwerp, keywords
              └── elk toekomstig kanaal, automatisch
```

Redactie is dus **geen renderingvlag maar een waarde-transformatie**, en hij gebeurt vóór de
splitsing naar de kanalen, niet erna.

**De sluitsteen is het typesysteem.** `AudienceDeck` krijgt een private constructor en is
alleen te maken via `PrivacyProjection`. De handtekeningen van de ontvangende oppervlakken
veranderen mee:

```dart
class AudienceDeck {
  final Deck deck;
  const AudienceDeck._(this.deck);   // alleen PrivacyProjection kan dit
}

// vroeger: export(Deck deck, …)      → nu:
Future<void> export(AudienceDeck deck, ExportFormat format, …)
Future<Uint8List> rasterize(AudienceDeck deck, …)
String build(AudienceDeck deck, …)              // MarpHtmlService
ExportMetadata from(AudienceDeck deck)
```

Wie over een jaar een vierde exportformaat schrijft, *kan* de ongeredigeerde gegevens niet
bereiken — de compiler weigert het. Een regel in `tool/check_conventions.dart` bewaakt dat de
audience-oppervlakken geen rauwe `Deck` meer accepteren, zodat de grens niet stilletjes
teruglekt.

Het aardige neveneffect: hiermee **verdwijnt het technisch riskantste onderdeel** uit het
oorspronkelijke plan. Er is geen bereik-bewuste `InlineRun.redacted` meer nodig en dus geen
offsetafbeelding door `parseInlineRuns` heen: tegen de tijd dat de tekst de widget bereikt,
staat er letterlijk `████`. De veiligere opzet is ook de simpelere.

### 6.1 De inventaris van ontvangende oppervlakken

Elk kanaal waarlangs slide-inhoud de app kan verlaten of een ontvanger kan bereiken, met de
bron in de code. Ieder van deze krijgt een `AudienceDeck` of wordt expliciet als bron-kanaal
gemarkeerd. Elk kanaal krijgt een eigen test.

| Kanaal | Code | Behandeling |
| --- | --- | --- |
| Preview / thumbnail / slidelijst | `slide_preview.dart`, `slide_thumbnail.dart` | AudienceDeck |
| Volledig scherm + **publieksvenster** | `fullscreen_presenter.dart`, `audience_window.dart` | AudienceDeck |
| PDF | `export_service.dart:238-255` — puur raster (`pw.Image`), **geen tekstlaag** ✓ | AudienceDeck (pixels) |
| PPTX-slides | `slide_rasterizer.dart` → PNG in de zip | AudienceDeck (pixels) |
| **PPTX-sprekersnotities** | `export_service.dart:298, 362` — platte tekst in `notesSlide*.xml` | AudienceDeck (tekst) |
| **Documentmetadata** | `export_metadata.dart:40-74` — titel, onderwerp, keywords in PDF/PPTX/HTML | AudienceDeck (tekst) |
| HTML | `marp_html_service.dart:64-154` — markdown letterlijk in `<script type="text/markdown">` | AudienceDeck (tekst) |
| Mermaid-diagrammen | `mermaid_render_service.dart`, `marp_html_service_charts.dart` | AudienceDeck |
| Semantics / schermlezer | Flutter-semantics van de preview-widgets | Volgt automatisch: de widget krijgt de tekens niet |
| Tekstselectie in een leesoppervlak | `SelectionArea` in `document_reader_screen.dart` | Volgt automatisch |
| **AI-verzoeken** | `ai_client_service.dart`, `finding_ai_service.dart`, `image_alt_ai_service.dart`, `management_summary.dart` | **Strengere projectie**, zie §6.2 |
| Auditdossier | `audit_dossier.dart` | AudienceDeck, tenzij het dossier bewust de bron vastlegt (dan expliciet als zodanig gemarkeerd) |
| Klembord (repetitie-samenvatting) | `rehearsal_summary.dart:55` | AudienceDeck |
| Klembord (markdown-editor) | `markdown_deck_editor.dart:666` | **Bron-kanaal** — dit ís de markdown, per ontwerp ongeredigeerd |
| Opslaan / WebDAV / Nextcloud | `file_service.dart`, `webdav_service.dart` | **Bron-kanaal** — de `.md` blijft integraal, dat was de eis |
| Logging | `lib/utils/log.dart` | Veldinhoud wordt nooit gelogd; bevindingen loggen alleen regel-id + slide-index, nooit de waarde |

### 6.2 Het publiek is niet hetzelfde als een derde partij

`accept` betekent: *dit publiek* mag dit zien. Het betekent níét dat de gegevens naar een
externe API mogen. Een politiebriefing die bewust namen en BSN's toont aan de zaal, mag die
niet ongemerkt naar een taalmodel sturen om er een managementsamenvatting van te laten maken.

Daarom twee projecties:

- `PrivacyProjection.forAudience(...)` — respecteert de dispositie. `accept` en `shield` laten
  de gegevens staan, `redact` haalt ze weg.
- `PrivacyProjection.forExternalProcessing(...)` — **negeert de dispositie** en verwijdert álles
  wat gedetecteerd is, ongeacht de keuze van de auteur, tenzij die daar apart en expliciet
  toestemming voor geeft. Dit is de projectie die de AI-diensten krijgen.

`ai_security_gate.dart` bestaat al en is de natuurlijke plek voor die poort.

### 6.3 De vervanging zelf

De vervanging mag de originele lengte **niet** naspiegelen. Negen blokjes waar een BSN stond
en elf waar een IBAN stond, vertelt de ontvanger wélk soort gegeven er is weggehaald en hoe
lang het was — en bij korte, gestructureerde waarden komt dat gevaarlijk dicht bij
reconstrueerbaar. Twee toegestane stijlen, instelbaar:

- **Blokken** (standaard): een vaste breedte, bijvoorbeeld `████████`, ongeacht de
  oorspronkelijke lengte.
- **Label**: `[BSN]`, `[E-MAILADRES]`. Eerlijker naar de ontvanger — die weet wát er is
  weggelaten — en in een briefing vaak juist prettig.

### 6.4 De auteur heeft het laatste woord

Detectie is per definitie best-effort. Wat de scanner niet ziet, redigeert hij niet — dat is
een grens van de techniek, geen bug (zie §J). Daarom moet de auteur onafhankelijk van de
detector kunnen redigeren, met een markering in de bron:

```markdown
De verdachte, [[Jan de Vries]], is aangehouden op [[de Kalverstraat 12]].
```

Alles tussen `[[…]]` gaat door de projectie de blokken in, ongeacht welke regel wel of niet
vuurt. In de editor is het gewone, zichtbare tekst met een accent; in elk ontvangend oppervlak
is het weg. De detector adviseert, de auteur beslist, de projectie voert uit.

(Dit vergt een nieuwe inline-markering in `inline_markdown.dart` en in de markdown-round-trip
— het is de enige plek waar we de inline-parser wél aanraken.)

### 6.5 De invariant en zijn test

> **De geredigeerde waarde komt in geen enkel ontvangend artefact voor — in geen enkele vorm.**

Testbaar, dus getest. Exporteer een deck met een bekende kanariewaarde en zoek de letterlijke
string in:

- de gegenereerde HTML-string, inclusief `<meta>`, `<title>` en het markdown-script-blok;
- **alle** zip-entries van de PPTX, inclusief `ppt/notesSlides/notesSlide*.xml` en
  `docProps/core.xml` + `docProps/app.xml`;
- de volledige PDF-bytes, inclusief de documentmetadata (raster is veilig, metadata is dat niet);
- de semantics-tree van de gerenderde slide (`tester.getSemantics`);
- de payload van een AI-verzoek;
- de klembordbuffer van de repetitie-samenvatting.

Nul treffers, anders faalt de suite. En de tegenhanger, even belangrijk: **de `.md` op schijf
bevat de waarde nog wél** — een redactiebeslissing mag de bron niet aantasten.

Aanvullend een structurele test die niet naar één waarde kijkt maar naar de grens zelf: geen
enkele functie in `export_service.dart`, `slide_rasterizer.dart`, `marp_html_service.dart`,
`export_metadata.dart` of `lib/widgets/presentation/` accepteert nog een rauwe `Deck`. Die
check hoort in `tool/check_conventions.dart`, want een test die je kunt omzeilen door een
parameter te veranderen, bewaakt niets.

### 6.6 Verifieerbare redactie: twee versies, één gezegelde bron

Redactie botst frontaal op het bestaande integriteitsmechanisme, en dat moet opgelost worden
vóórdat we een regel code schrijven.

**Het probleem.** `document_integrity.dart` legt een SHA-512-zegel over de gecanoniseerde
markdown (`Deck.sealHash`, `IntegrityStatus.intact` / `.changed`), en `audit_dossier.dart`
reist mee in het auditpakket "zodat een auditor die alleen het pakket heeft, kan zien wat er
geleverd is en hoe het te verifiëren". Een geredigeerd exportartefact heeft per definitie een
andere inhoud dan de bron. De auditor rekent de hash na, krijgt een mismatch en concludeert:
**gemanipuleerd**. Een vals tamper-alarm op een echt rapport is erger dan geen
integriteitscontrole hebben — het maakt het mechanisme onbetrouwbaar precies op het moment dat
het ertoe doet.

**De oplossing.** Het zegel blijft over de **bron**; dat is de identiteit van het rapport, niet
van één rendering. Elk afgeleid artefact draagt een *bewijsbare relatie* tot dat zegel mee, in
plaats van te doen alsof het de bron ís.

Per redactie gaat er een **commitment** mee:

```
commitment_i = SHA-256( salt_i ‖ waarde_i )
```

met een **eigen, willekeurige salt per redactie**. Dat de salt er is, is geen detail maar de
kern: een BSN heeft 10⁹ kandidaten, een telefoonnummer minder, een geboortedatum ~40.000. Een
kale SHA-256 van een geredigeerde waarde is in seconden terug te rekenen — dan publiceer je
precies wat je zojuist hebt weggelakt. Dit is de klassieke blunder in deze hoek en we moeten
hem expliciet vermijden.

Het geredigeerde artefact bevat:

- de blokken zelf, met een stabiele referentie: `[GEREDIGEERD #a3f1]` — zodat een verificateur
  kan zeggen "ik betwist redactie a3f1" (staande praktijk in juridische redactie);
- een **redactiemanifest**: per redactie `id`, `commitment`, `regel-id`, `slide-index`, `reden`;
- de hash van de gezegelde bron (`derived_from`), zodat de herkomst vaststaat.

De salts en de klaartekst zitten **alleen** in de volledige versie.

**Wat een derde partij daarmee kan:**

1. **Volledige verificatie** — wie beide versies heeft, kan elke redactie natrekken én bewijzen
   dat er verder niets is gewijzigd: de geredigeerde versie moet exact reconstrueerbaar zijn uit
   de bron door precies de gemanifesteerde spans te vervangen.
2. **Selectieve openbaarmaking** — de auteur kan één betwiste redactie openen door alleen díé
   salt en díé waarde vrij te geven. Dat bewijst dat redactie `#a3f1` precies die waarde verborg,
   zonder één van de andere redacties prijs te geven. Dat is precies wat een verificatieproces
   nodig heeft: een derde partij die één bevinding wil controleren, hoeft daarvoor niet het hele
   rapport ongeredigeerd te krijgen.
3. **Geen stille wijziging van het manifest** — de hash van het redactiemanifest valt onder het
   zegel, dus achteraf een redactie toevoegen of weglaten is zichtbaar.

**`IntegrityStatus` krijgt een vierde waarde:** `redactedDerivative`. Een geredigeerd artefact
kondigt zichzelf aan, en de verificatie loopt tegen het manifest in plaats van tegen de ruwe
inhoudshash. Geen vals alarm meer.

**Het auditpakket** (`audit_dossier.dart`) levert dan in één handeling: het gezegelde volledige
rapport, de geredigeerde versie, het redactiemanifest, de bewijs-hashtabel
(`evidence_hash_service.dart`) en het dossier dat uitlegt wélke versie dit is, hoeveel redacties
er zijn en hoe je ze controleert. Dat laatste is geen bijzaak: een geredigeerd rapport zonder
uitleg hoe het te verifiëren valt, is een rapport dat een auditor niet kan aannemen.

**Nog een grens, eerlijk benoemd:** dit is een *commitment*-schema, geen redactable signature in
de cryptografische zin. Het bewijst dat een geredigeerde versie een eerlijke afleiding is van een
bron die je óók hebt, of dat één specifieke redactie een specifieke waarde verborg. Het bewijst
niet, zonder de bron, dat de niet-geredigeerde delen ongewijzigd zijn — daarvoor zou elke slide
apart in een Merkle-boom moeten hangen die onder het zegel valt. Dat is een natuurlijke fase-8
uitbreiding, en de manifest-structuur wordt er nu al op voorbereid.

## 7. Instellingen

Nieuwe sectie in het tabblad "Veiligheid" (`settings_dialog_security.dart`), want daar staan
`allowRemoteMedia` en de classificatie-handhaving al.

| Instelling | Type | Standaard |
| --- | --- | --- |
| `privacyChecksEnabled` | bool (hoofdschakelaar) | **aan** |
| `privacyImageFaceDetection` | bool — afbeeldingen nakijken op gezichten | **aan** (grijs zolang de hoofdschakelaar uit staat) |
| `privacyFamilies` | set van 8 familieschakelaars | alle aan |
| `privacyDisabledRules` | set van regel-id's | leeg |
| `privacyRegions` | set van landpakketten | **heel Europa** (EU-27 + EER + CH + UK) — **geleverd** |
| `privacyStrictSeverity` | bool — behandel `zeker` als fout i.p.v. waarschuwing | uit |
| `privacyExportGate` | uit / waarschuwen / blokkeren | waarschuwen |
| `privacyRedactionStyle` | blokken (`████`) / label (`[BSN]`) | blokken |
| `privacyOwnIdentity` | vrije lijst: naam, e-mail, telefoon, domein | leeg |
| `ociWachtWatermark` | bool | uit |
| `privacyPreviewProfile` | welk doelgroepprofiel de preview toont | het profiel waarmee je zou exporteren |
| `privacyCustomRules` | pad naar een eigen regelbestand (fase 7) | leeg |

De hoofdschakelaar staat aan; alles is uit te zetten. Per regel uitzetten kan via
`privacyDisabledRules` (vanuit de melding zelf: "deze regel nooit meer melden") — dat is een
veel bruikbaardere ontsnappingsklep dan 90 vinkjes in een dialoog.

**Regiopakketten: heel Europa standaard aan.** Dat is verdedigbaar juist omdát de
FP-strategie op checksums leunt: van de ~30 Europese nummers zijn er ruim twintig
zelfvaliderend (mod-97, mod-11, ISO 7064, Luhn), en die kosten dus vrijwel geen precisie als je
ze allemaal aanzet. De uitzonderingen zijn de handvol zonder bruikbare checksum — `dk.cpr`
(sinds 2007 losgelaten), `uk.nino`, `mt.id` / `cy.id` / `lu.matricule` — en die zijn sowieso
contextpoort-gebonden (§5.2). "Heel Europa" leest hier als EU-27 + EER (NO/IS/LI) + Zwitserland
+ het VK: decks reizen, en een Nederlandse organisatie ziet Britse en Zwitserse gegevens
routinematig. Wie het smaller wil, zet pakketten uit.

**`privacyOwnIdentity` bewaart zelf persoonsgegevens.** De lijst met de eigen naam, het eigen
e-mailadres en telefoonnummer komt in de lokale voorkeuren te staan. Dat is nieuw op dit
apparaat en het hoort dus in de privacyverklaring (§12) — een privacyfeature die stilletjes een
nieuwe opslag van persoonsgegevens introduceert, is precies het soort ironie dat je niet wilt.

`privacyCustomRules` is de organisatie-uitbreiding: interne zaaknummers, projectcodenamen,
klantreferenties. Goedkoop te bouwen (het regelmodel is al data-driven) en voor
organisatiegebruik het verschil tussen "leuk" en "onmisbaar".

---

## 8. Fasering

Kleine, incrementele commits — één samenhangende stap per commit, elk met `make check` groen.

| Fase | Inhoud | Waarom hier |
| --- | --- | --- |
| **0** | Model + scanner-skelet + regel-descriptor + drie regels end-to-end (`contact.email`, `fin.iban`, `nl.bsn`) + hoofdschakelaar + bevindingen zichtbaar in het kwaliteitspaneel | Bewijst de hele keten van markdown tot UI met minimaal oppervlak. Hier ontdekken we de memo-valkuil en de UI-integratie, niet bij regel 87 |
| **1** | `privacy_checksums.dart` + de checksum-gedreven identificatoren (NL, EU) + de allowlist-registry | Het fundament waarop de FP-strategie rust |
| **2** | Secrets-familie | Hoogste opbrengst per regel, laagste FP-risico. Waarschijnlijk meteen al waardevol op bestaande decks |
| **3** | Standen + openbaarmakingsniveaus: directives lezen/schrijven, round-trip, validator-allowlist, per-slide dropdown, shield-overlay, `evidence` gekoppeld aan `FindingRole.evidence` | De feature wordt bruikbaar: je kunt nu iets *doen* met een bevinding |
| **4** | **De projectiegrens**: `AudienceDeck` + `PrivacyProjection`, alle ontvangende oppervlakken omgezet naar het nieuwe type, de conventiecheck die rauwe `Deck`-doorgifte verbiedt, de handmatige `[[…]]`-markering, en de kanarietest per kanaal | Het hart van de feature. Dit is een refactor van bestaande handtekeningen (export, rasterizer, HTML, presentatie) — daarom als eigen fase, met een groene suite ervoor en erna |
| **5** | **Exportprofielen + verifieerbare redactie** (§4.0, §6.6): profielkeuze in het exportdialoog, het redactiemanifest met gesalte commitments, `IntegrityStatus.redactedDerivative`, en het auditpakket dat beide versies + het manifest levert | Zonder dit breekt redactie het bestaande zegel en krijgt een auditor een vals tamper-alarm. Moet dus áf zijn voordat iemand een geredigeerd rapport de deur uit doet |
| **6** | Bijzondere categorieën + lexicons + co-occurrence-escalator + bulk/tabelregels | Vereist dat de basis staat, want het bouwt op de identificatoren |
| **7** | Instellingen-UI (regiopakketten, regels uitzetten, eigen identiteit), export-gate, eigen regels | Fijnafstelling nadat we weten hoe het in de praktijk ruist |
| **8** | Wereldpakketten (US/UK/CA/AU/IN/BR/ZA), EXIF, `struct.*`-restant, Merkle-boom per slide onder het zegel | Uitbreiding op een bewezen fundament |

Documentatie loopt mee per fase (niet aan het eind) — zie §12 voor de volledige lijst. Dat geldt
nadrukkelijk óók voor **de privacyverklaring** (`privacy_statement_content.dart`): die wordt aan
de gebruiker getoond vóór het eerste gebruik, en hij mag geen functies beschrijven die nog niet
bestaan. De copy voor de privacycontrole landt dus in fase 0 (de controle zelf draait, lokaal),
de alinea over redactie in fase 4, en de alinea over het controlespoor in fase 5 — elk in de
commit die de functie ook werkelijk levert.

L10n loopt ook mee per fase, met `make add-l10n SPEC=…`. Ruwe schatting: ~120 nieuwe strings
(6 kind-meldingen, ~90 regel-labels, ~25 UI-strings) × 30 talen. Veel regel-labels zijn
acroniemen of leenwoorden (BSN, IBAN, JWT, MRZ, PESEL) — die gaan in de `unchanged`-lijst van
`add_l10n.dart` en kosten dus geen vertaalwerk. De contextlexicons zijn **geen** l10n-strings
maar data-assets: ze worden nooit getoond, alleen gematcht.

---

## 9. Testplan

| Test | Wat het bewaakt |
| --- | --- |
| `privacy_checksums_test.dart` | Elk algoritme met bekende geldige én ongeldige waarden. Ideaal doelwit voor `make mutate` |
| `privacy_rules_<familie>_test.dart` | Tabelgedreven: per regel minstens 1 positief en **3 negatieven**. De negatieven zijn de eigenlijke test |
| `privacy_false_positive_corpus_test.dart` | Scan `docs/*.md`, `README.md`, `CHANGELOG.md` en een corpus realistische zakelijke slides → **nul** bevindingen met zekerheid `zeker`. Dit is de regressietest die voorkomt dat een nieuwe regel de tool onbruikbaar maakt |
| `privacy_bsn_entropy_test.dart` | Property-test: genereer 10.000 willekeurige 9-cijferige getallen zonder context → verwacht nul `warning`-meldingen (de contextpoort doet zijn werk) |
| `privacy_scanner_fields_test.dart` | Elk slideveld wordt gescand: titel, subtitel, bullets, tabelcellen, bijschriften, alt, quote, code, **notities**, frontmatter, bestandsnaam |
| `privacy_disposition_test.dart` | Directives round-trippen door markdown → deck → markdown; slide overschrijft deck; ignore-lijsten werken |
| `privacy_projection_test.dart` | **De invariant, per kanaal** (§6.5): een kanariewaarde komt niet voor in de HTML (incl. `<meta>`, `<title>`, markdown-blok), niet in enige PPTX-zip-entry (incl. `notesSlide*.xml`, `docProps/*`), niet in de PDF-bytes (incl. metadata), niet in de semantics-tree, niet in een AI-payload, niet in de klembordbuffer. En: de `.md` op schijf bevat hem nog wél |
| `check_conventions.dart` (nieuwe regel) | **De grens zelf**: geen ontvangend oppervlak accepteert nog een rauwe `Deck`. Een test die je omzeilt door een parameter te wijzigen, bewaakt niets |
| `privacy_manual_redaction_test.dart` | `[[…]]` round-trippt door de markdown en wordt geredigeerd ongeacht welke regels aanstaan |
| `privacy_disclosure_profile_test.dart` | Hetzelfde deck geëxporteerd op `full` / `restricted` / `public` levert respectievelijk niets, de PII, en alles-boven-het-plafond geredigeerd. Onredigeerbare bewijsslides **vallen weg** in `public`, ze worden niet stilzwijgend meegeleverd |
| `privacy_redaction_manifest_test.dart` | Commitments zijn gesalt (dezelfde waarde levert in twee decks een ander commitment); één redactie is selectief te openen zonder de andere prijs te geven; het manifest valt onder het zegel; `IntegrityStatus.redactedDerivative` geeft **geen** vals `changed` |
| `privacy_export_policy_test.dart` | De gate: uit / waarschuwen / blokkeren, en wat "afgehandeld" betekent |
| `privacy_panel_test.dart` + golden | Shield-badge en redactiebalken renderen zoals bedoeld; badge wijkt correct voor logo en footer |
| `privacy_performance_test.dart` | 100-slide deck < budget; memo doet zijn werk (tweede scan is gratis) |

---

## 10. Risico's

1. **De projectiegrens lekt terug.** Het grootste risico is niet technisch maar sociaal: iemand
   voegt over een half jaar een kanaal toe en geeft het een rauwe `Deck`. Daarom is de grens
   een *type* en geen afspraak, en bewaakt `check_conventions.dart` hem. Een afspraak in een
   ontwerpdocument houdt geen data tegen.
2. **Prestaties bij grote decks.** Gemitigeerd met prefilters en de memo, maar dit moet gemeten
   worden, niet aangenomen — vandaar de perf-test in fase 0 al.
3. **De FP-ratio in het veld.** Onze corpustests zijn een benadering. Bouw daarom vanaf fase 0
   de "meld deze regel nooit meer"-knop in: als het toch ruist, kan de gebruiker chirurgisch
   ingrijpen in plaats van de hele feature uit te zetten.
4. **Vals vertrouwen.** Een groene balk mag nooit lezen als "dit deck bevat geen
   persoonsgegevens" — alleen als "wij hebben niets gevonden met de regels die aanstaan". De
   lege toestand van het paneel benoemt expliciet wat we níét kunnen zien (§J).
5. **Het verkeerde profiel exporteren.** De duurste fout die een gebruiker kan maken is het
   `full`-exemplaar naar de brede kring sturen. Daarom: het profiel is een expliciete keuze in
   het exportdialoog (geen onthouden default), de gekozen doelgroep staat op de exportbanner en
   in de metadata van het bestand, en de bestandsnaam draagt het profiel (`…-volledig.pdf` /
   `…-geredigeerd.pdf`). Een verwisseling moet je kunnen *zien*, niet moeten onthouden.

---

## 11. Genomen beslissingen

Vastgesteld, niet meer open:

1. **De editor-preview volgt de instellingen.** Er is geen vaste keuze tussen bron en projectie:
   de preview toont het doelgroepprofiel dat in de instellingen actief is (`privacyPreviewProfile`),
   met standaard het profiel waarmee je zou exporteren. Daar is dit stelsel voor: de auteur ziet
   wat de gekozen ontvanger ziet. Een expliciete "toon origineel"-knop blijft beschikbaar in het
   paneel — de bron staat sowieso in de editorvelden en in markdown-modus.
2. **Gemengd in het kwaliteitspaneel**, met een eigen categoriefilter. Eén plek waar de gebruiker
   kijkt.
3. **`zeker`-bevindingen zijn standaard een waarschuwing**, niet een fout, met
   `privacyStrictSeverity` voor gereguleerde omgevingen. Fout zou `qualityBlockExportOnErrors`
   onbedoeld scherp zetten voor bestaande gebruikers.
4. **Heel Europa staat standaard aan** (EU-27 + EER + CH + UK). Verdedigbaar omdat het merendeel
   van die nummers zelfvaliderend is; de handvol zonder checksum is contextpoort-gebonden. Zie §7.
5. **`accept` geldt niet voor AI-verzoeken.** De AI-diensten krijgen
   `PrivacyProjection.forExternalProcessing()`, die de dispositie negeert en alles verwijdert wat
   gedetecteerd is. Wil de gebruiker dat toch anders, dan is dat een aparte, expliciete
   toestemming — nooit impliciet uit een publieksbeslissing af te leiden.
6. **De salts leven in de volledige versie**, die de klaartekst toch al bevat. Geen apart
   sleutelbeheer; "wie de volledige versie mag zien, kan verifiëren" volgt vanzelf. Escrow met
   selectieve openbaarmaking per betwiste redactie (§6.6) blijft als latere uitbreiding op tafel,
   maar vraagt sleutelbeheer dat Ocideck nu niet heeft.
7. **Het exportprofiel ís het TLP-plafond.** Eén ladder, geen tweede concurrerende as. Een deck
   zonder TLP-markering krijgt een expliciet standaardniveau (niet: een niveau dat per ongeluk
   ontstaat).

---

## 12. Documentatie en de privacyverklaring

### 12.1 Wat er bijgewerkt moet worden

| Doel | Wat |
| --- | --- |
| `lib/widgets/privacy_statement_content.dart` | **De privacyverklaring** — gedeeld door de toestemmingspoort én het instellingenscherm. Zie §12.2 |
| `docs/USER_GUIDE.md` | Nieuwe `##`-sectie "Privacycontrole", naast "Traffic Light Protocol (TLP)" (regel 347) |
| `docs/FILE_FORMAT.md` | De frontmatter-sleutels `privacy:`, `privacy_disclosure:`, `privacy_ignore:`, de `<!-- ocideck_privacy* -->`-directives, de `[[…]]`-markering, en het redactiemanifest |
| `docs/CHECKS.md` | Rij in de "at a glance"-tabel + een `###`-sectie in de vorm Runs / Covers / Failure means |
| `docs/SOURCE_MAP.md` | Eén regel per nieuw `lib/`-bestand |
| `docs/design/OCIWACHT.md` | Dit document. Design-docs vormen een eigen klasse in `docs_registration_test.dart`, maar worden nog steeds gecontroleerd: het bestand moet als asset in `pubspec.yaml` staan **en** een `_docTile` krijgen in `settings_dialog_docs.dart`, met een titel die in alle 31 talen vertaald is |
| `CHANGELOG.md` | Per fase |

### 12.2 De privacyverklaring

`privacy_statement_content.dart` heeft nu drie secties: de licentie, "Wat OciDeck op dit apparaat
bewaart", en "Wat je apparaat verlaat". De doc-comment zegt expliciet dat de consent-poort en het
instellingenscherm "in sync **and truthful**" blijven — en dat is precies de reden dat deze copy
**mee moet komen met de fase die de feature levert, niet ervoor**. Een privacyverklaring die
functies beschrijft die nog niet bestaan, is niet truthful; hij is een belofte.

Drie wijzigingen, plus één nieuwe sectie.

**A. "Wat OciDeck op dit apparaat bewaart" — uitbreiden.**
De privacycontrole introduceert zelf nieuwe lokale opslag, en dat is precies het soort ironie dat
je in een privacyfeature niet wilt laten liggen:

> •  Je privacy-instellingen, waaronder de lijst met je **eigen gegevens** (naam, e-mailadres,
> telefoonnummer, organisatiedomein) die je opgeeft zodat OciDeck jouw eigen contactgegevens niet
> als bevinding meldt. Die lijst blijft op dit apparaat en wordt nergens naartoe gestuurd.

**B. "Wat je apparaat verlaat" — de AI-alinea aanscherpen.**
De bestaande zin zegt dat de teksten die je laat verwerken naar het gekozen adres gaan. Dat wordt
nu preciezer én gunstiger:

> AI-assistentie (staat standaard uit): kies je een zelf-gehoste of cloud-backend, dan worden de
> teksten of afbeeldingen die je laat verwerken naar dat adres gestuurd. **Gegevens die de
> privacycontrole heeft herkend, worden er eerst uit verwijderd — ook als je ze op de dia zelf
> hebt geaccepteerd. Je akkoord dat een publiek iets mag zien, is geen akkoord om het naar een
> extern model te sturen.** Een lokaal AI-model op dit apparaat verstuurt niets.

**C. Nieuwe sectie: "De privacycontrole".**
Met een eigen kop, in de stijl van de bestaande drie:

> **De privacycontrole draait volledig op dit apparaat.** OciDeck kijkt je dia's na op gegevens
> die privacygevoelig kunnen zijn — identificatienummers, contactgegevens, wachtwoorden en
> sleutels, en aanwijzingen voor bijzondere persoonsgegevens. Die controle gebeurt lokaal: de
> inhoud van je dia's wordt daarvoor **niet** verstuurd, er worden geen bevindingen bijgehouden
> buiten dit apparaat, en er gaat geen statistiek naar ons of naar wie dan ook.
>
> **Wat je markdown-bestand betreft: er verandert niets.** Kies je ervoor gegevens te redigeren,
> dan gebeurt dat in wat je *toont en exporteert*. Je bronbestand behoudt de oorspronkelijke
> tekst. Dat is bewust: jij houdt je eigen gegevens.
>
> **Geredigeerde gegevens worden echt weggelaten, niet afgedekt.** Ze zitten niet als verborgen
> tekst onder een zwart balkje in je PDF, niet in de sprekersnotities van een PowerPoint, en niet
> in de broncode van een HTML-export.
>
> **Een geredigeerde export bevat wél een controlespoor.** Om een ontvanger te laten controleren
> dat er niets anders is weggehaald of veranderd, komt er per redactie een versleutelde
> verwijzing in het bestand. Die verwijzing is met een willekeurige toevoeging berekend en is niet
> terug te rekenen naar de oorspronkelijke waarde; alleen wie de volledige versie heeft, kan de
> redacties verifiëren. Onder de AVG blijven zulke verwijzingen persoonsgegevens
> (gepseudonimiseerd, niet geanonimiseerd) — behandel een geredigeerde export dus met dezelfde
> zorg als het origineel.
>
> **De controle garandeert niet dat alles wordt gevonden; ze verkleint de kans dat er
> persoonsgegevens onbedoeld uitlekken.** Tekst in afbeeldingen, gegevens in gelinkte bestanden en
> gevoelige informatie zonder herkenbaar patroon blijven buiten beeld. Een dia zonder meldingen is
> een dia waarin *wij* niets hebben gevonden — niet een dia waarvan vaststaat dat er niets in zit.
> De eindverantwoordelijkheid voor wat je deelt, blijft bij jou.

Die laatste alinea is niet optioneel. Zonder dat voorbehoud gaat iemand de groene balk lezen als
een vrijwaring, en dan hebben we een privacyfeature gebouwd die het probleem verergert.

Die ene zin is daarom de **hele belofte**, en hij staat op drie plaatsen waar hij ertoe doet: in de
privacyverklaring (`privacy_statement_content.dart`, óók in de toestemmingspoort), onder de
instelling zelf, en — het belangrijkst — in het **exportdialoog**, altijd, ook wanneer er niets is
gevonden. Juist dát is het gevaarlijke geval: een deck mét bevindingen waarschuwt zichzelf al,
maar een deck zónder bevindingen toont een groen "Klaar voor export" en dat leest als "schoon".
`privacy_promise_test.dart` houdt dat vast: het is een belofte die je niet stilletjes mag
oprekken.

### 12.3 Consequenties voor de toestemmingspoort

`PrivacyStatementContent` wordt óók getoond in `consent_dialog.dart:95`, vóór het eerste gebruik.
De nieuwe sectie verlengt die poort. Dat is aanvaardbaar — het is precies de informatie die iemand
vóór gebruik moet hebben — maar de tekst moet daarom kort en in gewone taal blijven, en de
technische details (commitments, salts, manifest) horen in `docs/USER_GUIDE.md`, niet in de poort.
De copy hierboven is met dat onderscheid geschreven.

Alle nieuwe copy gaat door `l10n.d()` en moet dus in alle 30 niet-Nederlandse talen vertaald
worden (`make add-l10n SPEC=…`). Dit is lopende tekst, geen acroniem: hier valt niets in de
`unchanged`-lijst weg te schrijven.

---

## 13. Versteviging van de art. 9-detectie, meertaligheid en beeld

Deze sectie komt voort uit een reeks metingen op de bestaande scanner. De cijfers
hieronder zijn gedraaid tegen de echte code, niet geschat.

### 13.1 Wat de meting liet zien

| Invoer | Uitkomst vóór |
| --- | --- |
| `De vogels vliegen over het weiland` | ❌ `special.criminal` |
| `Het arrest van de Hoge Raad uit 2019` | ❌ `special.criminal` |
| `De diagnose van het probleem is helder` | ❌ `special.health` |
| `Marieke de Vries wordt verdacht van diefstal` | ⚠️ niets |
| `Hauptstraße 12, 10115 Berlin` | ⚠️ niets |
| `Sig. Rossi` | ⚠️ niets |

Drie oorzaken, in volgorde van ernst.

**De matcher was een kale `indexOf`** — geen woordgrens, geen morfologie. Vandaar
`vog` in `vogels`. Microsofts eigen richtlijn voor custom types zegt het
omgekeerde: *"You should always use word unless you need to match parts of words
or words in Asian languages."*

**Het lexicon telde 122 termen over 8 families over 5 talen** — religie negen
termen, seksleven zes. Eén à twee begrippen per taal. En het bevatte de verbogen
vorm `verdachte`, waardoor "wordt verdacht van", de gebruikelijkste formulering
van precies het geval waar artikel 10 over gaat, volledig gemist werd.

**Redactie werkte op trefwoordniveau.** Op een `redact`-slide werd
`Jan had een diagnose bij de huisarts` tot `Jan had een ████████ bij de huisarts`.
Er wordt niets verborgen, "Jan" blijft staan, en de ontvanger concludeert uit het
blok dat daar iets gevoeligs stond. Misleidender dan overbodig.

### 13.2 Het model: twee assen die verschillend werk doen

| | bepaalt |
| --- | --- |
| **persoonskoppeling** op de slide | óf het een persoonsgegeven is → melden ja/nee |
| **term-rol** (indicator / waarde) | hoeveel je weglakt als je redigeert |

Een lexicon-entry:

```
term        de string
category    special.health | special.criminal | … | contact.*
role        indicator | value
lang        nl | en | …
match       word | prefix | compound | notation
weight      specificiteit (zeldzaam = hoog)
source      bundled | user
```

**`role` lost de zinloze redactie op.** "Diagnose" wijst naar een gegeven, `F32.1`
en een parketnummer zíjn het. Een aanwijzing gaat alleen mee als de escalator haar
bereik heeft verbreed tot de hele mededeling. Dit is geen eigen vinding: de
Autoriteit Persoonsgegevens hanteert exact dit onderscheid — *"Gegevens die
hooguit een indicatie geven dat het om een gevoelig kenmerk zou kunnen gaan, zijn
niet voldoende"* om van een rechtstreeks verband te spreken (onderzoek
kinderopvangtoeslag, §3.3.1).

**`match` lost de valse positieven op.** Voor Nederlands is `prefix` met
woordbegin-grens de juiste standaard: de morfologie is vrijwel volledig
suffigerend, dus `verdacht` dekt `verdachte`, `verdachten` en `verdachtmaking`.
Voor DE/NL/SV/DA/FI is een `compound`-modus nodig — decompounding levert in het
Duits gemeten +23% MAP op korte queries.

**`weight` stuurt wat je bundelt.** `Syndroom van Epstein` heeft geen homoniem;
`griep` heeft er tien. Zeldzame ziektenamen gedragen zich als codes. Dat is
dezelfde reden waarom `special.genetic` met dbSNP/HGVS-notatie de enige
art. 9-regel met lage FP-ratio is.

**De persoonskoppelingspoort** heeft juridische dekking én een gemeten
prijskaartje. [C-21/23 *Lindenapotheke*](https://eur-lex.europa.eu/legal-content/NL/TXT/?uri=CELEX:62023CJ0021)
§84: het gegeven werd art. 9 doordat de bestelling *"a link between a medicinal
product … and a natural person identified or identifiable by factors such as that
person's name or the delivery address"* legde. Maar VACCINE (WWW 2019) meet dat
patroondetectie op Enron-e-mail **F1 90,20%** haalt voor *attribuut*detectie ("is
dit een telefoonnummer?") en **F1 48,35%** voor *subject*detectie ("van wíé is dit
nummer?"). Reken op de helft, niet op negentig procent.

### 13.3 Meertaligheid

De interface draait in 30 talen, de detectie in één tot zes per regel. Adres en
BSN-context: alleen NL. Art. 9: vijf talen.

**Niemand lost dit systematisch op.** Microsoft stelt in eigen documentatie:
*"You can't use localized strings to provide different localized versions of a
keyword list or regular expression."* Hun 27 EU-rijbewijstypes delen één blok van
126 Engelse termen met mediaan vier lokale woorden erbovenop, inclusief
knip-en-plakfouten (het Nederlandse lijstje bevat `permis de conduire`). Google
dekt 15 van 27 EU-landen en publiceert zijn contextwoorden niet. AWS Macie
publiceert wél lokale lijsten maar heeft geen BSN, geen PESEL, geen personnummer.

En ML is geen uitweg: zero-shot transfer verliest bij XLM-R gemiddeld 9,3 F1 op de
makkelijke West-Europese talen; op XTREME's NER blijft de kloof ~19–24 punten. Wu
& Dredze tonen dat mBERT onder een corpusdrempel ~6 punten achterblijft bij
niet-neurale baselines — voor kleine talen zijn regels dus de bétere keuze.
Papiaments zit in geen enkel meertalig model en in geen enkele NER-dataset;
Maltees ontbreekt in XLM-R; Fries heeft 0,2 GiB tegenover Bulgaars 57,5 GiB.

**Drie lagen:**

1. **Taalonafhankelijk** draagt het meeste — IBAN mod-97 over 89 landen, Luhn,
   e-mail, IP, secrets, genetische notatie, ICD-codes, nationale nummers met
   checksum. Microsofts INSEE-definitie geeft de ijking: patroon + checksum alleen
   = confidence 75; het trefwoord voegt 10 toe.
2. **Lokale taal + Engels**, niet 30 talen. Dat is wat Microsoft feitelijk doet, en
   het past bij gemengd taalgebruik in zakelijke decks.
3. **Bulk waar het kan** — zie de correctie hieronder: van de bronnen die hier
   stonden is er één gebundeld en één afgevallen. CLDR voor datums en
   naamvolgorde en OpenCage `address-formatting` (MIT, 251 gebieden) voor de
   straat/huisnummer-volgorde staan nog open.

> **Gecorrigeerd bij de bouw (2026-07-19).** Twee claims in de regel hierboven
> hielden geen stand toen ze werden nagemeten.
>
> **"ORDO in 9 talen (16.378 Nederlandse labels)" klopt niet zoals het er stond.**
> ORDO is de OWL-ontologie, en die is **Engelstalig**: versie 4.9 draagt 1179
> `xml:lang="en"`-tags in de eerste 600 kB en geen enkele andere taal, ook niet
> halverwege het bestand. De meertalige gegevens zitten in een ander product van
> dezelfde uitgever — de `product1`-bestanden van Orphadata, met 11.645
> aandoeningen per taal in negen talen. Zelfde bron, zelfde licentie, ander
> artefact. **Dát is nu gebundeld**, gefilterd tot 62.490 namen in de band 10-45
> tekens; zie `tool/build_privacy_lexicon.dart` voor waarom die band.
>
> **EuroVoc: eerst afgewezen, daarna alsnog gebundeld — en de eerste afwijzing
> was fout.** De afwijzing berustte op een *trefwoordzoekopdracht*: zoek
> concepten met "vakbond" of "godsdienst" in het label. Dat leverde "Europees
> Vakbondsinstituut", "Politieke Commissie (73)" en "discriminatie op grond van
> godsdienst" op — instellingsnamen en beleidsbegrippen, waardeloos als
> indicator. Conclusie: ongeschikt.
>
> Die conclusie lag aan de vraag en niet aan de bron. Loop je de **hiërarchie**
> af in plaats van de labels te doorzoeken — alles ónder *godsdienst*, *politieke
> ideologie*, *vakbond* en *etnische groep* — dan komt er iets heel anders boven:
> `islam`, `jodendom`, `katholicisme`, `protestantisme`, `boeddhisme`,
> `atheïsme`, `communisme`, `fascisme`, `liberalisme`, `sociaal-democratie`. Dat
> zijn wél kenmerken van een persoon, en het zijn *waarden* en geen aanwijzingen.
>
> En dan doet EuroVoc waar het goed in is: **27 talen**, waarvan 24 EU-officieel.
> Religie en politiek hadden in de handgeschreven vloer termen in vijf talen.
> Geen andere bron in dit project dicht dat gat in één keer.
>
> Ongeveer een derde van de subboom gaat wél *over* het onderwerp in plaats van
> iemand te beschrijven — `kerk`, `theologie`, `heilige boeken`, `concilie`,
> `Internationale`. Die vijftien concepten zijn uitgesloten op hun **concept-URI**
> en niet op hun Nederlandse naam, zodat één uitsluiting meteen in alle 27 talen
> geldt. Ook eruit: `anglicisme`, want dat betekent in het Nederlands een Engels
> leenwoord en niet het anglicanisme.
>
> **Wat het niet vindt.** EuroVoc levert zelfstandignaamwoorden. "Betrokkene is
> katholiek opgevoed" wordt gemist, want `katholiek` is geen woordvorm van
> `katholicisme` en de bulk matcht op hele woorden. Dat is een eigenschap van een
> thesaurus — die indexeert begrippen, geen woordvormen. Wie die vormen wil, zet
> ze per taal in de vloer.
>
> De drie navraagbronnen (`LEXICON_LICENTIENAVRAAG.md`) blijven daarnaast open;
> Homosaurus zou `special.sexlife` dekken, dat als enige categorie nog uitsluitend
> op de vloer draait.

**De fallback is de kern.** `Deck.language` bestaat al en stuurt de
bevindingssjablonen — maar daar valt een ontbrekende taal terug op Engels. Voor een
lexicon is dat **precies verkeerd**: Poolse tekst scannen met Engelse triggerwoorden
geeft bijna nul recall en niemand merkt het. Het paneel dat nu meldt dát de
privacycontrole uitstaat, moet ook melden dat er voor deze taal geen lexicon is.

**Niet bundelen:** SNOMED CT NL (gratis maar sublicentiehouders moeten
geadministreerd en aan Nictiz overlegd — onverenigbaar met een publieke repo),
ICD-11 (CC BY-**ND**), MeSH-vertalingen (UMLS categorie 3), ATC (NC +
no-modification), LOINC (§4 geen afgeleide werken; §12 draagt vertaalwerk
automatisch over aan Regenstrief).

**Wat bundelen kost ná de eerste keer.** Een gebundeld lexicon is geen
eenmalige import maar een terugkerende beslissing, en die kost meer dan het
regenereren. Bij een referentiecatalogus als CWE is een verouderde regel
*cosmetisch* — er staat een verkeerd nummer in een lijst die de gebruiker leest.
Bij een lexicon **vuurt** elke term. Een nieuwe batch labels kan homoniemen
binnenbrengen (`griep` heeft er tien, `Syndroom van Epstein` geen), en dan gaat
de scanner af op gewone tekst. Een verversing is dus: generator draaien,
**termdiff lezen**, vals-positievencorpus draaien, en oordelen.

Daarom horen deze bronnen **niet** in de blokkerende poort van `make deps-check`
te belanden. ORDO brengt ongeveer maandelijks uit; een CI die daarop rood wordt,
staat binnen twee maanden permanent rood en wordt uitgezet — precies de
zichtbaarheid kwijt die de poort moest opleveren. Ze horen in
`make catalogs-outdated`: adviserend, en het draait vanzelf vóór een
release-build. Dan weet je wat je inpakt zonder dat "er is iets nieuws" als
defect wordt behandeld. Zie `docs/CHECKS.md`.

### 13.4 Pijplijnvolgorde: goedkoop eerst, duur laatst

De controles verschillen orden van grootte in kosten, en de UI hangt aan de
goedkoopste. De volgorde is daarom een ontwerpregel, geen implementatiedetail:

1. **Synchroon, microseconden** — checksums, regexes, contextpoorten. Draait bij
   elke toetsaanslag.
2. **Synchroon, milliseconden** — de trefwoordlexicons en de escalator.
3. **Asynchroon, tientallen tot honderden milliseconden** — de beeldcontrole:
   decoderen plus een neuraal netwerk, per afbeelding. Eigen provider, serieel,
   met een eigen schakelaar.

Stap 3 mag stap 1 nooit ophouden. Het paneel toont de tekstbevindingen zodra ze er
zijn en vult de beeldbevindingen bij zodra die binnen zijn.

### 13.5 De beeldcontrole

Een afbeelding waarop iemand herkenbaar staat, ís een persoonsgegeven — ook zonder
naam erbij. De tekstscanner kan dat per definitie nooit vinden: die leest
`mem:11162735-…`.

**Geen biometrie, en dat met opzet.** De EDPB stelt (Richtsnoeren 3/2019 §74-76)
dat beeld van een persoon pas een art. 9-gegeven wordt als het *"specifically
technically processed in order to contribute to the identification of an
individual"* wordt. Wij stellen aanwezigheid vast, nooit identiteit. Het model
levert per gezicht een kader, vijf landmarks en een score; daarvan blijft **alleen
het aantal** over. Er wordt geen sjabloon berekend, niets opgeslagen, niets
vergeleken. In `image_face_scan_io.dart` staat een expliciete grensmarkering op de
regel waar dat mis zou gaan.

**Motor:** YuNet (OpenCV Zoo, MIT, 232 KB) via `opencv_core` (Apache-2.0). Kosten:
27 MB `DartCvMacOS.framework` in de macOS-bundel, gemeten. Op het web bestaat FFI
niet; daar degradeert de controle en zegt ze dat via `isSupported`.

**Twee dingen die de meting op veertien echte foto's opleverde**, en die allebei
het gedrag vertoonden waar deze controle tegen ontworpen is:

*HEIC meldde nul.* OpenCV kent HEIC niet, `imdecode` geeft een lege matrix, en de
code rapporteerde dat als "geen gezichten". iPhone-foto's zijn standaard HEIC.
`ImageFaceScanResult` scheidt daarom `faces` van `readable`, en een onleesbare
afbeelding levert een eigen informatieve melding op.

*Eén vaste breedte verloor de meeste gezichten.* Per foto verschilt de béste
breedte en geen enkele is overal goed:

```
foto            orig  1920  1280   640
startbaan          0     0     1     0
twee personen      3     3     1     0
portret staand     0     -     -     1
```

Drie schalen met het maximum eroverheen vindt er zes van zeven. De zevende is een
strandfoto waarop iemand omlaag kijkt met een zonnebril op — die hóórt een
gezichtsdetector te missen.

**De scoredrempel bleek de belangrijkste knop, en hij stond bijna op de klif.**
Gemeten op zeven foto's plus elf mensloze app-assets:

```
drempel   gezichten   valse-positieven
   0,95           0                  0
   0,92           8                  0
   0,90          11                  0
   0,85          14                  0
   0,80          14                  0
   0,70          14                  0
   0,60          15                  0
   0,50          15                  2
```

Er stond eerst 0,92, "om zeker te zijn" — drie honderdsten van een detector die
letterlijk niets meer vindt. Tussen 0,85 en 0,70 ligt een vlak gebied zonder
enkele valse positief; 0,80 ligt daar in het midden, dus zo ver mogelijk van
beide kliffen. Op die drempel gaat de groepsfoto van drie naar **acht van acht**
en wordt zelfs de strandfoto gevonden.

Ook gemeten en daarom *niet* gebouwd: extra tussenschalen (960, 480) en
contrastnormalisatie (CLAHE, voor tegenlicht) leverden geen enkel extra gezicht
op. Die complexiteit is niet toegevoegd.

**Redactie haalt de héle mediaverwijzing weg, niet het gedetecteerde gezicht.**
Op een slide die op `redact` staat verdwijnen afbeeldingen, video en audio; de
bestaande placeholder toont een zichtbaar vak, zodat de ontvanger ziet dát er iets
weg is. De bron houdt haar afbeelding — dit raakt alleen wat getoond en
geëxporteerd wordt.

Alleen het gezicht zwart maken zou aantrekkelijker lijken, en is precies de val.
De detector vindt *gezichten* en mist er aantoonbaar; hij leest geen HEIC, ziet
geen tekst in beeld (een gefotografeerd formulier met een BSN erop dus niet), en de
gebruiker mag hem uitzetten. Het resultaat zou een afbeelding zijn die eruitziet
alsof ze is afgehandeld, met een gemist gezicht er nog op — dezelfde fout als het
zwarte blok op "diagnose" dat niets verborg. De afweging uit `statementSpan` geldt
onverkort: *te ruim redigeren is hinderlijk, te krap redigeren is een lek*.

Dat een logo op zo'n slide meesneuvelt is de hinderlijke kant, en bewust gekozen.

Dit repareerde meteen een tweede lek van dezelfde soort. `struct.user_path`
detecteert een gebruikersnaam in een mediapad, en het ontwerp meldde die wel maar
redigeerde hem niet — met als reden dat een pad met blokjes erin een kapotte
verwijzing is. Klopt, maar het gevolg was dat op een `redact`-slide
`/Users/<voornaam.achternaam>/…` letterlijk in de geëxporteerde markdown belandde:
gedetecteerd, gemeld, en vervolgens meegeleverd. Nu verdwijnt de verwijzing als
geheel, dus het pad kán er niet meer in staan.

**Eerlijkheid in de melding.** De detector telt structureel onder en nooit over —
hij vindt gezichten, dus iemand van achteren of met het hoofd buiten de uitsnede
ontbreekt per definitie. De melding zegt daarom "minstens N", en spreekt van
*gezicht* en niet van *persoon*.

*Voorbehoud:* zeven foto's en elf negatieven is een kleine steekproef. Het plateau
is geruststellend, maar dit is geen benchmark.

### 13.6 Fasering

| Fase | Inhoud | Waarom hier |
| --- | --- | --- |
| **9** | Trefwoordbereik nooit redigeren (`PrivacyTermRole`) + matcher met woordgrens en minimumtermlengte | **geleverd.** Geen nieuwe data, geen nieuwe l10n. Verwijdert misleidend gedrag en de grofste FP's |
| **10** | De beeldcontrole: YuNet, eigen provider, eigen schakelaar, `readable`-scheiding, multischaal | **geleverd.** Staat hier en niet later omdat de tekstscanner deze categorie principieel niet kan vinden |
| **11** | Persoonskoppelingspoort vóór elke art. 9-melding | **geleverd.** `contact.name` vuurt nu ook op een persoonspredicaat ("wordt verdacht van", "meldde zich ziek") en op een naam die een e-mailadres bevestigt; label en aanhef stegen van `possible` naar `likely`, want een aanhef is een structurele uitspraak en geen gok. Een naam koppelt bewust **niet** slidebreed maar tot het eind van zijn mededeling — zonder die grens tilde één naam bovenaan een vrij-markdownveld élk trefwoord eronder naar een harde melding, en dat ving de corpustest |
| **12** | `role` + `match` + `weight` als lexicondata in plaats van afgeleid; notatie-uitbreiding (ICD-10, ATC) | **geleverd.** De matchmodus werd afgeleid uit de termlengte (grens: vier tekens), en dat brak twee kanten op: `arrest` is lang genoeg voor de voorvoegselregel maar moet een héél woord zijn (het is ook een uitspraak van de Hoge Raad), en `ziekteverzuim` moet juist middenin een samenstelling gevonden worden — wat de oude matcher helemaal niet kon. Het `weight` doet ook echt werk: staan er meerdere termen van dezelfde familie in één fragment, dan draagt de meest specifieke de melding, niet de eerste in de lijst. `role` komt nu per term uit het lexicon, want binnen één familie komen beide voor: "diagnose" wijst, "diabetes" ís |
| **13** | Taaldekking zichtbaar + regiopakketten werkend + gebundelde lexicons (ORDO nl, EuroVoc) | Zonder de zichtbaarheid liegt een groene balk in 24 talen |
| **14** | Rolonderscheid verdachte/aangever (ConText-mechaniek in Dart, drieweg met *onbekend* als default) | **geleverd.** Het bereik is de mededeling (§5.6) in plaats van een tekenvenster — dezelfde eenheid als de redactie — met terminatiewoorden (`maar`, `terwijl`) die een trigger afkappen. Twee rollen in één mededeling leveren `unknown` op: bij twijfel geen rol. Dat is geen bescheidenheid maar de meting: VACCINE haalt op subjectdetectie F1 48%, tegen 90% op de vraag wát iets is |

### 13.7 Wat hier bewust níét in zit

**Geen NER, geen taalmodel.** Er is geen Nederlandse dependency parser of SRL die
offline in Dart draait. Alpino staat op Prolog uit 2013, Frog is GPLv3 (viraal),
spaCy `nl_core_news_lg` is 568 MB Python. De enige route naar een gelérd model is
een gekwantiseerde ONNX-classifier, en Nederlandse trainingsdata voor misdaadrollen
bestaat niet.

**Geen gehashte woordenlijst.** Overwogen om een diagnoselijst als bloomfilter mee
te leveren zodat hij niet leesbaar in de repo staat. Dat werkt niet: de privacy van
een bloomfilter is precies de min-entropie van de invoerverzameling, en een
diagnoselijst is publiek, opsombaar en klein. Een aanvaller hasht elke
kandidaatterm en toetst lidmaatschap — bij 1% FP herstelt hij 99% van de
verzameling. Een keyed hash helpt niet in een desktop-app, want de sleutel zit in
het binary. De lijst gaat dus gewoon leesbaar mee; het zijn ziektenamen uit een
publieke ontologie en er valt niets te beschermen.

**Geen exacte tellingen beloven.** Er bestaat geen onafhankelijke
accuratessebenchmark voor DLP — Gartner schrapte de Magic Quadrant in 2018 en geen
leverancier publiceert precisie of recall. Ter kalibratie: Presidio haalt op de
Text Anonymization Benchmark **recall 0,46** op directe identificatoren, in het
Engels, de taal waarvoor het gebouwd is. En TAB's menselijke annotatoren maskeerden
gemiddeld 67,9% van de entiteiten met SD 8,3% en 4.299 unieke meningsverschillen:
**er is geen grondwaarheid om naartoe te convergeren.** Dat plafonneert wat elke
classifier kan halen, en het is de reden dat de belofte van dit product — *een
hulpmiddel, geen garantie* — geen bescheidenheidsfiguur is maar de enige uitspraak
die door de meting gedekt wordt.

### 13.8 Open einden

Drie dingen die nog niet in code of documentatie zaten, en die je koud moet kunnen
oppakken zonder de sessie waarin ze ontdekt zijn.

#### Drie licentievragen die fase 13 blokkeren

Voordat er een lexicon gebundeld wordt, moet dit uitgezocht — per bron één e-mail.
De bronnen zijn interessant genoeg om het te vragen, en géén ervan mag mee op basis
van wat er nu bekend is.

**Homosaurus (seksuele geaardheid).** Via het RCE/NDE-endpoint 5.811 SKOS-concepten,
állemaal met een Nederlandse `prefLabel`, plus 3.187 Nederlandse `altLabel`s, actief
onderhouden. Veruit de beste bron voor deze categorie. Maar de licentie is
tegenstrijdig: [homosaurus.org/about](https://homosaurus.org/about) zegt
**CC BY-NC-ND 4.0** (dodelijk voor bundelen), terwijl IHLIA's eigen dataset-metadata
live `dcterms:license → CC BY 4.0` teruggeeft. Plausibel is dat de internationale
redactieraad BY-NC-ND hanteert en IHLIA zijn Nederlandse dataset onder BY 4.0
publiceert. **Niet bundelen op dat triple alleen** — schriftelijke bevestiging vragen
bij IHLIA, via de contactgegevens op hun eigen site. Het triple is sterk genoeg om
dat gesprek mee te openen.

> Terzijde, en leerzaam: hier stond eerst het letterlijke e-mailadres van IHLIA. De
> vals-positievencorpustest sloeg daarop aan — niet op het adres zelf, maar omdat de
> co-occurrence-escalator een e-mailadres als "identificeert een persoon" telt en
> daarmee élk artikel 9-trefwoord in dit document naar `zeker` tilde. In een
> ontwerpdocument over artikel 9 staan die woorden in elke alinea. De controle ving
> dus haar eigen documentatie, en precies zoals bedoeld.

**IISG-religietaxonomieën.** De religietaxonomie telt 288 SKOS-concepten, schoon en
tweetalig; de denominatielijst 3.219, inclusief historische spellingsvarianten maar
vervuild met transcriptie-afval (`!geen<`, kale interpunctie — filter op ≥3 letters).
**Beide datasets declareren geen licentie.** Vragen bij IISG.

**Thesaurus Zorg en Welzijn.** Met ~50.000 Nederlandse termen veruit het rijkste
NL-corpus voor de gezondheidscategorie, SKOS-RDF, sinds 1 januari 2023 beheerd door
Nictiz en kosteloos. Maar de tekst van de bilaterale overeenkomst is nergens
gepubliceerd. Vraag de Nictiz-servicedesk **expliciet** of herdistributie binnen een
open gelicentieerde applicatie is toegestaan — "kosteloos" is niet hetzelfde als
"herdistribueerbaar", en dat onderscheid velt ook SNOMED CT NL (§13.3).

#### Bundelgrootte: winst die nu blijft liggen

**Eerst een correctie op wat hier eerder stond.** De voor de hand liggende
configuratie is `include_modules`, en die doet **niets**. Lees `gen_cmake_vars.dart`
in dartcv4:

```dart
final result = {
  for (final e in defaultModuleSettings.keys)
    e: exclude.contains(e) ? "OFF" : defaultModuleSettings[e]!,
};
```

Alleen `exclude_modules` zet een module uit; `include_modules` dient uitsluitend om
een module tégen uitsluiting te beschermen. Wie `include_modules: [core, imgproc,
…]` opschrijft, krijgt een build die er geconfigureerd uitziet en niets uitsluit.

De juiste vorm is dus omgekeerd — noem wat eruit mág:

```yaml
hooks:
  user_defines:
    dartcv4:
      exclude_modules:
        [calib3d, contrib, features2d, flann, photo, stitching, video, videoio]
```

De standaardwaarden staan in `defaultModuleSettings`: alles hierboven staat AAN,
`freetype` en `highgui` staan al UIT, en `core` is niet configureerbaar. De
beeldcontrole gebruikt `core`, `imgproc` (resize), `imgcodecs` (decode), `objdetect`
(`FaceDetectorYN`) en `dnn` (het model draait door de dnn-module). De acht
hierboven zijn de rest.

**Het werkt alleen op Linux, Windows en Android.** Die drie lopen via
`src/CMakeLists.txt`, dat `dart run dartcv4:gen_cmake_vars` aanroept. macOS en iOS
krijgen een voorgebouwde CocoaPod (`DartCvMacOS` plus de `/dnn`-subspec) waar niets
aan te snoeien valt — daar is 27 MB gemeten en dat blijft zo.

**Niet aangezet, en dat is opzet.** Dit is nooit gemeten: er was geen Linux- of
Windows-machine beschikbaar. En een uitgesloten module houdt zijn Dart-API maar
gooit "symbol not found" bij aanroep — precies het soort stille runtimefout dat deze
codebase elders al twee keer heeft opgeleverd. Blind aanzetten zou die val zelf
zetten.

Het experiment, in volgorde, op een Linux- of Windows-machine:

1. `flutter build linux` zonder het blok, en meet `build/linux/*/*/bundle/lib/libdartcv.so`;
2. voeg het blok toe, `flutter clean`, opnieuw bouwen, opnieuw meten;
3. **verifieer dat de detector nog werkt** — bouwen is niet genoeg, want de fout
   valt pas bij aanroep. Draai `flutter test test/image_face_scan_test.dart` met
   `DARTCV_LIB_PATH` naar de nieuwe `.so`; de kattenfoto's moeten nul geven en
   `isSupported` moet waar zijn;
4. zakt er iets om, dan is de kortste weg één module tegelijk terugzetten —
   `dnn` en `objdetect` hebben interne afhankelijkheden die niet gedocumenteerd zijn.

#### De detectietests en de platformdekking

De Makefile vindt de OpenCV-bibliotheek zelf zodra er een platformbuild in `build/`
staat (zie CHECKS.md). De CI bouwt inmiddels op alle drie de desktopplatforms —
Linux in de gate, macOS en Windows in de matrix — zodat de detectietests daar echt
draaien in plaats van zichzelf over te slaan.

Wat daarmee nog niet is aangetoond: **alleen macOS is door een mens gedraaid gezien.**
`opencv_core` declareert `ffiPlugin: true` voor android/ios/linux/macos/windows en de
voorwaardelijke import kiest op elk native platform de echte implementatie, maar de
Linux- en Windows-paden in de Makefile en de CI zijn op patroon geschreven en niet op
een draaiende build geverifieerd. De eerste CI-run op die takken is dus tegelijk het
bewijs — en faalt hard als een pad niet klopt, in plaats van stil terug te vallen op
overslaan.

Android en iOS zijn geen leverplatform: de release-workflow bouwt web, macOS, Windows
en Linux. De mappen bestaan, het product niet.

---

## 14. Onderzoeksdossier: DLP-technieken en wat ervan gemeten is

Deze sectie is een **annex, geen ontwerp**. §13 bevat de beslissingen; hier staat
het materiaal waarop ze rusten, zodat een volgende sessie niet opnieuw hoeft te
zoeken. Alles is nagelopen tot de primaire bron; waar dat niet lukte staat het
erbij.

Eén ding vooraf, want het kleurt de rest: **er bestaat geen onafhankelijke
accuratessebenchmark voor enterprise-DLP.** Gartner schrapte de Magic Quadrant in
2018, NSS Labs heeft DLP nooit getest, en geen enkele leverancier publiceert
precisie of recall voor zijn detectoren. De reden staat in de literatuur zelf: de
producten zijn zwarte dozen (Katz et al. §4.2) en bedrijven geven hun
vertrouwelijke corpora niet vrij (Hart et al. §6). Elk rondzingend
FP-percentage is dus een leverancierclaim.

### 14.1 Wat de leveranciers werkelijk doen

| | Purview | Google SDP | Macie | Presidio |
| --- | --- | --- | --- | --- |
| Detectoren | 325 SIT's | 260 infoTypes | 162 MDI's | 81 entiteiten / 74 recognizers |
| Landspecifiek | 249 (62 landen + EU) | 126 (50 landen) | ~141 (67 prefixen, 51 alleen IBAN) | 60 (18 landen) |
| EU-27 nationale ID | alle 27 | 15 van 27 | 10 landen (géén NL/PL/SE) | 8 landen |
| Trefwoorden gelokaliseerd? | **inconsistent** — mediaan 4 lokale termen bovenop één gedeeld blok van 126 Engelse | **niet gepubliceerd** | **ja**, per land in de lokale taal | Engels standaard; schrijf je zelf |

**Niemand lost meertaligheid systematisch op.** Microsoft stelt het expliciet in
eigen documentatie: *"You can't use localized strings to provide different
localized versions of a keyword list or regular expression."* Hun 27
EU-rijbewijstypes delen datzelfde Engelse blok, met zichtbare knip-en-plakfouten:
het Nederlandse lijstje bevat `permis de conduire`, het Zweedse bevat Fins.
Purview's trainable classifiers zijn bovendien **Engels-only**.

**De ijking die je wilt overnemen** komt uit Microsofts Franse INSEE-definitie:

```xml
<Entity patternsProximity="300" recommendedConfidence="75">
  <Pattern confidenceLevel="75">   <!-- patroon + checksum, géén trefwoord -->
  <Pattern confidenceLevel="85">   <!-- patroon + checksum + trefwoord binnen 300 tekens -->
```

De checksum draagt al 75; het taalsignaal voegt 10 toe. Precies de verhouding die
een 30-talenproduct nodig heeft. Let op: `patternsProximity` is **±N tekens** rond
de match, dus 300 betekent een venster van 600 breed.

**Nabijheidsvensters lopen ver uiteen** — Purview 300 (±), Macie **30** voor
managed identifiers (en asymmetrisch: het trefwoord moet vóór de match staan;
custom is default 50, bereik 1-300), Google maximaal 1000 totaal, Presidio 5
wóórden ervoor en 0 erna. OciDeck zit met `kContextWindow = 40` dicht bij Macie.

**Purview rékent niet.** De waarden 65/75/85 zijn volgens Microsofts eigen
PowerShell-referentie *"a unique ID for each pattern in an entity"* — met de hand
toegekende labels, geen som en geen Bayes. Bij creditcards is het Luhn alleen = 65,
Luhn + context = 85; er is geen 75-trede. Dat is bevrijdend: OciDeck's drie
zekerheidsniveaus zijn hetzelfde soort ding, geen simpelere versie van iets
geavanceerders.

**Presidio is het enige systeem waar je de rekensom kunt lézen:** regex geeft 0,3;
de Luhn-validator is een **harde override naar 1,0 of 0,0**, geen weging;
context-boost is +0,35 additief met ondergrens 0,4.

### 14.2 De technieken, en wat ze kosten

**Exact Data Matching (EDM).** Je indexeert een echte brontabel als gehashte
waarden en matcht daartegen. Purview: 100 miljoen rijen, 32 kolommen, max 10
doorzoekbaar, 5 uploads per 24 uur. Hashing gebeurt met een salt, maar **het
algoritme en de saltlengte staan nergens in de publieke documentatie** — wie
schrijft dat Purview SHA-256 gebruikt, citeert iets wat Microsoft niet publiceert.

De architectonisch belangrijkste beperking: een primair element *moet* al vindbaar
zijn via een bestaande SIT met een detecteerbaar patroon. Vrije-tekstvelden (namen,
adressen) kunnen géén primair element zijn. **EDM is dus geen zelfstandige exacte
matcher maar een corroboratielaag over patroonmatching** — het kan de FP-ratio
nooit onder de kandidatenset van de onderliggende regex duwen.

Symantec publiceert wél harde cijfers: **+3 bytes per cel** boven 500 miljoen
cellen (4 bytes voor CJK), tijdelijke index ≈ `rijen × kolommen × 25` bytes, tot 6
miljard cellen. En een FN-bron om te onthouden: *"by default, EDM scans only the
first 30.000 tokens"*.

**Document fingerprinting.** Purview: partiële match instelbaar op **30–90%** van
de tekst, bestand max 4 MB, template 256–204.800 tekens, ~100 fingerprints per
tenant. Blinde vlekken: wachtwoordbeveiligde bestanden, beeld-only bestanden,
ingesloten documenten. Symantec IDM is algoritmisch openhartiger: *"uses a rolling
hash algorithm"* (Rabin-Karp) plus *"a selection method … not all text is hashed"*
(de winnowing-familie), minimaal 50 genormaliseerde tekens voor exacte en 300 voor
partiële match.

Winnowing zelf (Schleimer, Wilkerson & Aiken, SIGMOD 2003) heeft een nette
garantie: venster `w = t − k + 1`, dichtheid `2/(w+1)`, ondergrens voor élk lokaal
algoritme `1,5/(w+1)` — dus binnen 33% van optimaal. Het overtuigendste empirische
resultaat is negatief: op 500.000 HTML-pagina's liet de naïeve "0 mod p"-selectie
een aaneengesloten stuk van **29.983 tekens zonder enkele vingerafdruk**.

**Checksums.** Wiskundige eigenschappen, geen metingen — en **geen enkele studie
kwantificeert de FP-reductie van checksums in DLP**:

| Validator | P(willekeurig passeert) |
| --- | --- |
| Elfproef / BSN | ≈ 1/11 = 9,1 % |
| Luhn | 1/10 = 10 % |
| IBAN mod-97 | ≈ 1/97 = 1,03 % |

Het ontwerpprincipe dat eruit volgt is de **asymmetrie**: een gefaalde checksum is
bijna sluitend bewijs van géén match, een geslaagde is zwak bewijs vóór. En:
**formaatbeperkingen leveren vaak méér precisie dan de checksum zelf** — IBAN's
landcode plus vaste lengte per land is sterker dan de mod-97, en creditcard-IIN's
beperken de eerste zes cijfers, wat meer waard is dan één controlecijfer. Voor
uitbreiding naar EU-nummers betekent dat: investeer eerst in de formaattabel.

**Entropie voor secrets — het oordeel staat op zijn kop.** truffleHog's drempels
zijn 4,5 bits base64 en 3,0 hex (beide 75% van het theoretisch maximum; geverifieerd
in de broncode). Het gangbare verhaal is dat entropie ruis oplevert. Meli et al.
(NDSS 2019) maten het tegenovergestelde: entropie vond het merendeel van de
secrets, en overstappen op alleen regex zou de recall van 25% naar 19% hebben
gedrukt. Het probleem van entropie is **precisie, niet recall** — Basak et al.
geven het mooiste bewijs: `ThisIsAReallyLongString` scoort entropie **4,11**, een
echte sleutel **4,08**.

**Bloomfilters.** Zie §13.7 voor waarom ze hier niet kunnen. De wiskunde voor het
geval je ze elders overweegt: `m/n ≈ 1,44·log₂(1/ε)`, optimaal `k = (m/n)·ln 2` —
9,6 bits per element voor 1% FP, 14,4 voor 0,1%. Elke factor 10 minder FP kost
~4,8 bits. **Geen enkele commerciële DLP-leverancier documenteert het gebruik
ervan**; in onderzoek wel (Shu, Yao & Bertino, IEEE TIFS 2015), en daar zijn
botsingen juist een *feature*.

**OCR.** Purview is gemeterd, niet gelicentieerd: elke PDF-pagina telt als een
aparte scan. Limieten: 20 MB (Exchange/Teams), 50 MB (SharePoint/endpoints), eerste
2 miljoen tekens, 1.024 MB per apparaat per dag. Blinde vlek die telt: *"Only
images uploaded after OCR is enabled are scanned"* — geen terugwerkende scan.
Netskope is het eerlijkst over de grens: *"English is the only supported language
for extraction with OCR"*. **Geen enkele leverancier publiceert een
OCR-accuratessecijfer.**

### 14.3 Wat er werkelijk gemeten is

De peer-reviewed cijfers, met hun voorbehouden.

| Meting | Uitkomst | Bron |
| --- | --- | --- |
| Regex: *attribuut*detectie (is dit een telefoonnummer?) | **F1 90,20%** | VACCINE, WWW 2019, Enron |
| Regex: *subject*detectie (van wíé is dit nummer?) | **F1 48,35%** | idem |
| Presidio, recall directe identificatoren | **0,46** | TAB, Computational Linguistics 48(4) |
| Presidio + ORG: recall +0,003, precisie **−0,219** | 0,761 → 0,542 | idem |
| Google Cloud DLP / Presidio op echte tabellen | F1 **0,576** / **0,565** | Telkamp & Hulsebos 2025 |
| Acht PII-systemen, cross-domein | span-F1 **< 0,14** | PIIBench (preprint) |
| Regex-precisie op sleutels | **3,62%** (NER: 60%) | StarPII / BigCode, TMLR 2023 |
| Gebruikersnamen, beste model | F1 **61,5%** | idem |
| Fingerprinting, ingebedde passages | max **90%**, na naïeve synoniemvervanging **~65%** | CoBAn, Information Sciences 262 |
| Naïeve classifier op niet-bedrijfstekst | FP tot **87,2%** | Hart et al., PETS 2011 |
| Vijf van negen secret-scanners | precisie **< 7%** | Basak et al., ESEM 2023 |
| Korte termen (1–2 tekens) | 2.044 termen → **~1,9 miljard** valse MEDLINE-matches | Hettne et al., J Biomed Semantics 2010 |

Twee cijfers verdienen extra aandacht.

**VACCINE's 90,20 versus 48,35** is de meting die de persoonskoppelingspoort
(§13.2) zowel rechtvaardigt als tempert: het patroon is het makkelijke deel, de
koppeling aan een persoon het moeilijke — en juist die bepaalt of iets een lek is.
Reken op de helft, niet op negentig procent.

**Hart's mooie cijfers rusten op een aanname.** De false-discovery-rate van 0,47%
geldt bij een verondersteld verkeer van *25% vertrouwelijke documenten*. In een echt
netwerk ligt die basisfrequentie ordes van grootte lager, en FDR verslechtert daar
recht evenredig mee.

**En er is geen grondwaarheid.** TAB's menselijke annotatoren maskeerden gemiddeld
**67,9%** van de entiteiten met SD **8,3%** en **4.299** unieke meningsverschillen
(waarvan 4.062 over quasi-identificator versus niet-maskeren). Getrainde
annotatoren, één taal, één domein, expliciete richtlijnen — en ze komen niet tot
overeenstemming. Dat plafonneert wat élke classifier kan halen.

**"Vals positief" is als begrip zelfs betwist.** Alahmadi et al. (USENIX Security
2022) tonen dat het rondzingende "99% van DLP-alerts is vals positief" een citaat
van één analist is, geen meting. Hun werkelijke bevinding: het merendeel zijn
**benign triggers** — technisch correcte treffers die de organisatie bewust
negeert. Dat is precies wat de acceptatie-badge modelleert.

### 14.4 Bronnen voor lexicons, met licentiestatus

**Bundelen kan:** ORDO 4.9 (CC BY 4.0, **16.378 Nederlandse labels** + 30.662
synoniemen — de enige bron met eersteklas NL-editie), DOID (CC0), MONDO (CC BY
4.0), Wikidata (CC0), EuroVoc (24 EU-talen incl. MT en GA), IATE, HGNC (CC0), CBS
Standaardclassificatie Misdrijven (75 categorieën, CC BY 4.0), **RvIG BRP Tabel 32**
(217 rijen in de *adjectivische* vorm — `Marokkaanse`, `Syrische` — precies wat je
in lopende tekst tegenkomt), Wetboek van Strafrecht XML (CC0), OpenCage
`address-formatting` (MIT, 251 gebieden, encodeert de straat/huisnummer-vólgorde
die per land verschilt), CLDR (datums, naamvolgorde), RxNorm *Current Prescribable*
alleen.

**Bundelen kan niet:** SNOMED CT NL (gratis, maar sublicentiehouders moeten
geadministreerd en op verzoek aan Nictiz overlegd), ICD-11 (CC BY-**ND**: verbatim
mag, een lexicon eruit afleiden niet), MeSH-vertalingen (UMLS categorie 3), ATC
(NC + no-modification), G-Standaard, LOINC (§4 geen afgeleide werken; **§12 draagt
vertaalwerk automatisch over aan Regenstrief** — onwerkbaar in een repo waar
bijdragers forken).

**Nog uit te zoeken:** zie §13.8.

**Gat zonder oplossing:** vakbondslidmaatschap. Er is geen open vakbondenregister;
het KvK-open-bestand dekt alleen BV's en NV's, en vakbonden zijn verenigingen.
Realistisch honderd entries met de hand.

### 14.5 Meertaligheid en rolonderscheid: wat niet bestaat

**Er is geen erkende meertalige PII-benchmark voor de EU-talen.** TAB is Engels,
de Kaggle-set Engels, n2c2 Engels, MEDDOCAN Spaans en klinisch, ai4privacy zes
talen en synthetisch, MultiCoNER twaalf talen maar generieke NER. De claim
"detecteert persoonsgegevens in 30 talen" is door niemand te valideren.

**ML is geen uitweg voor kleine talen.** Zero-shot transfer verliest bij XLM-R
gemiddeld 9,3 F1 op de makkelijke West-Europese talen; XTREME's NER-kloof blijft
~19–24 punten; MasakhaNER 2.0 meet een instorting van ~30 punten. En Wu & Dredze
tonen dat mBERT onder een corpusdrempel **~6 punten achterblijft bij niet-neurale
baselines** — voor kleine talen zijn regels dus de bétere keuze, niet de armoedige.
Papiaments zit in geen enkel meertalig model en in geen enkele NER-dataset;
Maltees ontbreekt in XLM-R; Fries heeft 0,2 GiB CC-100 tegenover Bulgaars 57,5.

**Rolonderscheid (fase 14).** ConText (Harkema et al. 2009) levert de mechaniek:
cue + scope + terminatie + pseudo-triggers, zonder parser of model. ContextD
(Afzal et al., BMC Bioinformatics 2014, CC-BY) is de Nederlandse port, 509
triggers. **Maar geloof het cijfer niet dat je zult tegenkomen:** de gerapporteerde
experiencer-F van 0,99–1,00 is gemeten met *Patient* als positieve klasse op een
verdeling waar 'Other' 0,1–2% is — de triviale baseline. De prestatie op de
zeldzame rol-flip is nooit apart gerapporteerd, en in het hele corpus vuurden 10
unieke 'other'-triggers waarvan `moeder` de frequentste. Het is een
familielid-lexicon, geen redenering over argumentstructuur.

Ter kalibratie voor wat handgebouwde patronen halen: XARA (regelgebaseerde SRL,
Nederlands) haalt **F1 53,80** tegen 70,43 voor een getrainde classifier, en het
beste vergelijkbare frame-patroonwerk (slachtofferherkenning in Portugese
dossiers) rapporteert precisie **0,726** — en recall niet.

**Offline in Dart kan het niet met een parser.** Alpino draait op SICStus 3 of
SWI-Prolog 6.6.4 (2013), Frog is **GPLv3** (viraal), spaCy `nl_core_news_lg` is
568 MB Python, Stanza wil PyTorch. Er bestaat geen Dart-native Nederlandse
dependency parser of SRL. De enige route naar een gelérd model is een
gekwantiseerde ONNX-classifier via `dart:ffi` — en Nederlandse trainingsdata voor
misdaadrollen bestaat niet.

### 14.6 Wat marketing is, expliciet

Zodat niemand het per ongeluk citeert:

* **"51% van DLP-alerts is vals positief"** en **"legacy-DLP gemiddeld 35%, soms
  90%"** — zelfgerapporteerde enquêtes van een leverancier die het middel verkoopt.
* **"99% vals positief"** — één analist in een interview, geen meting.
* **Microsoft "fewer false positives"** voor EDM, **Symantec "much more reliable"**
  voor partial matching — onfalsifieerbaar.
* **Nightfall's "Possible 40%+, Likely 60%+, Very Likely 80%+"** — ordinale labels
  in procentkleding, nergens een kalibratiestudie.
* Elke leveranciers-whitepaper waarin de opdrachtgever wint.

### 14.7 Waar je verder leest

Techniek en evaluatie: Hart, Manadhata & Johnson (PETS 2011); Katz, Elovici &
Shapira, *CoBAn* (Information Sciences 262, 2014); Shvartzshnaider et al.,
*VACCINE* (WWW 2019); Pilán et al., *Text Anonymization Benchmark* (Computational
Linguistics 48(4), 2022); Meli, McNiece & Reaves (NDSS 2019); Basak et al. (ESEM
2023); Alneyadi, Sithirasenan & Muthukkumarasamy (JNCA 62, 2016).

Meertaligheid: XLM-R (arXiv 1911.02116); XTREME (arXiv 2003.11080); MasakhaNER 2.0
(EMNLP 2022); Wu & Dredze (RepL4NLP 2020); ELE-project en de DLE-metriek; MAPA
(CEF, 24 EU-talen, code Apache-2.0 maar dormant, datasets op ELRC-SHARE).

Rolonderscheid: Harkema et al. (J Biomed Inform 2009); Afzal et al. (BMC
Bioinformatics 2014); van Es et al. (BMC Bioinformatics 2023); medspaCy; Open Dutch
FrameNet; `vmenger/docdeid` (MIT — de architectuurreferentie; DEDUCE zelf is
GPL-3.0).

Juridisch: HvJ C-184/20 (*OT*), C-252/21 (*Meta*), C-21/23 (*Lindenapotheke*),
C-446/21 (*Schrems*); WP29 WP136 (het inhoud/doel/resultaat-criterium); EDPB
Richtsnoeren 8/2020 §8.1.2 en 3/2019 §62-76; AP-onderzoeken kinderopvangtoeslag
(z2018-22445) en FSV (z2020-04615).
