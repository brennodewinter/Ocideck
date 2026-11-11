# Kwaliteitsonderzoek van gegevens- en procesgrenzen

Datum: 11 november 2026. Aanleiding: de Windows-video en de bevestigde fouten
#2875–#2879. Opdracht: dezelfde foutklassen elders onderzoeken en een echte
Windows-openproef aan de releasecontrole toevoegen. Dit is een gericht
correctheidsonderzoek, geen repositorybrede veiligheidsaudit of garantie dat
alle fouten zijn gevonden.

## Reikwijdte en werkboom

Onderzochte grenzen: project-/pakketstijl, zelfstandige stijlimport, opgeslagen
voorkeuren, herstelbestanden, browserkopieën, intake-sidecars, lokale bestand-
hydratatie en de handgeschreven isolateprotocollen voor import en gezichtsdetectie.
De JSON-/voorkeurproeven zijn uitgevoerd op broncommit `22ae82c45`.

Tijdens dit werk verschenen andere wijzigingen in dezelfde checkout voor
grafiekhydratatie en IO-fouttests, en issues #2881–#2887. Die wijzigingen zijn
intact gelaten. Hier zijn de releaseproef, haar fixture-/koppelingtests en dit
onderzoeksverslag toegevoegd; er is geen reparatie van runtimecode door deze
taak gedaan in de eerste onderzoeksronde. De latere echte Windows-proef
bewees alsnog een runtimefout; de reparatie daarvan staat hieronder. Niet
iedere wijziging in de oorspronkelijke gedeelde diff komt uit dit werk.

## Bevindingen en afweging

| Grens | Controle / waarneming | Uitkomst |
|---|---|---|
| Pakketstijl uit bytes | `applyCarriedStyleMembers` met `{"logoSize":"96"}` gooit `TypeError`. Alleen `FormatException` wordt afgevangen. | Daadwerkelijk gereproduceerd; bewijs toegevoegd aan #2877, geen duplicaatissue. |
| Zelfstandig `.ocideckstyle` | Geldige envelop `{"ocideck":"style-profile","version":2,"profile":{"logoSize":"96"}}` gooit dezelfde `TypeError` buiten de JSON-catch. | Daadwerkelijk gereproduceerd; meegenomen bij #2877. De instellingen-UI heeft hier een catch en toont een algemene importfout: geen stille crash geclaimd. IO-fouten op de picker zijn apart #2884. |
| Opgeslagen instellingen | `themeProfiles` met een fout num-veld onderbreekt `_load` vóór de toekenning van alle instellingen. Een geldige `languageCode: en` blijft daardoor ongeladen (`nl`). | Daadwerkelijk gereproduceerd; nieuw issue [#2888](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/2888). Bronvoorkeuren blijven bewaard; geen bewezen verwijdering op schijf. |
| Herstelbestanden | Goede snapshot naast `{"id":12}`. `loadAll` vangt de ongeldige snapshot per bestand af. | Controleproef geslaagd: goede snapshot komt terug, slechte bronbytes blijven identiek. Geen nieuw defect. |
| Browserkopieën | `BrowserDeckStore.list` weigert bij onleesbare opslag; `save` doet dit bewust vóór overschrijven. Bestaande test bewaakt behoud van de beschadigde waarde. | Bewuste fail-closed keuze; geen nieuw issue zonder bewijs van onjuist UI-/herstelgedrag. Herstel is wel relevant onder #2880. |
| Intake-sidecars | `readIntakeContext` omvat bestaan, lezen en decode in een catch; `fromJson` controleert locator/revision-typen vóór casts. | Statisch geen vergelijkbaar ontsnappend type-/IO-gat aangetroffen op deze grens. Geen universele parsergarantie geclaimd. |
| AI-/LibrePlan-voorkeuren | `_readAiSettings` en `_readLibreplanSettings` hebben elk een eigen catch en terugval. | Bestaande structuur contrasteert met de onbeschermde stijllijsten. Geen extra issue voor hetzelfde patroon. |
| Grafiekdata in documentexport | Bestaan/stat stonden ook hier buiten de leescatch. | Overlap met reeds aangemaakt #2881 en parallelle reparatie; niet dubbel aangemaakt. |
| Importmap-hergebruik / picker-bytes / captions | Vergelijkbare IO-grenzen nagelopen; aparte issues #2882–#2886 waren inmiddels aanwezig. | Opvolgen in die issues; niet als nieuwe vondsten van deze taak tellen. |
| Importworker | `runImportTask` stuurt workerfouten via `onError` naar een latch; annuleren doodt de worker en sluit de poort. Normale `_worker` stuurt zijn resultaat terug. | Het Windows-pickerpatroon ontbreekt hier voor gewone workerfouten. Er is geen `onExit`; een resultaatloze exit is een resterende onderzoeksvraag, geen nieuw bevestigd incident zonder bereikbare trigger. |
| Gezichtsdetectieworker | Antwoorden hebben een 90s-timeout/finally-close. De eerdere handshake in `_ensureWorker` is onbegrensd en heeft geen eigen error/exit-kanaal. De worker stuurt de handshake direct na een triviale constructor. | Statisch aandachtspunt, niet dynamisch als bereikbaar defect gereproduceerd. De 90s-grens dekt de handshake niet. Niet als bevestigd nieuw defect gerapporteerd. |
| Privacywarming | De eerste statische ronde zag `Isolate.run` en geen raw-port-protocol. De echte releaseproef toonde daarna een niet-verzendbare scanner door een providerclosure. | Bevestigd productieprobleem [#2891](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/2891); de eerste statische beoordeling was onvoldoende. Reparatie en bewijs hieronder. |

De bedoeling is fouten per onafhankelijk onderdeel te begrenzen en bekende
oorzaken door te geven. Een catch rond alles is op zichzelf onvoldoende:
onleesbare broninformatie mag niet door standaardwaarden worden vervangen
en vervolgens bij opslaan verdwijnen.

## Herstel van bestaande bestanden

Op expliciet aanvullend verzoek is
[Pawprint #2880](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/2880)
aangemaakt: herstel naar een kopie, behoud van exacte bronbytes en onbekende
onderdelen, manifest/hashes, eerlijke melding van niet herstelbare delen en
foutinjectie tijdens het herstel. Het issue belooft niet dat reeds verdwenen
bytes terug te vinden zijn; het eist dat herstel zelf geen extra informatie wist.

## Windows-proef in de releasecontrole

De bestaande installerproef in `.github/workflows/release.yml` riep alleen de
app aan en controleerde een eerste frame. Daar is vóór de-installatie en vóór
het cohortattest de aanroep van `scripts/windows_open_probe.ps1` aan toegevoegd.
De bestaande Forgejo-route die de Windows-kandidaat op de spiegel laat bouwen
blijft dezelfde workflow volgen; issues blijven op Pawprint.

De proef:

1. Maakt nieuwe, unieke fixtures en weigert een bestaande fixturemap (geen oud
   succesbewijs hergebruiken).
2. Start de **geïnstalleerde release-executable**, zonder Flutter-testbinding,
   mock-picker, direct providercommando of alternatieve parserroute.
3. Handelt op een verse runner de licentiepoort via de echte interface af.
4. Opent via de welkomstknop (vanuit de editor met Meer → Openen) de zoekdialoog,
   bedient Browse/Bladeren en eist een native
   Windows-dialoog (`#32770`) van het eigen proces.
5. Annuleert één keer en opent vervolgens opnieuw.
6. Selecteert via het native filename-control een Markdown-presentatie en
   daarna een `.ocideck`-pakket. Beide hebben 48 dia's, BOM/CRLF, een geldige
   stijlsidecar en paden met spaties/accent. Dit raakt ook de productie-warming
   die gewone tests overslaan.
7. Eist per bestand een vooraf afwezige unieke titel in de zichtbare editor,
   zonder welkomstacties. De bestandsnaam verschilt van die titel, zodat de
   kiezer zelf niet als editorbewijs kan dienen.
8. Controleert dat alle fixturebronhashes ongewijzigd zijn en bewaart
   screenshots, UIA-/MSAA-bomen en resultaat/fout-JSON als Actions-artifact.

Een supervisor begrenst de worker en de door hem gestarte app tot vier minuten.
Ook een blokkerende UIA-aanroep kan dus niet de hele releasejob bezet houden.
Onbekende UI-taal, ontbrekende controls, een verdwenen proces en ontbrekend
bewijs falen hard. Er is geen groene skip en geen `continue-on-error`.
Er worden geen runtime-testhaakjes aan Ocideck toegevoegd.

Dit vereist een wegwerp-Windows-runner met interactieve desktop en Engelse
native bestandskiezer; de Flutter-app mag Nederlands of Engels zijn. MSAA-/UIA-identificatie gebeurt op de echte toegankelijkheids-
boom; fouten daarin komen als rood bewijs terug. Cloudplaceholder-/rechtenfouten
worden hiermee niet nagebootst. Syntax-/fixturetests zijn geen bewijs van
geslaagde native bediening; het vervolg hieronder legt de echte runs vast.

## Verificatie

- Vier tijdelijke diagnostische Flutter-proeven geslaagd: losse profielimport
  met verkeerd type, pakketstijl met verkeerd type, afgebroken instellingenload,
  en herstelisolatie met behoud van de onleesbare bron.
- Tijdelijke defectproeven zijn niet als tests van gewenst gedrag achtergelaten.
  Reproducties staan in #2877/#2888; tijdelijke bron en logs staan onder
  `/tmp/ocideck-video-analysis/` en zijn geen duurzaam archief.
- `test/release_windows_open_probe_test.py` bewaakt echte fixture-inhoud,
  BOM/CRLF/48 dia's, pakketleden, unieke markers, weigeren van oud bewijs,
  Windows-PowerShell-5.1-veilige encoding en de verplichte releasekoppeling
  vóór promotie. Dit vervangt de native proef niet.
- De PowerShell-bron is met de echte PowerShell-parser gecontroleerd. Voor
  de lokale scriptcontroles is een portable PowerShell 7.4.6 onder `/tmp`
  gebruikt; de releaseworker gebruikt Windows PowerShell 5.1 met UI Automation.
- De supervisor is daarnaast met acht proces-/resultaatgevallen uitgevoerd:
  compleet succes, child-exitfout, timeout met kill, ontbrekend resultaat,
  expliciet foutresultaat, twee keer hetzelfde bestandstype, geen annulering
  en gewijzigde bronnen. Alle verwachtingen slagen. Dit zijn foutinjectietests
  met een vervangen childproces, uitdrukkelijk geen native UI-proef. Deze
  controles draaien ook in een apart PowerShell-proces vóór de echte releaseproef.
- Bestaande Windows-packagingtests: **48 geslaagd**.
- Volledige Python-releasetests: **252 geslaagd**; de vier gerichte
  fixture-/releasekoppelingtests zijn ook afzonderlijk uitgevoerd. Beide
  PowerShell-bestanden zijn syntactisch geverifieerd. De definitieve volledige
  controle en Windows-resultaten staan hieronder.

## Vervolg: commit, push en uitvoering op Windows

De bestuurder is gecommit als `6daf2854206cfadd1306c65f1b7b1b062f2f1ac5`
en op Pawprint gezet onder `codex/windows-open-probe`. De Windows-spiegel
bouwt een afzonderlijke, onveranderlijke kandidaatbranch. Er wordt geen tag
of publieke release gemaakt.

- Run 43058129791 weigerde terecht de kandidaatinvoer: de commit vermeldt
  `0.7.7+49`, terwijl `v0.7.8` was meegegeven. De invoer is daarna afgeleid
  van de vastgezette `pubspec.yaml`; de versiecontrole is behouden.
- [Run 43058624708](https://github.com/brennodewinter/Ocideck/actions/runs/43058624708)
  bouwde de app en installer en startte de geïnstalleerde app op Windows
  Server 2025. De eerste echte proef stopte op het toestemmingsscherm:
  screenshot aanwezig, maar de UIA-boom bevatte slechts een leeg `FLUTTERVIEW`.
  Dat is geen bewezen bestandsopenfout; de bestuurder kon nog niet bedienen.
- De bestuurder vraagt nu via `AccessibleObjectFromWindow`/`OBJID_CLIENT`
  toegankelijkheid aan op het hoofdvenster en de echte child-HWND's. Dit is
  het normale MSAA-pad waarmee Flutter zijn semantiek activeert, zonder
  testbinding of app-haakje. Zie de
  [Flutter Windows-toegankelijkheidsdocumentatie](https://github.com/flutter/flutter/blob/master/docs/platforms/desktop/windows/Accessibility-on-Windows.md).
  De bestaande eisen aan native dialoog, titel en bronhashes blijven gelden.
- Een mislukte kandidaat bewaart voortaan ook de installer als diagnoseartifact,
  zodat een probleem in de bestuurder niet alle gebouwde bytes weggooit.
- De lokale poort vond daarnaast een overschreden `FileService`-klasseplafond.
  De staatloze `_fileHasBytes`-helper is buiten de extensie geplaatst, met
  behoud van gedrag; het plafond is niet verruimd.
- De volledige lokale suite bereikte **15.317 geslaagde tests**, één skip en
  één fout: een verouderde WebRTC-boomhash in de SBOM. Bij onderzoek bleek ook
  dat de generator echte symlinks oversloeg, maar Windows-placeholders als
  gewone bestanden meetelde. De generator neemt nu het POSIX-doel van een
  symlink op als tekst, zonder het doel te volgen. De SBOM is opnieuw afgeleid.
  Drie regressietests bewaken gelijkheid met Git-placeholders, geen lezen
  buiten de fork en het detecteren van bronwijzigingen. Samen met SBOM- en
  packagingtests zijn **78 gerichte tests geslaagd**.

- `make check-full` is daarna volledig geslaagd, inclusief 15.321 Flutter-tests
  (één skip), 1.238 pakkettests (vijf skips), 92 goldentests en de uitgebreide
  controles op licenties, SBOM, afhankelijkheden, webbouw en echte Marp-rendering.
- Run 43063590429 bewees dat alleen MSAA activeren onvoldoende was: deze
  Flutter-engine exposeert de controls niet via UIA. De bestuurder leest en
  bedient Flutter daarom direct via MSAA; native Windows-dialogen worden via
  UIA geïdentificeerd.
- Run 43067628793 bediende daarmee de toestemmingspoort. De welkomstactie
  wordt nu direct bediend en de editor krijgt voor Ctrl+O focus op de echte
  Flutter-child-HWND, niet op het bovenliggende venster.
- Run 43068356712 opende vervolgens de echte Windows-bestandskiezer, maar de
  annulering raakte een lijstbestand met dezelfde AutomationId als Cancel.
  Selectie op zowel ID als label vond de juiste Cancel, maar run 43069272806
  bewees dat deze native provider geen InvokePattern aanbiedt. De kiezer wordt
  daarom met echte toetsenbordinvoer bediend (Escape, bestandsnaam, Enter),
  zonder interne app-aanroep. De vereiste unieke editortitel blijft behouden.
- De diagnostische workflow installeert de behouden f566a349c-installer opnieuw
  op een verse Windows-runner. Haar artifact bevat ook `producer.json`;
  dit onderscheidt de gebouwde applicatie van de geteste bestuurder.

## Productiefout ontdekt door de echte openproef

[Run 43070889495](https://github.com/brennodewinter/Ocideck/actions/runs/43070889495)
legde een correcte bestandsnaam in de native kiezer vast. Direct na selectie
bleef het welkomstscherm staan. `app-flight-0.log` meldde de concrete oorzaak:
`Illegal argument in isolate message: object is unsendable`, met de keten
`Future → ProviderPointer/Ref → privacyScannerProvider.assetTextReader →
PrivacyScanner → warmPrivacyScanMemo → Isolate.run`. Het openen brak af vóór
`_placeDeckInTab`. Deze fout is dus geen falende knopselectie van de bestuurder.

Dit is geregistreerd als
[Pawprint #2891](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/2891).
Het bewijst zonder het oorspronkelijke bestand/log niet dat precies dit de
melding in de aangeleverde video veroorzaakte.

Commit `b131e4513` maakt een expliciet gegevensverzoek: scannerinstellingen,
dia's en op de aanroepende isolate gelezen captiontekst (de bestaande lezer
begrenst ieder bestand). Pas de worker maakt een nieuwe scanner. De
`Isolate.run`-closure heeft een eigen functiecontext en kan daardoor geen
reader/provider uit de oorspronkelijke context meenemen. Callbackgedrag,
mem:-captions en de scanneridentiteit van de UI-memo blijven behouden.
Captiontekst wordt per uniek pad één keer gelezen; er gaat geen inhoud naar
een externe dienst.

De nieuwe regressietest voert een **echte isolate** uit met een assetlezer die
bewust een niet-verzendbare `ReceivePort` vasthoudt. Hij vergelijkt alle
bevindingvelden met een directe scan, inclusief captions, eigen identiteit,
regio's en uitgeschakelde regels. Deze test en de bestaande memotests slagen:
**14 tests**; `flutter analyze --no-pub` is schoon. De eerdere gewone
warmingtests namen de synchrone no-token route en konden deze fout niet zien.

De oude kandidaat 43069663502 is na deze vondst geannuleerd en vervangen door
een nieuwe kandidaat op de vastgezette reparatiecommit. De conventiecontrole
vond nog de vereiste expliciete webterugval bij de workerfunctie; die is als
`0392f1799` toegevoegd. Run 43071744119 is daarom eveneens geannuleerd; de
definitieve kandidaat is 43072219374. De volledige lokale poort draait opnieuw
omdat nu ook runtimecode gewijzigd is.

Na deze vondst zijn ook de andere `Isolate.run`-/`compute`-grenzen nagelopen:
SVG-sanering en broncontroles sturen bytes/records; beeldrotatie, hashes en
AI-resizing gebruiken top-level workers; pakket-/DOCX-/ODT-/EPUB-compressie
stuurt archiefdata; raster- en document-PDF-export bereiden hun data vóór de
worker voor. In die callsites is geen tweede providerreader zoals bij de
privacyscanner aangetroffen. Dit is een gerichte inspectie, geen garantie over
alle mogelijke callbackconfiguraties. De bestaande exporttests draaien mee in
de volledige poort.

De diagnostische workflow is na de iteratie handmatig gemaakt, zonder
vastgezette oude installer of automatische proef op deze tijdelijke branch.
Een expliciet opgegeven voltooide producer levert bij succes zijn cohort en
bij een mislukte openproef de apart behouden installer. Het definitieve native
openbewijs wordt hieronder toegevoegd na de herproef.


## Windows-herproef met de runtime-reparatie

[Run 43072219374](https://github.com/brennodewinter/Ocideck/actions/runs/43072219374)
bouwde en installeerde commit `0392f1799`. Annuleren en vervolgens de
Markdown-presentatie openen slaagden: de screenshot toont 48 dia's en de unieke
titel in de editor; de vluchtrecorder heeft de onverzendbare-providerfout niet
meer. De proef werd nog rood doordat de bestuurder vanuit de editor met Ctrl+O
geen zoekdialoog opende. Dit bewijst de werking van die sneltoets niet; de
bestuurder gebruikt voortaan de echte zichtbare actie Meer → Openen.

De volledige lokale `make check-full` op de runtime-reparatie is geslaagd:
15.322 Flutter-tests (één skip), 1.238 pakkettests (vijf skips), 92 goldens en de
uitgebreide controles inclusief webbuild, licenties, SBOM en echte Marp-rendering.
De volgende native proef hergebruikt exact de installer van run 43072219374;
daarna volgt de volledige kandidaat met de gecorrigeerde bestuurder.


## Geslaagde native openproef

[Diagnoserun 43076242154](https://github.com/brennodewinter/Ocideck/actions/runs/43076242154)
is volledig **geslaagd**, inclusief installatie en de-installatie. Producer:
releasebuild 43072219374, applicatiecommit `0392f1799`; bestuurdercommit
`056c2e548`. Het artifact bevat `producer.json`, beide screenshots,
MSAA-/UIA-bomen, geselecteerde bestandsnamen, beide `*.proof.json`-bestanden,
`result.json`, fixtures en de eigen app-vluchtrecorder.

`result.json` vermeldt `opened: [markdown, package]`, `cancelled: true` en
`sourceHashesPreserved: true`. Beide unieke titels zijn zichtbaar in de editor
met 48 dia's. Na downloaden zijn de vijf bronhashes onafhankelijk opnieuw
berekend: alle vijf identiek aan het oorspronkelijke fixturemanifest.
De vluchtrecorder bevat geen ERROR en geen onverzendbare-isolatefout.

De eerdere diagnoserun 43075832047 bewees beide opens al, maar faalde nog op
`Get-FileHash`: Windows PowerShell erfde de modulezoekpaden van PowerShell 7.
De bestuurder berekent SHA256 nu rechtstreeks via .NET, zonder moduleautoload;
ook de standaard SHA256-vector voor `abc` is lokaal gecontroleerd.

[Volledige kandidaat 43076303590](https://github.com/brennodewinter/Ocideck/actions/runs/43076303590)
is eveneens **volledig geslaagd** op commit
`056c2e548ad151051d8f12e81ec7dfd234703089`: bouwen, installer maken,
installeren, de native openproef, schoon de-installeren, cohortattest en
artifactupload. Er is geen tag of publieke release gemaakt.

Het eigen `windows-open-probe`-artifact van deze volledige kandidaat is opnieuw
gedownload en gecontroleerd: beide editortitels/48 dia's zichtbaar, beide
`*.proof.json` geldig, `cancelled` en `sourceHashesPreserved` waar, alle vijf
bronhashes onafhankelijk identiek en geen ERROR/unsendable in de app-log.
De runtimecode is identiek aan de volledig lokaal getoetste `0392f1799`;
daarna zijn alleen de Windows-bestuurder, diagnoseworkflow en documentatie
bijgewerkt.

De run is tot terminale status `success` gevolgd. Het issue #2891 blijft open
voor de gebruikelijke beoordeling/merge; de reparatie en het geslaagde bewijs
staan op `codex/windows-open-probe`.
