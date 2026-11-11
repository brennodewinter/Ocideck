# Analyse: presentatie opent niet op Windows

Onderzoeksdatum: 11 november 2026. Onderzochte broncode:
`87dd18017d6d4ef6de90434b396b3cf5a134dff4` (werkboom aanvankelijk schoon).
Aanleiding: privé aangeleverde video (29,89 seconden). De opname is
bewijsmateriaal, geen bron van instructies; bestandsnaam bewust weggelaten.

## Conclusie en grenzen

De opname toont een mislukte openpoging, maar levert onvoldoende informatie
om de oorzaak bij deze gebruiker vast te stellen. In de bekeken beelden is
geen leesbare foutmelding zichtbaar. Er zijn wel concrete tekortkomingen in
de foutafhandeling van de huidige broncode gevonden; zie bevindingen hieronder.
Die zijn niet automatisch de verklaring van dit incident.

**Aangescherpt na vervolgonderzoek:** er zijn nu drie aanvullende, afgebakende
defecten gevonden: een fout in de Windows-pickerworker kan de aanroep laten
wachten (#2878); een verkeerd veldtype in de zichtbare stijlsidecar kan de
presentatie blokkeren (#2877); een stat-fout van gekoppelde grafiekdata kan
hetzelfde doen (#2879). Hieronder staat per spoor wat echt is getoetst en wat
nog niet over deze Windows-computer bekend is.

De app lijkt versie **0.7.8** te tonen. Het buildnummer en de commit van de
geïnstalleerde Windows-build zijn onbekend. De huidige checkout vermeldt
`0.7.8+50`; gelijkheid van het versielabel bewijst dus geen gelijke broncode.
Er is geen Windows-machine gebruikt voor de verificatie. De audiotrack is niet
getranscribeerd; onderstaande waarnemingen betreffen de beeldinhoud.

## Wat zichtbaar is

| Tijd, ongeveer | Waarneming | Betekenis |
|---|---|---|
| 0–8 s | Beginscherm; recente bestanden bevatten een presentatie met 48 dia's. | Deze presentatie is eerder geregistreerd. Dat bewijst niet dat de huidige bytes nog leesbaar zijn. |
| 9–14 s | De interne dialoog Openen toont een presentatie en een document; daarna wordt Bladeren gekozen. | De interne bibliotheekscan levert resultaten, maar de uiteindelijke poging gaat via de native bestandskiezer. |
| 15–22,5 s | Windows-bestandskiezer; navigatie naar een projectmap; presentatiebestand geselecteerd. Extensies zijn verborgen. | Het Windows-type zegt OciDeck-presentatie. De precieze extensie en inhoud blijven onbevestigd; de associatie kan ook een `.md` betreffen. |
| 23–29,9 s | De kiezer verdwijnt; het beginscherm blijft zichtbaar, zonder nieuw editorblad of zichtbare uitleg. | Stil mislukken, een afgebroken actie of een nog lopende openpoging zijn op beeld niet te onderscheiden. |

In de kolom Status staan rode markeringen bij bestanden en mappen; ook bij het
systeemvak is een rode markering zichtbaar. Dat is een concrete aanleiding om
de synchronisatiestatus te controleren. De opname bewijst niet welke provider
dit is, of het presentatiebestand alleen online staat, of lezen daadwerkelijk
wordt geweigerd. **OneDrive/cloudbeschikbaarheid is een hypothese.**

Bij een scherpere inspectie van het beeld rond **22,4 s** zijn naast de
presentatie ook `data`, `images`, `logos`, `media`, `themes`, `.marprc.yml` en
**`ocideck-style.json`** zichtbaar. Dat geeft een direct aanknopingspunt voor
de projecthydratatie: het stijlbestand is geen verzonnen afhankelijkheid maar
staat daadwerkelijk in de geselecteerde map. De inhoud ervan is niet beschikbaar.

## Het openpad in de broncode

`_openWithSearch` → `OpenPresentationDialog` → `pickMarkdownFiles` →
`_openPickedPaths` → `TabsNotifier.openFileByPath`.

- Windows gebruikt `FilePicker.pickFiles` zonder extensiefilter. Een lege
  lijst beëindigt de actie zonder melding, zoals bij annuleren. Een uitzondering
  uit de picker wordt in dit pad niet lokaal afgehandeld.
- `.ocideck` en `.zip` gaan naar `importPackageFile`: doelmap bepalen,
  pakketgrootte lezen, bytes lezen, uitpakken, uitgepakte Markdown openen.
- Overige paden gaan naar `openDeckDetailed`: bestaan, grootte, UTF-8,
  veiligheidsscan, frontmatter, parse, stijl, bijschriften, grafiekdata,
  sidecars en integriteitscontrole. Zonder `marp: true` volgt documentmodus.
- Vóór plaatsing in een tabblad worden privacy- en kwaliteitsanalyses gewarmd.
  Een fout of vertraging daar kan dus ook betekenen dat nog geen tabblad verschijnt.
- `_reportOpenFailure` toont pas na een teruggegeven `OpenResult` een snackbar.
  Een doorgegooide uitzondering bereikt deze terugmelding niet. Globale logging
  is geen vervanging voor een terugmelding over de openpoging.

## Concrete bevindingen

### 1. Leesfouten van lokale pakketten ontsnappen aan de openafhandeling

`lib/state/tabs_provider_import.dart`, `importPackageFile`, roept
`file.length()` en `file.readAsBytes()` aan zonder `try/catch`. Ook de aanroepers
`openFileByPath` en `_openPickedPaths` hebben hier geen foutgrens.
Een verdwenen pakket of een geweigerde leesactie kan daardoor een
`FileSystemException` opleveren in plaats van een `OpenResult` en een uitleg.
De latere foutafhandeling bij het uitpakken dekt deze eerdere bronlezing niet.

Minimale proef: stel een bestaande bibliotheekmap in, open een niet-bestaand
`missing.ocideck`, controleer dat de Future een `FileSystemException` gooit en
`openFailureProvider` leeg blijft. Herhaal voor een bestaand onleesbaar pakket.
Test bij een oplossing ook een volgende geldige selectie in een meervoudige
openactie; één mislukte bron mag de overige geselecteerde bestanden niet verliezen.

### 2. Lees- en opslagproblemen krijgen een onjuiste formaatverklaring

`_readAndScanMarkdown` gebruikt `OpenFailure.unreadable` voor zowel stat-/IO-fouten
als ongeldige UTF-8. `openFailureMessage` maakt daarvan altijd:
“Dit bestand is geen leesbare tekst. OciDeck opent Markdown.”
Een geldig Markdown-bestand waarvoor leesrechten ontbreken is echter geen
verkeerd bestandsformaat. Ook `_packageOpenResult` vertaalt een volle schijf en
een onbeschrijfbare uitpakmap naar dezelfde `unreadable` en dus dezelfde tekst.
De service kent die laatste twee oorzaken al als `diskFull` en
`destinationUnavailable`, maar die informatie gaat onderweg verloren.

Minimale proef op macOS/Linux: schrijf geldige UTF-8-Marp, ontneem leesrecht met
`chmod 000`, open via `openFileByPath`, en controleer `OpenFailure.unreadable`
en de resulterende formaatmelding. Herstel daarna de rechten. Dit is een proef
van de gedeelde foutvertaling, geen simulatie van Windows-cloudgedrag.

### 3. Verkeerd veldtype in de zichtbare stijlsidecar blokkeert openen

`carriedProjectStyle` in `file_service_carried_style.dart` belooft terugval op
de lokale stijl bij een onbetrouwbaar bestand. Het vangt `FormatException` en
`FileSystemException`, maar niet de `TypeError` die `ThemeProfile.fromJson`
bij een onjuist numeriek veldtype kan geven.

Werkelijk gereproduceerd met geldig Markdown en `ocideck-style.json` ernaast:

- `{"logoSize":"96"}` → onafgevangen `TypeError`, geen `DeckOpenResult`.
- `{"tableCellPaddingPx":[]}` → eveneens onafgevangen `TypeError`.
- Alleen `{` in de sidecar → syntaxfout wordt opgevangen, presentatie opent.
- Zonder sidecar → dezelfde presentatie opent.

Dit kan verklaren waarom de hoofdpresentatie intact is en er toch geen tabblad
verschijnt. Het gaat om een optionele projectafhankelijkheid; het is onjuist
dat die de hele presentatie onbereikbaar maakt. **Niet bewezen dat haar
stijlbestand zo'n verkeerd veld bevat.** Vastgelegd als
[Pawprint #2877](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/2877).

### 4. Windows-picker kan blijven wachten na een workerfout

`pubspec.lock` legt `windows_file_picker` vast op **2.0.1**. De daadwerkelijk
geïnstalleerde packagebron is nagelezen, niet alleen de publieke API.
`_pickFilesInternal` start een isolate en wacht op `port.first`. De worker doet
`args.port.send(impl._pickFiles(args))`. Er is geen `onError`, `onExit` of
foutenvelop die deze resultaat-Future afhandelt wanneer `_pickFiles` gooit.

Native fouten kunnen onder meer ontstaan bij `getResults`, `getItemAt` en
`getDisplayName(SIGDN_FILESYSPATH)`. Die liggen na `show`: de dialoog kan dus
al verdwenen zijn voordat de fout ontstaat. Dan blijft Ocideck wachten in de
picker, nog vóór het bestand wordt gelezen. Een catch rond `openDeckDetailed`
of alleen de picker-Future herstelt dit niet: er komt geen resultaat of error
op die Future aan.

Een zelfstandige Dart-proef met dezelfde result-port/worker-sendstructuur en
een geïnjecteerde fout heeft aangetoond: **workerfout en exit zijn voorbij,
resultaat-Future blijft pending**. Dit is een verificatie van het protocol,
geen uitvoering van de native Windows-dialoog. Een concrete HRESULT bij de
melder is onbekend. Vastgelegd als
[Pawprint #2878](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/2878).

Een ontbrekende startmap is hier een minder passend subgeval: de kiezer komt
in de video wel open. Fouten bij het uitlezen van het selectieresultaat passen
beter bij het zichtbare moment. De oplossing moet workerfout/exit terugmelden,
niet de gebruiker met een korte timeout beperken terwijl zij nog kiest.

### 5. Stat-fout in grafiekdata blokkeert het hele deck

De in de eerste analyse genoemde onbeschermde `file.length()` in
`_hydrateCharts` is nu met gerichte foutinjectie bevestigd. Een echt opgeslagen
deck met `data/omzet.json` opent normaal. Een `IOOverrides`-wrapper die het
echte bestaan en realpath laat staan maar uitsluitend `length()` een
`FileSystemException` laat geven, veroorzaakt een onafgevangen uitzondering.
Een ontbrekend databestand wordt juist wel een waarschuwing met geopend deck.

Een verdwijnen tussen exists/stat of een stat-/cloudfout mag geen hele
presentatie blokkeren als de data zelf optioneel kan ontbreken. **Niet bewezen
dat haar presentatie grafieken bevat of deze IO-fout krijgt.** Vastgelegd als
[Pawprint #2879](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/2879).

## Afweging van de sporen na het vervolgonderzoek

| Spoor | Oordeel op basis van onderzoek | Issuebesluit |
|---|---|---|
| Windows-pickerworker faalt na sluiten dialoog | Past precies bij de zichtbare fase; foutprotocol aantoonbaar onvolledig. Native fout op haar machine onbekend. | #2878, foutafhandeling repareren en native Windows-proef toevoegen. |
| Verkeerd veldtype in `ocideck-style.json` | Bestandsnaam zichtbaar; volledige servicefout gereproduceerd met twee kleine JSON-varianten. Haar inhoud onbekend. | #2877, optionele stijl mag openen niet blokkeren. |
| Stat-fout in grafiekdata | `data`-map zichtbaar; fout met injectie gereproduceerd. Of er grafieken zijn is onbekend. | #2879, waarschuwing in plaats van totale weigering. |
| Pakketbron niet leesbaar | Eerder gereproduceerd; blijft relevant als gekozen extensie `.ocideck` is. | Bestaand #2875; geen duplicaat. |
| Cloudstatus / lokale beschikbaarheid | Rode statusmarkeringen zijn reëel, maar zijn geen IO-foutcode en bewijzen niet dat bytes ontbreken. | Geen apart “OneDrive kapot”-issue. De aangetoonde foutafhandeling staat in #2875–#2879. |
| CRLF, UTF-8-BOM, accent of spaties in pad | Eén controlebestand met deze kenmerken opent; code normaliseert CRLF en bewaart BOM. | Geen nieuw issue op basis van deze aanwijzingen. Dit test geen Windows MAX_PATH/UNC. |
| Ontbrekende afbeelding | Dezelfde controlepresentatie opent met verwijzing naar een niet-bestaand plaatje. | Geen issue “ontbrekend plaatje verhindert openen”. |
| Lege of kapotte JSON-syntax in stijlsidecar | Syntactisch ongeldige JSON wordt al afgevangen; veldtypefouten zijn het afzonderlijke probleem. | Alleen #2877 voor het bewezen gat. |
| Installatie/VC++-runtime | App start en de native kiezer verschijnt. | Geen passend spoor voor dit incident. |
| Kwaliteitswarming / idle scheduler | `Priority.idle` kan wachten zolang framecallbacks actief zijn. In het beginscherm is geen voortdurende animatie gevonden die dit verklaart; 48 dia's is op zichzelf geen bewijs van overbelasting. | Geen nieuw issue zonder passend triggerbewijs. De gewone tab-open-tests gebruiken een aparte synchrone testroute en sluiten runtimeproblemen niet uit. |
| Verkeerde extensie / UTF-16 / beschadigd hoofdbestand | Blijft mogelijk; hoort meestal een foutresultaat te geven, geen stille wacht. | Bekende onjuiste IO-/formaattekst onder #2876; geen aanvullende claim over haar bestand. |

De nuttigste onderscheidende proeven op haar Windows-machine zijn, in deze
volgorde: dezelfde presentatie via de reeds zichtbare bibliotheekrij openen
(passeert de native picker niet), een volledige lokale projectkopie buiten de
synchronisatiemap openen, en uitsluitend op die kopie het stijlbestand tijdelijk
een andere naam geven. Werkt de bibliotheekrij maar Bladeren niet, dan wordt de
picker het sterkste spoor. Werkt pas het tijdelijk weglaten van de stijl, dan
is de stijl de verdachte; de inhoud moet daarna het verschil verklaren. Een
geslaagde lokale kopie wijst naar de oorspronkelijke locatie, maar bewijst nog
niet welke provider-/rechtenfout daar optreedt.

## Overige mogelijke oorzaken en gericht vervolg

| Categorie | Huidige aanwijzing / gedrag | Wat de oorzaak kan onderscheiden |
|---|---|---|
| Synchronisatie / online bestand | Rode statusmarkeringen in de video; IO kan mislukken. | Providerstatus lezen; controleren of de hele projectmap lokaal beschikbaar is; kopie naar een korte lokale map buiten synchronisatie openen. |
| Verplaatst/verwijderd bestand | Recente lijst en scan kunnen verouderd zijn; `.md` kent `notFound`, pakketroute heeft bevinding 1. | Volledig pad en extensie uit Eigenschappen; bestaan controleren direct na de poging. |
| Toegang, blokkade, netwerkpad | IO deelt nu een reden met tekstdecodering. | Diagnostiek met uitzonderingstype/OS-foutcode; lokaal lezen/kopiëren proberen. Geen beveiliging uitschakelen. |
| Uitpakbestemming niet beschikbaar / schijf vol | Alleen relevant voor pakketten; bevinding 2. | Extensie vaststellen, ingestelde bibliotheekmap en vrije ruimte controleren. Een bestaande map kunnen aanmaken bewijst nog niet dat daarin geschreven kan worden. |
| Ongeldige encoding / binair bestand | Strikte UTF-8-lezing kan weigeren; Windows-associatie bewijst geen inhoud. | Originele bytes of geschoond reproducerend bestand, BOM/encoding en bestandsgrootte. UTF-16 is geen UTF-8. Niet zomaar herschrijven. |
| Beschadigd of incompleet bestand/pakket | Parser en ZIP-validatie kunnen weigeren. | Hash en grootte met werkende kopie vergelijken; ZIP valideren indien echt een pakket; bron bij voorkeur alleen lezen. |
| Veiligheidsweigering | `unsafe` hoort een afzonderlijk alarm te tonen. Geen alarm zichtbaar. | Diagnostiek en, indien deelbaar, de geweigerde inhoud. De veiligheidscontrole behouden. |
| Grootte / uitpaklimieten | Markdown 32 MiB, pakket 512 MiB; daarnaast entry- en extractiegrenzen. | Werkelijke grootte, ledentelling en uitgepakte omvang vaststellen. Geen bewijs in de opname dat een grens geraakt wordt. |
| Frontmatter / verkeerde modus | Zonder `marp: true` opent leesbare inhoud als document. | Eerste frontmatterregels en volledig document controleren. Een ontbrekende marp-vlag verklaart op zichzelf geen stille weigering in deze checkout. |
| Extra projectbestanden | Grafiekdata, thema's, bijschriften en lagen worden tijdens openen gelezen. | Stijltypefouten en grafiek-statfouten zijn nu bevestigd; zie #2877/#2879. Controleer welke van deze afhankelijkheden werkelijk wordt gebruikt. |
| Analyse vóór tabplaatsing | Privacy-/kwaliteitswarming wordt afgewacht. | Log op fouten of lange UI-blokkade; tijd tot resultaat meten met dezelfde bron. Geen hang bewezen door de resterende zeven seconden beeld. |
| Bestandskiezer / buildverschil | Keuze verdwijnt, maar teruggegeven pad is niet zichtbaar. | Windows-proef met dezelfde build; diagnostiek; afzonderlijk recent bestand, bibliotheekrij en Bladeren vergelijken. |

Ontbrekende plaatjes zijn op zichzelf geen bewijs van een niet-openbare
presentatie. Maak onderscheid tussen het hoofdbestand niet kunnen openen en
een geopend deck waarvan afhankelijkheden ontbreken. Ook frontmatter zonder
body is bewust toegestaan: het kan een geldig leeg deck zijn (historisch #1909).

## Nog benodigde incidentinformatie

1. Direct na één nieuwe poging: **Instellingen → Over OciDeck → Diagnostiek →
   Diagnostiek kopiëren**. Dit bevat build/OS en recente logregels. Zie ook
   [de bestaande probleemoplossingsgids](TROUBLESHOOTING_GUIDE.md#build-and-startup-problems).
2. Volledige extensie, bestandsgrootte en volledig lokaal pad; versie/build van
   de Windows-app. Het etiket OciDeck-presentatie alleen is onvoldoende.
3. Is dezelfde projectmap op de broncomputer nog te openen? Werkt een volledige
   lokale kopie buiten de synchronisatiemap op de Windows-computer?
4. Indien deelbaar: origineel pakket of een geschoond bestand dat dezelfde fout
   veroorzaakt. Alleen een los `.md` kan noodzakelijke projectbestanden missen.

Bewaar het origineel en zijn projectmap ongewijzigd; vergelijk op kopieën.
De privévideo is niet naar de issuetracker geüpload. Issues bevatten technische
repro's en geen persoonsgegevens of persoonlijke bestandsnamen uit de opname.

## Verificatie en opvolging

- [Pawprint #2875: leesfouten van lokale pakketten ontsnappen zonder gebruikersmelding](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/2875).
- [Pawprint #2876: toegangs- en opslagfouten krijgen ten onrechte een formaatmelding](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/2876).
- Beide diagnostische proeven zijn op macOS uitgevoerd en bevestigd: ontbrekend
  pakket gooit een `FileSystemException` zonder foutreden; geldig Markdown met
  `chmod 000` krijgt de onjuiste formaatmelding. De 2 proeven slagen omdat ze
  het defect aantonen, niet omdat het defect is opgelost. Het tijdelijke
  proefbestand is uit de testsuite verwijderd; reproductiestappen staan hierboven
  en in de issues. Tijdelijke proefbron en uitvoer staan in
  `/tmp/ocideck-video-analysis/` en vormen geen duurzaam archief.
- Bestaande controles:
  `flutter test --no-pub test/open_failure_reason_test.dart test/open_package_by_path_test.dart test/document_open_test.dart --reporter compact`
  — **20 tests geslaagd**. Een eerste teststart strandde in de native
  assetvoorbereiding (`libpdfium.dylib` ontbrak); de daaropvolgende afzonderlijke
  run voltooide succesvol. De proeven zijn daarna afzonderlijk nogmaals uitgevoerd.
- Vooraf is Pawprint doorzocht op gerelateerde open/gesloten issues (onder meer
  openen, UTF-8 en pakketten); er waren geen open issues. Historische reparaties
  zoals #646 en #905 dekken deze twee vastgestelde tekortkomingen niet volledig.
- Dit onderzoek wijzigt geen runtimecode. Er is geen fix, commit of push gedaan.
  De issues bevatten de gewenste uitkomst en regressietestcriteria.

### Verificatie van het vervolgonderzoek

- Vijf gerichte controles/proeven zijn geslaagd: combinatie van BOM/CRLF/accent/
  spaties/ontbrekend beeld; ongeldige JSON-syntax in stijl; twee afzonderlijke
  veldtypefouten; grafiek-statfout met controle op gewoon openen en ontbrekende data.
  Geslaagd betekent bij de foutproeven dat het defect aantoonbaar optreedt.
- Bij de eerste grafiekinjectie werd alleen het lexicale macOS-pad geraakt en
  niet het gecanonicaliseerde `/private/...`-pad. Die proef activeerde de fout
  dus niet. Na correctie van het doelpad is de stat-uitzondering bevestigd.
- De losse picker-protocolproef observeert fout en exit van de worker, en
  vervolgens nog een pending resultaat. Er is geen Windows-API nagebootst of
  Windows-succes geclaimd.
- Bestaande stijl-/grafiekcontroles:
  `flutter test --no-pub test/logo_style_roundtrip_test.dart test/chart_data_file_test.dart --reporter compact`
  — **29 tests geslaagd**. De tijdelijke defectproeven zijn daarna uit de
  normale testsuite verwijderd; er blijven geen tests achter die het foutieve
  gedrag als gewenste regressie-uitkomst voorschrijven.
- Proefbron en logs staan tijdelijk onder `/tmp/ocideck-video-analysis/`.
  De duurzame reproductie-instructies en grenzen staan in deze notitie en
  Pawprint #2877, #2878 en #2879.
