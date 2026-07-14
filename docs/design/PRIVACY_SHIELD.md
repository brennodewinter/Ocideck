# OciDeck — Privacy Shield (ontwerp)

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

| Pad | Rol |
| --- | --- |
| `lib/models/privacy_finding.dart` | `PrivacyFinding`, `PrivacyFamily`, `PrivacyConfidence`, `PrivacyDisposition`, `PrivacyScanResult` |
| `lib/services/privacy/privacy_scanner.dart` | Orkestratie: velden verzamelen, prefilter, regels draaien, allowlist toepassen, co-occurrence-escalatie |
| `lib/services/privacy/privacy_rule.dart` | `PrivacyRule`-descriptor (data-driven: id, familie, regex, validator, confidence, contextwoorden, regio) |
| `lib/services/privacy/rules_identifiers_nl.dart` | BSN, V-nummer, A-nummer, BIG, AGB, KvK, btw-id, parketnummer, kenteken, postcode |
| `lib/services/privacy/rules_identifiers_eu.dart` | BE/DE/FR/ES/PT/IT/PL/SE/NO/DK/FI/GR/IE/HR/CZ/SK/HU/BG/RO/SI/EE/LV/LT/AT/CH/MT/CY/LU |
| `lib/services/privacy/rules_identifiers_world.dart` | US/UK/CA/AU/IN/BR/ZA/CW/AW |
| `lib/services/privacy/rules_financial.dart` | IBAN, PAN, BIC, SEPA-mandaat, crypto |
| `lib/services/privacy/rules_contact.dart` | E-mail, telefoon, adres, postcode, geboortedatum, coördinaten |
| `lib/services/privacy/rules_digital.dart` | IP, MAC, IMEI, ICCID, UUID, handles, device-ID |
| `lib/services/privacy/rules_secrets.dart` | API-keys, tokens, PEM, connection strings, wachtwoorden, entropie |
| `lib/services/privacy/rules_special.dart` | Gezondheid, strafrecht, religie, politiek, vakbond, etniciteit, biometrie, genetica |
| `lib/services/privacy/rules_structural.dart` | Gebruikerspaden, URL-tokens, share-links, mailto, data-URI, remote media, doorhaling-als-redactie |
| `lib/services/privacy/privacy_checksums.dart` | 11-proef, mod-97, Luhn, Verhoeff, ISO 7064, MRZ, base58check, bech32, EIP-55 |
| `lib/services/privacy/privacy_allowlist.dart` | Testwaarden, gereserveerde reeksen, placeholder-personen, eigen identiteit |
| `lib/services/privacy/privacy_lexicon.dart` | Meertalige contextwoorden (laadt `assets/privacy/lexicon_<lang>.json`) |
| `lib/models/audience_deck.dart` | `AudienceDeck` — deck ná de privacyprojectie, met een private constructor. Het enige type dat de ontvangende oppervlakken accepteren (§6.0) |
| `lib/services/privacy/privacy_projection.dart` | **De grens.** `forAudience()` en `forExternalProcessing()`: bron-`Deck` → `AudienceDeck` met de gevoelige substrings al vervangen |
| `lib/services/privacy/privacy_export_policy.dart` | Export-gate, spiegelt `ClassificationEnforcementPolicy` |
| `lib/state/privacy_provider.dart` | Riverpod: scanner-config uit settings, gememoiseerde deck-scan |
| `lib/l10n/privacy_localization.dart` | Regel-labels, familie-labels, meldingteksten, uitleg |
| `lib/widgets/panels/privacy_disposition_control.dart` | Per-slide dropdown (accepteren / shield / redigeren), naast `_SlideTlpControl` |
| `assets/privacy/lexicon_*.json` | Contextwoordenlijsten per taal (géén l10n-strings: dit is data, geen UI) |

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
| `doc.mrz` | Machine-readable zone van paspoort/ID (TD1/TD2/TD3) | Twee of drie regels van 30/36/44 tekens, `P<` + ISO-3166-landcode, plus de mod-7-3-1-controlecijfers over documentnummer, geboortedatum, vervaldatum en het samengestelde cijfer. **Bijna nul FP's** en het is meteen `error`: een MRZ in een slide is een gescande identiteitskaart. | zeker | ✓ |
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
| `contact.phone` | Telefoonnummer | E.164 (`+CC…`) óf nationaal formaat van een actief regiopakket, met een plausibele lengte per land. **Uitgesloten:** versienummers (voorafgegaan door `v`), CVE-ids, bedragen (valutateken in de buurt), jaartallen, tijdstippen, ISBN's, en de gereserveerde "drama"-reeksen (US `555-01xx`, UK `07700 900xxx` / `020 7946 0xxx`, DE `+49 30 23125 xx`) | waarschijnlijk | ✓ |
| `contact.address` | Straat + huisnummer | straatnaampatroon + huisnummer + (postcode óf plaatsnaam) | mogelijk | ◐ |
| `contact.postcode_nl` | NL-postcode | `\d{4}\s?[A-Z]{2}`, met de verboden lettercombinaties SA/SD/SS eruit. **Postcode + huisnummer is in Nederland vrijwel uniek identificerend** → escaleert naar `warning` zodra beide op dezelfde slide staan | waarschijnlijk | ◐ |
| `contact.postcode_intl` | Postcodes per land | DE/FR/BE/PL/UK/US/CA-formaten binnen het regiopakket | mogelijk | ◐ |
| `contact.birthdate` | Geboortedatum | datum + contextwoord (`geboren`, `geb.`, `dob`, `geboortedatum`, `°`, `*`) óf een datum in een tabelkolom met kop "geboortedatum" | waarschijnlijk | ✓ |
| `contact.name` | Persoonsnaam | Zie §5.5 — bewust géén NER. Alleen: aanhef (`dhr.`, `mevr.`, `Herr`, `Sra.`, `Dr.`), naamlabel (`naam:`, `contactpersoon:`, `auteur:`), of een tabelkolom met een naamkop. Placeholder-personen uitgesloten (`Jan Jansen`, `John Doe`, `Max Mustermann`, `Mario Rossi`, `Jean Dupont`, …) | mogelijk | ✓ |
| `contact.geo` | Coördinaten | lat/lon-paar in plausibel bereik, `geo:`-URI, plus-code, what3words. Uitgesloten wanneer het een grafiek-as of een chart-dataset is | waarschijnlijk | ✓ |
| `contact.plate` | Kenteken | NL-sidecodes met de juiste letteruitsluitingen; overige landen binnen het regiopakket. Contextwoord aanbevolen (`kenteken`, `nummerbord`) omdat `XX-99-99` ook een artikelcode kan zijn | mogelijk | ◐ |

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

Voor een gewoon deck dat niets met de secmodule te maken heeft, blijft dit simpel: twee
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

Een `_PrivacyShieldOverlay` naast de bestaande `_TlpOverlay` in
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
| `privacyFamilies` | set van 8 familieschakelaars | alle aan |
| `privacyDisabledRules` | set van regel-id's | leeg |
| `privacyRegions` | set van landpakketten | **heel Europa** (EU-27 + EER + CH + UK) |
| `privacyStrictSeverity` | bool — behandel `zeker` als fout i.p.v. waarschuwing | uit |
| `privacyExportGate` | uit / waarschuwen / blokkeren | waarschuwen |
| `privacyRedactionStyle` | blokken (`████`) / label (`[BSN]`) | blokken |
| `privacyOwnIdentity` | vrije lijst: naam, e-mail, telefoon, domein | leeg |
| `privacyShieldWatermark` | bool | uit |
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
| `docs/design/PRIVACY_SHIELD.md` | Dit document. Design-docs vormen een eigen klasse in `docs_registration_test.dart`, maar worden nog steeds gecontroleerd: het bestand moet als asset in `pubspec.yaml` staan **en** een `_docTile` krijgen in `settings_dialog_docs.dart`, met een titel die in alle 31 talen vertaald is |
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
> **De controle is een hulpmiddel, geen garantie.** OciDeck vindt niet alles: tekst in
> afbeeldingen, gegevens in gelinkte bestanden en gevoelige informatie zonder herkenbaar patroon
> blijven buiten beeld. Een dia zonder meldingen is een dia waarin *wij* niets hebben gevonden —
> niet een dia waarvan vaststaat dat er niets in zit. De eindverantwoordelijkheid voor wat je
> deelt, blijft bij jou.

Die laatste alinea is niet optioneel. Zonder dat voorbehoud gaat iemand de groene balk lezen als
een vrijwaring, en dan hebben we een privacyfeature gebouwd die het probleem verergert.

### 12.3 Consequenties voor de toestemmingspoort

`PrivacyStatementContent` wordt óók getoond in `consent_dialog.dart:95`, vóór het eerste gebruik.
De nieuwe sectie verlengt die poort. Dat is aanvaardbaar — het is precies de informatie die iemand
vóór gebruik moet hebben — maar de tekst moet daarom kort en in gewone taal blijven, en de
technische details (commitments, salts, manifest) horen in `docs/USER_GUIDE.md`, niet in de poort.
De copy hierboven is met dat onderscheid geschreven.

Alle nieuwe copy gaat door `l10n.d()` en moet dus in alle 30 niet-Nederlandse talen vertaald
worden (`make add-l10n SPEC=…`). Dit is lopende tekst, geen acroniem: hier valt niets in de
`unchanged`-lijst weg te schrijven.
