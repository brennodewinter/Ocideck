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
taak gedaan. Niet iedere wijziging in de gedeelde diff komt dus uit dit werk.

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
| Privacywarming | Gebruikt `Isolate.run` in plaats van een zelfgemaakt resultaatpoortprotocol. | Geen nieuwe raw-port-issue aangetroffen. De aparte unit-testroute blijft reden om de release-app werkelijk te bedienen. |

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
4. Opent met Ctrl+O de zoekdialoog, bedient Browse/Bladeren en eist een native
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
   screenshots, UIA-bomen en resultaat/fout-JSON als Actions-artifact.

Een supervisor begrenst de worker en de door hem gestarte app tot vier minuten.
Ook een blokkerende UIA-aanroep kan dus niet de hele releasejob bezet houden.
Onbekende UI-taal, ontbrekende controls, een verdwenen proces en ontbrekend
bewijs falen hard. Er is geen groene skip en geen `continue-on-error`.
Er worden geen runtime-testhaakjes aan Ocideck toegevoegd.

Dit vereist een wegwerp-Windows-runner met interactieve desktop en Engelse of
Nederlandse interface. UIA-identificatie gebeurt op de echte toegankelijkheids-
boom; fouten daarin komen als rood bewijs terug. Cloudplaceholder-/rechtenfouten
worden hiermee niet nagebootst. Er is in deze macOS-sessie **geen Windows-app
uitgevoerd**: syntax-/fixturetests zijn geen bewijs van geslaagde native bediening.
De eerste kandidaat-run moet dat bewijs leveren in `windows-open-probe`.

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
  PowerShell-bestanden zijn syntactisch geverifieerd. Geen volledige
  `make check-full` of nieuwe Windows-build geclaimd.
