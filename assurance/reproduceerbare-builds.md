# Reproduceerbare builds & provenance — onderzoek en positie

> **Status:** vastgesteld 2026-07-31 · Stichting LibreKAT · intern werkdocument
>
> Geen conformiteitsclaim en geen auditrapport. Zie [`README.md`](README.md) voor
> waarom dit niet in `docs/` staat.

## Waarom dit dossier bestaat

Dit is de uitwerking van **#1027**, het residu van ENISA-open punt O1 uit
[`enisa-sbd-mapping.md`](enisa-sbd-mapping.md) (playbook 14, "release artefacts
signed") en onderdeel van de veilige-distributievraag #520.

De release-keten heeft sinds #1014 **herkomst** maar nog geen
**reproduceerbaarheid**. `SHA256SUMS` draagt een minisign detached signature die
elk artefact verankert; macOS is daarbovenop Developer-ID-getekend en
genotariseerd. Een handtekening zegt *wie* voor de bytes instaat. Een
reproduceerbare build zegt iets sterkers: iedereen die de bron heeft, maakt er
dezelfde bytes uit, en hoeft de bouwmachine — en de ondertekenaar — dus niet te
vertrouwen. Dat is precies de kernwaarde "de gebruiker bouwt uit de bron", maar
dan **verifieerbaar identiek** in plaats van "een workflow die je kunt lezen".

Dit dossier onderzoekt of dat haalbaar is, per platform, wat het toevoegt, en
waar de weging landt. Zoals overal hier is de **motivering het waardevolle deel**,
niet de telling.

## De vraag scherp: wat koopt reproduceerbaarheid dat een handtekening niet koopt

De handtekening over `SHA256SUMS` beschermt tegen een verwisseling ná publicatie:
wie de download vervangt, kan de handtekening niet meebewegen zonder de private
sleutel. Wat hij **niet** dekt, staat er eerlijk bij in
[`SECURITY.md`](../SECURITY.md) §"Release artifact integrity and signing": een
compromittering van de eigen publicatieketen zelf. Wie zowel de build als de
ondertekening beheerst, tekent een kwaadaardig artefact net zo geldig als een
goed. De handtekening verplaatst het vertrouwen naar de sleutelhouder en de
bouwmachine; hij verwijdert het niet.

Reproduceerbaarheid verwijdert het wél, voor wie de moeite neemt: bouw zelf uit
de bron, en als je dezelfde bytes krijgt als de gepubliceerde (en getekende)
lijst beschrijft, dan is de bouwmachine uit de vergelijking. Dat is de enige
maatregel in deze keten die niet leunt op vertrouwen in ons.

## Wat er nu al is — de zwakke vorm

Drie dingen samen vormen vandaag een zwakke reproduceerbaarheid:

- **De bronroute** is openbaar en de bouwstappen zijn leesbaar
  (`.forgejo/workflows/release.yml`, `docs/BUILD.md`).
- **De toolchain is gepind** en bewaakt: Flutter 3.44.8 stable, afgedwongen door
  `make check-toolchain` (`tool/check_toolchain.dart`) tegen `.tool-versions` en
  beide workflow-bestanden.
- **Eén bekende bron van niet-determinisme is al weggewerkt**:
  `tool/pack_web_release.dart` (`nietUitleveren`) verwijdert `.last_build_id`,
  een md5 over onder meer het absolute bouwpad, precies omdat die twee
  bouwmachines gegarandeerd zou laten uiteenlopen.

Wat ontbrak was het bewijs: is de rest van de bundel bij byte-identieke bron ook
byte-identiek? Dat was in de code uitdrukkelijk *niet* beweerd (zie de oude
docstring van `bundelBestanden` in `pack_web_release.dart`). Dit dossier meet het.

## Empirische toets — de webbundel

De web-tak is volgens de issue "waarschijnlijk het makkelijkst", dus daar is
gemeten in plaats van geredeneerd.

**Methode.** Twee schone builds (`flutter clean` ertussen) met exact het
release-commando `flutter build web --release --no-web-resources-cdn --csp`
(Flutter 3.44.8, engine `0cd610717b`), daarna een sha256 per bestand en een
regel-voor-regel-diff. Plus een grep van de hele uitvoer op het absolute
bouwpad, om padinbedding op te sporen.

**Uitkomst.**

- Van **2854 bestanden** week er precies **één** af: `flutter_bootstrap.js`.
  `main.dart.js`, CanvasKit, de service-worker, de getree-shakete fonts en alle
  assets waren byte-voor-byte gelijk.
- Binnen dat ene bestand was het verschil één regel: `serviceWorkerVersion` met
  een **willekeurig** getal (waargenomen `276285049` vs `1177672334` vs
  `2704400220`). Dat getal is niets meer dan de cache-buster in de queryparameter
  `flutter_service_worker.js?v=…` van een door Flutter zelf **afgeschreven**
  service-workermechanisme. Het staat niet in de service-worker zelf — die is
  over builds heen byte-identiek.
- **Nul** bestanden bevatten het absolute bouwpad. Er lekt geen machinepad in de
  uitvoer.

Met andere woorden: de webbundel was al reproduceerbaar op één willekeurig
getal na.

**Reparatie.** Dat ene getal is weggewerkt in dezelfde stap die `.last_build_id`
al verwijderde: `normaliseerServiceWorkerVersie` in `pack_web_release.dart`
vervangt het door een waarde die is afgeleid van de sha256 van de service-worker
(`serviceWorkerVersieUit`). Bewust afgeleid en niet een vaste constante: het
getal is een cache-buster, en een vaste waarde zou reproduceerbaar zijn maar de
cache-invalidatie breken — de waarde moet mee veranderen als de service-worker
verandert, en verder nooit. Afgeleid van de inhoud klopt allebei.

**Eindtoets.** Na de reparatie leveren schone builds die achter elkaar en
zonder andere last draaien een byte-voor-byte identieke bundelinhoud op —
`main.dart.js`, CanvasKit, service-worker, fonts, assets en de nu-genormaliseerde
`flutter_bootstrap.js`, alles gelijk, inclusief de zelf-digest van de
bundelinterne `SHA256SUMS`. Drie geïsoleerde builds achter elkaar gaven exact
dezelfde `main.dart.js`. Herbouwen uit de bron geeft, in dezelfde bouwomgeving,
precies dezelfde bytes.

### Een tweede waarneming — en de correctie ervan

> **Gecorrigeerd 2026-08-01 (#1033).** De eerste lezing weet een sprong in
> `main.dart.js` aan de native-assetslaag en wees het pinnen daarvan aan als
> sluitstuk. Een vervolgtoets vond een mundane oorzaak — bronvervuiling — en trekt
> die conclusie in. De oorspronkelijke tekst is vervangen door wat er werkelijk
> aan de hand was; de fout zelf blijft benoemd, want hem verzwijgen zou dezelfde
> les een tweede keer laten kosten.

**Wat er tijdens #1027 werd gezien.** `main.dart.js` nam op enig moment een tweede,
daarna stabiele waarde aan (`23ca67d6…` → `f04ac94e…`). Dat werd toegeschreven aan
de native-assetslaag (de `dartcv4`/OpenCV-hook), omdat de sprong samenviel met een
gelijktijdige host-build.

**Wat #1033 vaststelde.** Die meting liep in een **gedeelde werkkopie** waarin een
parallelle sessie een `lib/`-bestand (`preview_panel.dart`) bewerkte tussen builds
door — en een `lib/`-wijziging gaat recht de dart2js-uitvoer in. Gecontroleerd
nagebouwd in een geïsoleerde kopie op de ongewijzigde bron:

- Drie schone build+pack-cycli gaven **elke keer** `23ca67d6…`, mét de
  host-native-assets-hook (`dart run pack`) die elke cyclus draaide. dart2js is dus
  deterministisch, en die hook raakt de web-uitvoer niet.
- Precies díe ene `lib/`-edit toepassen en opnieuw bouwen gaf `f04ac94e…` — de
  "tweede waarde" uit #1027.

De sprong was dus een **bronwijziging**, geen bouwomgevingsvariabele. En de
native-assetslaag kán de web-uitvoer architectonisch niet eens raken: het is een
*host*-FFI-bibliotheek, en web heeft geen `dart:ffi`, dus zij is geen invoer van
de web-build.

**De les.** Een reproduceerbaarheidstoets hoort in een geïsoleerde, schone
werkkopie — nooit in een gedeelde map waar een andere sessie de bron onder je kan
wijzigen. De #1027-conclusie "de native-assetslaag is de resterende variabele"
was een artefact van een vervuilde meting en is hiermee ingetrokken.

**Wat wél de eerlijke restrand is.** Reproduceerbaarheid geldt altijd ten opzichte
van een vastgelegde bouwomgeving, nooit "op elke machine met elk gereedschap".
Gepind/geborgd: de toolchain (Flutter 3.44.8, `make check-toolchain`), de
afhankelijkheden (`pubspec.lock` + `--enforce-lockfile`), en de bron (gecommit) —
zodat een herbouw op dezelfde machine uit dezelfde bron byte-identiek is
(getoetst — drie cycli op één machine). *Niet* rechtstreeks getoetst is een
build in een **andere bouwomgeving**: vooral een ander besturingssysteem, maar
strikt genomen ook een andere machine (ander bouwpad, `HOME`, locale). De grootste
machine-specifieke invoer — het absolute bouwpad — is empirisch uitgesloten (nul
lekken, #1027), en dart2js hoort platformonafhankelijk te zijn, maar dat is op één
machine gemeten. Dat is dezelfde restrand als het nog niet meten van de Linux-tak
— klein, en van een andere orde dan "een ongepinde native-assetslaag".

De winst blijft scherp: de **intrinsieke** willekeur die élke build liet
verschillen (de service-workerversie) is weg, en binnen een vaste bouwomgeving is
de bundel aantoonbaar bit-voor-bit reproduceerbaar.

### Twee lagen, en welke ertoe doet

Er zijn twee `SHA256SUMS` in het spel, en het onderscheid is belangrijk:

- De **bundelinterne** `build/web/SHA256SUMS` (geschreven door
  `pack_web_release.dart`) hasht de **inhoud** van elk bundelbestand. Die is nu
  reproduceerbaar en na te lopen met `dart run tool/pack_web_release.dart --check`
  of gewoon `sha256sum -c`.
- De **release-brede** `dist/SHA256SUMS` (geschreven door de `publiceren`-job en
  getekend met minisign) hasht de **archiefbestanden** — de `.tar.gz` en `.zip`.

Het `.tar.gz`-omhulsel om de webbundel is *niet* byte-reproduceerbaar: `tar`
legt mtimes en permissies vast en `gzip` zet een tijdstempel in zijn kop. Dat is
bewust niet gerepareerd, want het is **niet nodig voor de vertrouwensketen**. Wie
verifieert, pakt het archief uit en vergelijkt de *inhoud* met een eigen herbouw;
de mtime-bytes van het omhulsel spelen in die vergelijking geen rol. De
minisign-handtekening bewijst dat je het gepubliceerde archief hebt; de
inhouds-reproduceerbaarheid bewijst dat die inhoud uit de bron komt. Samen is dat
een complete keten zonder dat het omhulsel byte-identiek hoeft te zijn.

Een deterministische `tar`/`gzip` (`--sort=name --mtime=@0 --owner=0 --group=0
--numeric-owner` plus `gzip -n`) zou het archief zélf ook reproduceerbaar maken
en is een kleine, afgebakende ingreep — maar hij voegt aan de vertrouwensredenering
niets toe boven de inhoudslaag, en hij is afhankelijk van de `tar`/`gzip`-versie
op de machine van de verifieerder, wat juist een nieuwe bron van "bij mij komt er
iets anders uit" is. Daarom niet gedaan; vastgelegd als overwogen en gewogen.

## Per platform: haalbaarheid en oordeel

| Platform | Haalbaarheid bit-voor-bit | Oordeel |
|---|---|---|
| **Web** | Bereikt binnen een vaste bouwomgeving (getoetst); alleen cross-OS niet gemeten | **Gedaan (web-inhoud)** — intrinsieke willekeur weg, determinisme getoetst; enige restrand is cross-OS |
| **Linux** | Waarschijnlijk dichtbij; niet hier getoetst | **Gewogen: niet nu** — redelijke opbrengst, maar buiten deze meting |
| **macOS** | Per definitie niet door een derde | **Gewogen: nee** — notarisatie is serverside |
| **Windows** | Vergt buildvlaggen; cross-gebouwd op de spiegel | **Gewogen: niet nu** — hoge last, lage opbrengst |

**Web** — zie boven. De tak waar bit-voor-bit binnen een vaste bouwomgeving
haalbaar én goedkoop bleek, en die het dichtst bij de kernwaarde ligt (de
webversie draait op librekat.nl; wie hem wantrouwt kan hem, mits dezelfde
toolchain, narekenen). De intrinsieke willekeur is weg en het determinisme is
getoetst; de enige niet-gemeten restrand is een build op een ander
besturingssysteem (zie [Een tweede waarneming](#een-tweede-waarneming--en-de-correctie-ervan)).

**Linux** — niet in deze ronde gemeten, en dat staat er als "niet vastgesteld"
in plaats van dichtgepraat. Wat bekend is: een Flutter-Linux-bundel is
grotendeels dezelfde dart2js-loze AOT-constructie met een `bundle/`-boom; de
bekende obstakels zijn ELF-build-ids en tijdstempels in de tar. De redelijke
verwachting is "dichtbij, met een paar normalisaties", maar zonder de dubbele
build op een Linux-doel is dat een vermoeden, geen bevinding. Heroverweging staat
open zodra de Linux-tak toch gemeten wordt (bijvoorbeeld via
`.forgejo/workflows/linux-gate.yml`).

**macOS** — hier is het oordeel principieel, niet inspanningsgebonden. Het
artefact dat wij uitleveren is **getekend en genotariseerd**: Apple hangt er een
serverside afgegeven notarisatieticket aan (`stapler`), en dat ticket kan een
derde per definitie niet reproduceren. Ook de onderliggende Mach-O draagt een
`LC_UUID` en een codesign-zegel die aan de ondertekenaar hangen. Bit-voor-bit
reproduceerbaarheid van het gepubliceerde macOS-artefact is dus geen kwestie van
moeite maar van definitie — en het is ook niet nodig, want juist voor macOS is de
notarisatie de herkomstgarantie. Wie het toch wil narekenen, doet dat op de
*ongetekende* bundel vóór notarisatie, en dat is een aparte, hier niet
uitgewerkte oefening.

**Windows** — de PE-kop draagt een `TimeDateStamp` die zonder de linkervlag
`/Brepro` niet-deterministisch is, en de tak wordt bovendien op de GitHub-spiegel
gebouwd (`.github/workflows/release.yml`), niet op de forge. Bit-repro zou een
buildvlag-ingreep in een cross-gebouwde tak vergen voor het platform met de minste
opbrengst (Windows is toch al ongetekend en leunt op `SHA256SUMS` + de
"Run anyway"-uitleg, #1013). Hoge last, lage opbrengst; niet nu.

## SLSA-weging

De issue vraagt SLSA-provenance te wegen "als tussenstap of alternatief" en het
niveau (build L1–L3) af te zetten tegen wat een lokaal-eerst project zonder
gehoste CI kan waarmaken. SLSA draait om één ding: het bouwplatform geeft
provenance af die de *consument* kan verifiëren zónder de bouwer op zijn woord te
geloven.

- **Build L1 (provenance bestaat).** De forge-workflow zou een provenance-bestand
  kunnen afgeven (bron, tag, parameters). Maar ongetekend is dat forgeerbaar, en
  het voegt weinig toe boven de al met de hand getekende manifest. Lage waarde
  hier.
- **Build L2 (gehost platform tekent de provenance).** Dit vraagt een sleutel op
  de runner die de bouwstappen niet kunnen lezen. Dat botst frontaal met de vaste
  lijn van dit project: de minisign-sleutel staat **bewust off-runner** en wordt
  met de hand lokaal gebruikt (least-privilege, dezelfde grond als #1013 en de
  macOS-notarisatie). Een sleutel op de runner zetten om L2 te "halen" zou de
  beveiliging verzwakken om een label te winnen. De huidige, off-runner getekende
  manifest is voor dit dreigingsmodel eerder *sterker* dan runner-gehouden L2.
- **Build L3 (geharde, geïsoleerde bouwdienst).** Vergt een gehoste,
  geïsoleerde, niet-vervalsbare bouwomgeving. Voor één zelf-gehoste runner en één
  beheerder is dat niet haalbaar en niet zinvol.

**Conclusie.** De kern die SLSA levert — "vertrouw de bouwer niet" — wordt in dit
project beter bediend door **reproduceerbaarheid** dan door een
provenance-attestatie: reproduceerbaarheid haalt de bouwer uit de vergelijking,
terwijl de niveaus die écht een sterkere garantie geven (L2/L3) sleutels of
isolatie vragen die botsen met least-privilege en niet passen bij één
vertrouwenswortel. Daarom geen aparte SLSA-attestatie nu; de inspanning gaat naar
de reproduceerbaarheid die hier wél iets waarmaakt.

## Besluit en verhouding tot bestaande waarborgen

Complementair aan de minisign-handtekening en de bronroute, geen vervanging.

- **Web: intrinsieke willekeur weg, reproduceerbaar binnen een vaste
  bouwomgeving.** De enige-per-build-variabele (`serviceWorkerVersion`) is
  weggewerkt in `pack_web_release.dart` en de herbouw-en-vergelijk-route staat in
  [`docs/BUILD.md`](../docs/BUILD.md) §"Reproducible builds (web)". Bewust **geen
  poort**: een dubbele schone build als `make check`-stap zou minuten kosten bij
  elke commit, en de toolchain is al gepind — het is een *uitvoerbare,
  gedocumenteerde* verificatie (zoals `pack_web_release.dart --check` en de
  adviserende DAST), niet een stille claim. Determinisme getoetst; de enige
  niet-gemeten restrand is cross-OS (zie [Een tweede waarneming](#een-tweede-waarneming--en-de-correctie-ervan)).
  De eerder hier aangewezen "native-assets pinnen" bleek een vals spoor (#1033).
- **Desktop: gewogen weg** met heropen-trigger. Bit-repro is hoge inspanning en,
  voor macOS, principieel onmogelijk voor een derde; handtekening, notarisatie en
  de getekende manifest blijven de herkomstgarantie. Heropenen: als de Linux-tak
  toch gemeten wordt, of als een reproduceerbaar desktop-artefact een concrete
  eis wordt.
- **SLSA: gewogen weg** met reden (zie boven). Heropenen: als er een tweede,
  onafhankelijke bouwer of een externe verifieerder bijkomt — dan kantelt de
  waarde van een aparte, verifieerbare provenance-attestatie, en is deze weging
  het eerste wat herzien moet worden.

Dit dicht het reproduceerbaarheidsdeel van ENISA-punt O1 voor de tak waar het
haalbaar was, en legt voor de andere takken de weging vast in plaats van ze open
te laten. De [`risicoafweging.md`](risicoafweging.md) noemde
"distributie-integriteit" als het risico dat bij releases met artefacten bijkomt;
de handtekening (#1014) en nu de web-reproduceerbaarheid zijn samen het antwoord
daarop.

## Het aangewezen vervolg

*(Herzien 2026-08-01, #1033.)* Eerder stond hier "pin de native-assetslaag" als
sluitstuk voor web-reproduceerbaarheid over machines heen. Dat is ingetrokken: de
native-assetslaag raakt de web-uitvoer niet (geen `dart:ffi` op web), en de
waarneming die haar aanwees bleek bronvervuiling (zie [Een tweede
waarneming](#een-tweede-waarneming--en-de-correctie-ervan)).

Wat wél resteert voor web-reproduceerbaarheid over machines heen is smal: **het
meten van een build op een ander besturingssysteem** (dart2js hoort
platformonafhankelijk te zijn, maar dat is hier op één OS getoetst). Dat valt
samen met het al bestaande punt "de Linux-tak meten" en hoort onder de
veilige-distributievraag #520. Bewust vastgelegd, niet stilzwijgend weggelaten.

## Wanneer dit opnieuw langs moet

- Bij een **Flutter-upgrade** — een nieuwe engine of dart2js kan het web-
  determinisme opnieuw maken of breken. De herbouw-en-vergelijk-route in
  `docs/BUILD.md` is dan de toets; `normaliseerServiceWorkerVersie` is robuust
  tegen een verdwijnend service-workermechanisme (no-op), maar een nieuwe bron
  van niet-determinisme zou opnieuw gemeten moeten worden.
- Bij **meten van de Linux-tak** — dan verschuift dat platform van "niet
  vastgesteld" naar een oordeel.
- Bij een **tweede bouwer of externe verifieerder** — dan kantelt de SLSA-weging.
