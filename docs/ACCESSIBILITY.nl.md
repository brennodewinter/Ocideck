> 🤖 Machinevertaling — het Engelse bronbestand is leidend.
>
> _Machine translation — the English source document is authoritative. _

# OciDeck — Toegankelijkheid

> **Status:** beschrijving van de huidige stand van wat wel en niet toegankelijk is · **Status laatst nagekeken:** 2026-08-29 · **Uitgegeven door:** Stichting LibreKAT

Wat OciDeck voor toegankelijkheid doet, en — de langere helft van dit document —
wat het niet doet. Beide helften staan hier met opzet. Een gereedschap dat enkel
zijn toegankelijkheidsfuncties opsomt, laat de lezer de hiaten ontdekken op het
slechtst denkbare moment, en dat is meestal het moment waarop het deck al
verstuurd is.

De korte versie: **de editor is gebouwd om met een toetsenbord en een
schermlezer bruikbaar te zijn en om opschaling te doorstaan; de exports zijn geen
toegankelijke documenten.** PDF en PPTX komen als plaatjes uit OciDeck.

## Wat er staat

**Tekst opschalen tot 200%.** *Instellingen → Algemeen → Toegankelijkheid*
schaalt alle interfacetekst tussen 100% en 200%, bovenop wat het besturingssysteem
al vraagt (`uiTextScale` in `AppSettings`). Dit is de WCAG 1.4.4-eis voor het
vergroten van tekst. Het diacanvas is bewust uitgesloten: een dia is een vast
16:9-ontwerpvlak, dus wat je ziet blijft wat je presenteert en exporteert.
De documentatielezer heeft daarbovenop zijn eigen **A− / A+**-knop, omdat het
lezen van een gids en het bedienen van een editor om verschillende maten vragen.

**Schermlezerlabels waar de interface geen tekst is.** Diaminiaturen dragen een
samengesteld label ("Dia 3/12: <titel>", plus de overgeslagen-staat, of de dia
wordt achtergehouden door zijn TLP-classificatie en op welk niveau, en of hij
notities heeft) in plaats van als naamloze afbeelding te worden aangekondigd.
Beide redenen waarom een dia het publiek niet bereikt worden uitgesproken, en
apart uitgesproken, omdat het dimmen en de twee gekleurde vlaggen die op het
scherm dezelfde boodschap dragen hier geen nut hebben. Grafieken tonen hun
gegevens als tekstalternatief (`_semanticsLabel` in `chart_preview.dart`), zodat
een grafiek leesbaar is en niet slechts aanwezig. Knoppen met alleen een pictogram
dragen een naam.

**Beeldverwijzingen zijn zonder zicht te lezen.** Een beeldverwijzing knoopt een
bullet aan een plek in de afbeelding (*een genummerde speld, een gemarkeerd
gebied of een pijl*), en die knoop is programmatisch, niet alleen visueel. In de
app is elke markering een knoop met een naam — *verwijzing, beschrijving*, plus
*target n van m* als één verwijzing meerdere markeringen heeft — en de bullet
die hem bezit draagt dezelfde beschrijving, zodat het lezen van de bullet de
betekenis één keer meeleest. De zichtbare letter op de markering blijft buiten
de boom, want die staat al vooraan in de naam. Presenteer je met stapsgewijs
onthullen, dan is een groep die nog niet onthuld is **afwezig uit de
accessibility tree**, niet enkel doorzichtig, en wordt elke stap aangekondigd
met de bullet en hoeveel markeringen meekwamen. De HTML-export draagt hetzelfde
in ARIA: `role="img"` met dezelfde naam op elke markering, een visueel verborgen
beschrijving met een vast id, en `aria-describedby` op de bullet. De
HTML-export stapt niet — hij toont elke groep tegelijk — en heeft daarom geen
live region. Het contract is `docs/design/IMAGE_CALLOUTS.md` §12; de poort is
`test/callout_accessibility_test.dart`.

**Een test die de build laat falen — en precies hoeveel van de app hij ziet.**
`test/accessibility_labels_test.dart` stelt vast dat elke knop een toegankelijke
naam heeft (WCAG 4.1.2). Hij werkt op twee manieren, en het verschil doet ertoe:

- hij **pompt zes editors** (opsomming, tabel, tijdlijn, twee afbeeldingen,
  ondertekening, video) en inspecteert de echte semantiekboom. Dat is zes van de
  26 editors, geen van de 41 dialogen, en niet de presentatiemodus. Wat hij niet
  pompt, ziet hij niet;
- hij **scant de bron** van heel `lib/` op één specifieke fout:
  `Tooltip(message: …, child: IconButton(…))`. Dat leest als een benoemde knop
  en is dat niet — een `Tooltip` om een knop heen hangt er geen semantisch label
  aan; alleen `IconButton(tooltip:)` doet dat. Deze helft is goedkoop en dekt
  alles, ook de code die niemand pompt.

*Gecorrigeerd 2026-07-22 (#586). Deze regel zei dat de test "de interface
doorloopt" en dat hij drie gebreken had gevonden. Beide waren te royaal. Hij
pompt zes widgets, en achter die widgets stond juist de fout waartegen hij waakt
**23 keer meer** — zeven in de hoofdlayout, vier in het voorbeeldpaneel, vier in
de presentatie-overlays, waaronder de knop waarmee je een presentatie verlaat, en
de hele driewegs-tekentoolbar. Wie een schermlezer gebruikte hoorde "knop" bij de
afsluitknop. De 23 zijn hersteld en de bronscan is wat de vierentwintigste
tegenhoudt; maar de eerlijke samenvatting van de dekking zijn de twee opsommingen
hierboven, niet "doorloopt de interface".*

**Alt-tekst als een eersteklas veld.** De editors voor afbeelding, twee
afbeeldingen en opsomming-met-afbeelding hebben een **Alt-tekst**-veld los van
het zichtbare bijschrift. Een schermlezer kondigt de alt-tekst aan als die is
ingevuld, valt terug op het bijschrift, en daarna op een generiek "afbeelding";
de diakwaliteitscontrole port net zolang tot een van de twee aanwezig is.
Alt-tekst wordt in de Markdown opgeslagen, dus die overleeft een rondgang.

**Aankondigingen van diawissels tijdens het presenteren**, zodat een
schermlezergebruiker die een presentatie volgt te horen krijgt welke dia er staat.

**Toetsenbordbediening van de onderdelen die makkelijk te missen zijn.** De
paneelscheiding tussen de dialijst en de editor neemt focus met `Tab` en verandert
van grootte met `←`/`→`. De dialoog voor dia toevoegen is volledig met het
toetsenbord te bedienen, en tabben tussen de typekaarten stuurt ook de uitleg
onder het raster aan, zodat het toetsenbord dezelfde informatie bereikt als de
muis. Algemene navigatie en de sneltoetsen staan in
[SHORTCUTS.md](SHORTCUTS.md).

**Uitleg gehecht aan de bediening, niet alleen ernaast.** Elke kaart in de dialoog
voor dia toevoegen draagt de uitleg van zijn type als schermlezerhint, omdat de
strook onder het raster een aparte widget is die een lezer die de kaarten aflopt
nooit passeert. Dezelfde redenering zet de melding over de opslagvoortgang op de
chip in de statusbalk als live regio: het is een uitspraak over wat er gebeurt,
dus hij wordt aangekondigd zonder de focus ernaartoe te verplaatsen.

**Een menubalk op macOS.** `PlatformMenuBar` geeft de systeemmenubalk de acties
van de app — bestand, bewerken (inclusief knippen/kopiëren/plakken), presentatie,
venster en help. Een menubalk is een vlak dat van begin tot eind af te lopen is
om te ontdekken wat een programma kan, in plaats van een toolbar afzoeken naar
pictogrammen. Onderdelen die een open presentatie nodig hebben worden grijs in
plaats van te verdwijnen, zodat de lijst die een gebruiker leert dezelfde lijst
blijft. Windows en Linux krijgen hun menu van de desktopomgeving; de browserbuild
heeft er geen.

**Markeringen die niet op kleur alleen rusten.** Waar de app naar een deel van
een tekst wijst, koppelt hij de kleur aan een vorm. De correctie na een getypt
vraagantwoord streept door wat er te veel stond en onderstreept wat ontbrak,
zodat de twee regels ook uit elkaar te lezen zijn voor wie rood en groen slecht
onderscheidt. Bij een afbeeldingsparenvraag dragen de twee plaatjes een
**A**/**B**-badge die een ✓ of ✗ wordt, in plaats van alleen een groene of rode
rand.

**Beperkte beweging in een geëxporteerde cockpit.** De opstartsequentie van de
offline-HTML van de authentieke cockpit heeft een `prefers-reduced-motion`-tak:
het wordt een korte doorzichtigheidswisseling in plaats van de volledige
helderheidspuls en het gestapelde verschijnen. Een auteur kan ook **Animeren bij
binnenkomst** per cockpitdia uitzetten, wat de presentator de tot rust gekomen
uitlezingen meteen laat tonen. PDF en PPTX zijn statische afbeeldingen en dragen
de sequentie nooit.

**Contrastcontrole van het deck dat je maakt.** Het diakwaliteitspaneel toetst
bodytekst, titels, tabeltekst en -koppen, codekleuren en de accentkleur tegen hun
achtergronden op WCAG 2.1 AA, en meldt wat faalt. Dit helpt het *publiek* van je
deck in plaats van jou — maar het is de controle die de meeste presentatiegereed­schappen
helemaal niet doen.

**En de gebundelde stijlprofielen worden er ook aan gehouden.** *(Toegevoegd
2026-08-27, #1818.)* De kleuren van de auteur meten en tegelijk standaarden
uitleveren die diezelfde lat niet halen, is geen kleine inconsistentie — dan is
de app het met zichzelf oneens, en de auteur kan er vanuit de `.md` niets aan
doen omdat styling daar bewust niet in staat (FILE_FORMAT §3.2). Het
standaardprofiel deed precies dat: een niet-afgevinkt checklistvakje op 1,5:1
tegen een ondergrens van 3:1, waardoor elk deck met een checklist opende op een
waarschuwing waar niemand iets mee kon. `theme_profile_contrast_test` haalt nu
elk gebundeld profiel door dezelfde analyzer als het kwaliteitspaneel en eist nul
bevindingen. Bewuste uitzonderingen staan daar bij naam, met reden en
issuenummer, en een tweede test faalt zodra een uitzondering niet meer nodig is —
zodat hij wordt opgeruimd in plaats van stilletjes de volgende fout te dekken.
Vandaag staat er één: het Vigilis-merkgeel als linkkleur (#1819).

## Wat er niet staat

**PDF- en PPTX-exports zijn afbeeldingen.** Dit is de grootste beperking in dit
document en de beperking die er het waarschijnlijkst toe doet.
`export_service.dart` rendert elke dia naar een bitmap en verpakt die dan: de PDF
is één full-bleed `pw.Image` per pagina, en de PPTX is één `<p:pic>` per dia.
Gevolgen, ronduit gezegd:

- er is **geen tekstlaag**, dus er is niets te selecteren, te doorzoeken of door
  een schermlezer te lezen;
- er is **geen alt-tekst** in de PDF, ook niet voor de afbeeldingen die je in
  de editor zorgvuldig alt-tekst gaf. PPTX en ODP zijn sinds 29-08-2026 een
  gedeeltelijke uitzondering: de afbeelding van elke dia draagt een beschrijving
  op de vorm (`descr` in PPTX, `<svg:desc>` in ODP) met de alt-tekst van het
  beeld en de beschrijvingen van de beeldverwijzingen op die dia. Dat is één
  regel tekst per dia, geen structuur — het verschil tussen betekenis die
  overleeft en betekenis die weggegooid wordt, niet tussen ontoegankelijk en
  toegankelijk;
- er is **geen structuur** — geen koppen, geen leesvolgorde, geen tags, geen
  tabelsemantiek;
- het gegevensalternatief van een grafiek, dat de editor toont, overleeft niet.

Als de ontvanger een toegankelijk document nodig heeft, zijn de eerlijke routes
vandaag de **Markdown** (die tekst is, zijn koppen behoudt en de alt-tekst draagt)
of de **HTML-export** (echte tekst in een browser, al is die evenmin tegen WCAG
gebouwd). PPTX-sprekernotities zijn echte tekst en reizen wél mee.

**De interactieve onderdelen van een keuzemenu-slide zijn met het toetsenbord te
bedienen.** *(Opgelost 2026-08-18; stond hiervoor als bekend gat.)* Tijdens het
presenteren zijn een menublok dat springt en de categoriebalk erboven allebei een
knop: `Tab` en `Shift + Tab` lopen erlangs — eerst de categorieën, dan de blokken
in leesvolgorde — `Enter` of de spatiebalk volgt de sprong of wisselt van
categorie, en `Escape` geeft de toetsen terug aan de dia, zodat je meteen weer
kunt bladeren. Het onderdeel met de focus krijgt een accentring met een halo
eromheen, ruim genoeg om vanaf de achterste rij te zien. Een schermlezer meldt ze
als knop, met de uitleg achter het label (`Prijzen. Wat het kost`), en de tekst
ín de kaart wordt uitgesloten zodat er niets dubbel wordt voorgelezen.

Enter en de spatiebalk betekenen in de presentator óók "volgende dia". Dat botst
niet: een toetsaanslag gaat eerst naar het onderdeel met de focus en pas daarna
naar de presentator. Staat de focus nergens, dan bladert de spatiebalk gewoon
door. De pijltjestoetsen blijven altijd van de presentatie — die onderscheppen
zou betekenen dat je met de focus op een blok niet verder kunt.

De focusring is van de presentator en reist niet mee naar het beamervenster: daar
zijn de blokken niet aanklikbaar, dus ook niet focusbaar. Los daarvan bereikt de
gewone navigatie (pijltoetsen, het diaraster, springen naar een dia) elke slide
waar een menu naar wijst, dus een menu is nooit de enige route naar een slide.

**De HTML-export is niet op toegankelijkheid getoetst.** Hij levert echte tekst
en koppen, wat al veel meer is dan de bitmapformaten, maar niemand heeft het
kleurcontrast, de focusvolgorde of de landmarkstructuur gecontroleerd.

**De eigen kleuren van de app, en de lat die hij op je dia's legt.** *(Audit
afgerond 2026-07-23, #606; voor het eerst gemeten 2026-07-22.)* OciDeck meet het
contrast van je deck tegen WCAG AA en meldt wat tekortschiet, dus zijn eigen
interface kan zich daar maar beter aan houden. Dat deed hij niet, en de
oplossing bleek minder om hertinten te draaien dan om twee dingen uit elkaar
houden.

**De scheidslijn is chrome versus inhoud, niet licht versus donker.** Tekst die
je *in de app* leest volgt het uiterlijk van de app. Inkt die *op een dia* landt
niet — dat kan niet, omdat een dia identiek moet renderen in het voorbeeld op het
scherm en in een headless export-isolate waar de uiterlijkinstelling niet bestaat.
Een thema-volgende kleur daar zou twee verschillende PDF's van één deck opleveren
(PENTEST_MIAUW §11).

Dus elk van de ongeveer tweehonderd toepassingen werd als het een of het ander
gelezen:

- **Interfacetekst en -pictogrammen verhuisden naar modus-bewuste tokens.**
  `accent` (`#2563EB`), `navy` (`#1C2B47`) en `teal` (`#2E7D64`), plus het rood
  en groen van de ernst- en statuspaletten, verfden tekst in dialogen, editors,
  panelen en de shell — waar op een donker oppervlak het blauw 3.3:1 haalt en het
  marine bijna verdwijnt. Ze gebruiken nu `accentFg`, `brandFg`, `tealFg`,
  `dangerFg` en `successFg`, die elk 4.5:1 halen in de modus die ze verven.
- **De vaste kleuren zelf veranderden niet.** Ze vullen nog steeds oppervlakken,
  tekenen randen, verven verlopen en renderen binnen dia's. De golden tests
  bevestigen het: elke dia rendert byte-identiek aan voorheen.

**En de meting was fout, wat niemand vleide.** De eerste ronde mat elk vast token
tegen `AppTheme.paper` — het *interface*-oppervlak — en noteerde zeventien
donkere-modusfalen. Maar de ernstkleur van een bevinding wordt gelezen op een
**dia**, die wit is. Gemeten tegen het oppervlak waar hij daadwerkelijk op zit,
en tegen de lat die daadwerkelijk geldt:

- veertien tokens zijn **tekst** op een dia (status­labels van checklist, scope en
  scorekaart) — die halen allemaal 4.5:1 op wit;
- twee zijn helemaal nooit tekst. `severityHigh` (`#EA580C`) en `severityMedium`
  (`#D97706`) verschijnen als een 6%-tint achter de kopkaart van een bevinding,
  als de randstreep ernaast, en als de vulling van een badge waarvan het label
  wit, vet en ongeveer 30px is op een dia van 1280 breed. Voor een grafisch object
  (WCAG 1.4.11) en voor grote tekst (1.4.3) is de lat 3:1, en die halen ze met 3.6
  en 3.2.

Dus er is **geen contrastbasislijn meer over** — niet omdat de schuld werd
afgeschreven, maar omdat het merendeel een categoriefout was en de rest hersteld
is. Dat ronduit zeggen doet er meer toe dan het getal: een basislijn die schuld
noteert die niet bestaat maakt de posten die wél bestaan ongeloofwaardig.

**En de regel snijdt ook de andere kant op, wat de visuele beoordeling opving.**
De diavoorbeelden verfden hun grijzen met de *modus-bewuste* leischaal — op een
canvas dat wit blijft. In de donkere modus kwam `slate700` op **1.3:1** uit en
`slate500` op 2.1:1, zodat de tekst van een checklist, een scopematrix en een
bevindingensamenvatting bijna verdween. Dat is de simpelste vorm van waar dit
document over gaat: de app die op de eigen dia's van de gebruiker de lat faalt die
hij hun oplegt.

Erger dan onleesbaar, hij **liep uiteen met de export**. De HTML-export draait
zonder thema en schrijft altijd de lichte waarden; de exportdialoog belooft dat
de export precies gebruikt wat de editor toont. In de donkere modus was dat niet
waar. Diavoorbeelden gebruiken nu vaste inkt (`slideInk`, `slideInkMuted`,
`slideInkSoft`, …) — dezelfde waarden, niet langer bewegend.

`test/app_theme_contrast_test.dart` toetst nu twaalf dingen, en de wachters zijn
wat dit ervan weerhoudt eenmalig te zijn: de modus-bewuste tokens halen 4.5:1 in
beide modi; de dia-teksttokens halen 4.5:1 op wit; de twee accenttokens halen
3:1; de dia-inkt is identiek in beide modi; en twee bronscans wijzen
**een vaste merk- of ernstkleur gebruikt als tekst buiten de dia-rendercode** en
**een modus-bewust grijs gebruikt binnen een diavoorbeeld** af. Die twee lezen de
bron, dus de volgende `AppTheme.navy` in een dialoog — of `AppTheme.slate600` op
een dia — laat de build falen in plaats van stil terug te keren.

**Een hele klasse zat buiten dat alles, en het kostte een visuele controle van
het toestemmingsscherm om die te vinden (#744).** Elke controle hierboven meet
een kleur die iemand *koos*. Niets mat de kleuren die `ThemeData` uitdeelt
wanneer niemand kiest — en Material geeft een `TextButton` `colorScheme.primary`
als voorgrond. In het ingebouwde *Donker*-profiel is `primary` de merkkleur
`#111827`, die op het eigen `#1E293B`-oppervlak van dat profiel **1.21:1** is.
Elke tekstknop en elke link in de app, inclusief de twee routes naar de
licentietekst op het scherm dat een eerste gebruiker moet passeren, was in feite
onzichtbaar.

Het was half bekend: `app_theme.dart` droeg al de opmerking dat "in donkere
modus is primary donker (onleesbaar op donker)" — maar alleen op
`outlinedButtonTheme`. Twee regels verderop had de tekstknop helemaal geen thema.
Daarom las in *Over OciDeck* de omlijnde "Alle licentieteksten tonen" prima
terwijl de "Website van de stichting"-link ernaast dat niet deed.

De oplossing is diezelfde regel toegepast op `textButtonTheme`, plus een
`accentInk` op `AppPalette` voor de zes plekken die `colorScheme.primary`
rechtstreeks als inkt namen (de links, markeringen en citaatbalk van de
documentatielezer; de sectiepictogrammen van het toestemmingsscherm; de badge van
een bestand op afstand). `secondary` zou de voor de hand liggende keuze zijn
geweest en is fout: in het *Europa*-profiel is het accent EU-geel, dat op het
witte oppervlak van dat profiel niet beter is dan het probleem dat wordt opgelost.

De twee nieuwe controles sluiten de klasse, niet enkel het geval: voor **elk**
ingebouwd uiterlijkprofiel moet de opgeloste voorgrond van elk knopthema en van
`accentInk` 4.5:1 halen op het eigen oppervlak van dat profiel, en een bronwachter
wijst `colorScheme.primary` gebruikt als `color:` af. De eerste faalt als een
toekomstig knopthema helemaal wordt overgeslagen, wat hier daadwerkelijk gebeurde.

**Dat goed meten bracht iets ergers dan de tekst aan het licht.** Tekst op 1.21:1
is onleesbaar; een bediening die zijn eigen staat niet kan tonen is onbruikbaar.
De vulling van een aangevinkt selectievakje was `primary` (`#111827`) met zijn
vinkje getekend in `onPrimary` (`#122F60`) — **1.35:1 tegen zijn eigen vulling**.
In de donkere modus was een aangevinkt vakje niet van een leeg te onderscheiden.
En zonder ook maar ergens een `TextSelectionThemeData` nam Flutter
`colorScheme.primary` voor de tekstcursor: `#111827` op een `#1E293B`-veld. In een
applicatie die bedoeld is om te schrijven, was de cursor onzichtbaar.

Beide kwamen uit één overbelasting. `primary` in een uiterlijkprofiel is de
**merk- en titelbalkkleur** — `appBarTheme` verft de balk ermee, en in een donker
profiel *hoort* die donker te zijn. Material behandelt `ColorScheme.primary` ook
als het **accent voor interactieve componenten**, waar het in het donker licht
moet zijn. Eén waarde kan niet beide zijn, en de voor de hand liggende oplossing
(geef het donkere profiel een lichte `primaryColor`) lost het conflict niet op —
hij verplaatst het, en levert een lichte titelbalk op. De rollen zijn nu
gescheiden: in de donkere modus neemt `ColorScheme.primary` het accent van het
profiel (`#60A5FA` — 5.75:1 op het oppervlak, vinkje op 5.16:1) terwijl de balk de
merkkleur houdt. Lichte profielen zijn byte-identiek.

Nog drie controles, waarvan één die verkeerde afslag dichthoudt: een aangevinkte
bediening haalt 3:1 tegen zijn oppervlak (WCAG 1.4.11), zijn vinkje haalt 4.5:1
tegen zijn eigen vulling, de cursor haalt 3:1 tegen het veld, en de titelbalk moet
de merkkleur van het profiel houden *met een leesbare titel erop* — zodat een
toekomstige lichte `primaryColor` de build laat falen in plaats van het oog.

**Dat alles waakt over de drie ingebouwde profielen. De kleurkiezers bouwen geen
vierde.** *Instellingen → Uiterlijk* laat iedereen een profiel samenstellen uit
acht vrije kleuren, dus dezelfde fout kon met de hand worden herbouwd — een donker
accent in een donker profiel — zonder dat iets dat zou zeggen. De editor meet het
nu (#750): negen paren onder het voorbeeld, elk met de ratio die het haalt en de
lat die het moest halen, en de twee vergeleken kleuren. Hij waarschuwt in plaats
van te blokkeren; het is de eigen applicatie van de gebruiker, en de weg terug is
één kleur. Blokkeren hoort bij de export, waar het resultaat het pand verlaat.

Twee dingen over hoe het gebouwd is zijn het punt in plaats van het detail.

Het meet **het thema dat het profiel voortbrengt, niet de acht velden**. Vier van
de negen paren zijn geen velden — de voorgrond van de tekstknop, de interactieve
kleur, het vinkje erop en het label van de primaire knop worden afgeleid in
`AppTheme.fromProfile`. Een controle die de kleurkiezers op een rij zou zetten had
het profiel dat #744 veroorzaakte volmaakt in orde verklaard. En het is dezelfde
functie die de contrasttest aanroept: twee berekeningen die één vraag
beantwoorden lopen uiteen, en dan waakt de test niet meer over wat het scherm
belooft.

Het **voorbeeld vleide voorheen**. Het verfde zijn eigen kleuren via een helper
die zwart of wit koos op luminantie, terwijl de echte app `panelTextColor`
gebruikt voor de balktitel en een berekende voorgrond voor de knop — dus toonde
het een leesbare titelbalk boven een profiel dat een onleesbare rendert. Het
bouwt nu het echte thema en rendert daarbinnen, en het toont een selectievakje,
een schakelaar en een tekstknop: de drie rollen die in #744 braken en die het
oude voorbeeld wegliet. Een voorbeeld dat de fout toont is meer waard dan een
lijst getallen eronder, want het is het enige waar iemand naar kijkt voordat hij
opslaat.

*Die meting voor het eerst over de ingebouwde profielen draaien bracht meteen een
negende gebrek aan het licht dat niemand had gemeld: het label op een gevulde
knop werd gekozen met `brightness == light && luminance > 0.6 ? black : white`,
wat wit forceert in de donkere modus — ook op het lichte `#60A5FA`-accent van het
donkere profiel, op 2.54:1. Dat is de Opslaan-knop. De helderheid van het
omringende thema doet niet ter zake voor wat leesbaar is op een knop; alleen die
van de knop zelf. Zwart of wit, wat dan ook wint: 2.54 → 8.26:1, met beide lichte
profielen die precies de kleur houden die ze hadden.*

**En de app heeft drie donkere paletten, niet één.** Het thema hierboven is het
grote; de afbeeldingskiezer en de schermvullende presentatiemodus dragen elk hun
eigen, bewust buiten `AppTheme` omdat het op zichzelf staande donkere oppervlakken
zijn — wat ook de reden is dat de rauwe-kleurratchet ze vrijstelt. Wat niemand
opmerkte is dat de vrijstelling ze ook buiten elke contrastmeting plaatste: geen
van beide verscheen in ook maar één testbestand (#779).

Gemeten was het presentatorpalet in orde — zijn inkt haalt overal 9.0:1. De kiezer
niet. `textDim` kleurde **zowel** pictogrammen als tekst, en als tekst haalde het
op geen van zijn eigen zeven oppervlakken 4.5:1 (3.31 op `surface2`, 4.24 op
`bgDeepest`). Zeven plekken waren getroffen, en degene die steken zijn de
lege-staatregels — *"Zet het filter uit om alles weer te zien"* en *"Gebruik
Bladeren om afbeeldingen van elke locatie te kiezen"*. De zin die een vastgelopen
gebruiker vertelt hoe hij weer los komt was de minst leesbare tekst in de dialoog.

De zeven teksttoepassingen nemen nu `textMuted` (≥4.95:1 op elk oppervlak hier),
en het token dat achterblijft heet `iconDim`: als grafisch object heeft het 3:1
nodig (WCAG 1.4.11) en dat haalt het overal. Hernoemen in plaats van alleen
documenteren, want een `textDim` die geen tekst mag kleuren is een valstrik voor
wie er als volgende naar grijpt. `test/standalone_palette_contrast_test.dart`
houdt beide latten per oppervlak vast, plus de witte labels op de gekleurde
vullingen — dezelfde klasse als de Opslaan-knop hierboven, en voorheen ongemeten.

*Drie kleinere dingen die de visuele beoordeling aan het licht bracht, nu
hersteld: de exportdialoog was op zijn succestak gemigreerd maar niet op zijn
faaltak, zodat "de export is mislukt" op 3.1:1 zat in de donkere modus terwijl
"geëxporteerd naar…" straalde; de kop van de gebruikersnotities was een vast blauw
dat zwakker (2.4:1) was geworden dan de ondertitel eronder; en de lichte waarde
van `dangerFg` was bleek genoeg dat hij op de scorekaartchip — die zijn eigen
achtergrond tint — daalde tot 4.2:1, onder AA, voor de ene kleur die alarm
betekent.*

**Een paar blokkerende meldingen worden nog in het Nederlands opgebouwd.**
*(Herschreven 2026-07-22.)* Deze regel zei ooit dat ongeveer vijftig editorlabels
hun Nederlandse brontekst toonden. Dat is niet meer waar: die labels zijn
vertaald, de poort faalt nu op elke overtreding in plaats van af te tellen naar
een plafond, en de sleutels die de laag indirect bereiken worden in elke taal op
dekking getoetst.

Wat overblijft is smaller en structureel. De vertaallaag is gesleuteld op
letterlijke Nederlandse brontekst, dus een string die een waarde *interpoleert*
heeft geen letterlijke sleutel om op te zoeken en kan helemaal niet worden
opgezocht. Een classificatieweigering noemt het niveau in zijn eigen zin, dus die
bereikt je in het Nederlands, welke taal je ook koos. Voor wie geen Nederlands
leest is dat een toegankelijkheidsprobleem en geen cosmetisch, en het is het ergst
waar het het meest pijn doet: dit zijn de meldingen die je tegenhouden iets te
doen. Bijgehouden in #576.

**Alleen links-naar-rechts, en dat bepaalt ook je inhoud.** Er is nergens een
richtinggevoelige layoutprimitief in gebruik — `EdgeInsetsDirectional`,
`AlignmentDirectional` en `BorderDirectional` komen nul keer voor in `lib/`, tegen
negenentwintig fysieke `EdgeInsets.only(left:`/`right:`. Van de dertien plekken
die `TextDirection` noemen, hardcoderen er elf `TextDirection.ltr`, waaronder een
`Directionality`-wrapper om het **hele diacanvas** in `slide_preview.dart`
(geteld 2026-07-22).

Dat geen van de 32 interfacetalen rechts-naar-links is, is een scopekeuze. Het
scherpere gevolg is het canvas: een auteur die een Arabische of Hebreeuwse alinea
op een dia zet krijgt de verkeerde basisrichting — links uitgelijnd, leestekens
aan de verkeerde kant — ongeacht de interfacetaal die hij koos. Niets waarschuwt
hem, dus het wordt op de beamer ontdekt. Hier wordt nog niets voor gebouwd; het
staat hier opgeschreven zodat het een bekende beperking is in plaats van een
verrassing, en zodat op de dag dat iemand RTL wil het startpunt al in kaart is
gebracht. *(Toegevoegd 2026-07-22.)*

**Bredere WCAG-conformiteit wordt niet geclaimd.** Contrastverhoudingen binnen de
*applicatie-interface*, focusvolgorde over de hele app, en leesvolgorde zijn een
werkprogramma in plaats van een testbestand. Wat er is, is de vangrail hierboven
en de gebreken die hij ving. OciDeck claimt geen WCAG 2.1-conformiteit op enig
niveau, heeft geen toegankelijkheidsconformiteitsrapport, en is niet getest met
gebruikers van hulptechnologie.

**Niet geverifieerd met echte schermlezers.** De labels worden in tests via de
semantiekboom van Flutter vastgesteld. Niemand heeft OciDeck van begin tot eind
gedraaid onder VoiceOver, NVDA, JAWS of Orca, dus "draagt een semantisch label"
is bewezen en "werkt goed in de praktijk" niet.

**De afbeeldingsscan van de privacycontrole is niet beschikbaar op de
browserbuild**, wat een capaciteitshiaat is en geen toegankelijkheidshiaat, maar
het landt op dezelfde plek: zie [PRIVACY.md](PRIVACY.md) en
[HOSTING.md](HOSTING.md) §5.

**De interface en het diacanvas zijn alleen links-naar-rechts.** Geen van de 32
interfacetalen is rechts-naar-links, wat een scopekeuze is. Het scherpere punt is
dat het ook de *inhoud* bepaalt: `lib/widgets/slides/slide_preview.dart` wikkelt
het hele canvas in `Directionality(textDirection: TextDirection.ltr)`, zodat een
auteur die een Hebreeuwse of Arabische alinea op een dia zet de verkeerde
basisrichting krijgt — links uitgelijnd, met leestekens aan de verkeerde kant. Dat
treft auteurs ongeacht de taal waarin ze de interface lezen. Er zijn ook geen
richtingbewuste layoutprimitieven in gebruik (`EdgeInsetsDirectional`,
`AlignmentDirectional` en `BorderDirectional` komen nul keer voor in `lib/`, tegen
29 fysieke `EdgeInsets.only(left|right`), dus RTL later ondersteunen is een
wijziging aan layoutcode en geen vertaalklus. *(Toegevoegd 2026-07-22: dit was
waar maar nergens opgeschreven, dus het was iets wat je op de beamer ontdekte.)*

## Als je hierop steunt

- Werk in de editor met tekstschaling omhoog als je die nodig hebt; het deck
  wordt niet beïnvloed door die instelling.
- Vul **Alt-tekst** in voor elke afbeelding, ook al laten PDF en PPTX die vallen —
  de Markdown behoudt hem, en dat is waar een toegankelijke versie zou beginnen.
- Overhandig de **Markdown** of de **HTML** wanneer de ontvanger moet lezen in
  plaats van kijken.
- Meld wat niet werkt. De issuetracker staat in
  [TROUBLESHOOTING_GUIDE.md](TROUBLESHOOTING_GUIDE.md); een
  toegankelijkheidsgebrek is hier een gewoon gebrek, geen functieverzoek.

---

*Geschreven 2026-07-21, vanuit de code in plaats van vanuit de bedoeling. De
README vatte toegankelijkheid ooit samen in één regel die toetsenbordbediening en
schermlezerlabels noemde zonder te noemen dat de twee meest gebruikte
exportformaten geen van beide dragen; dit document bestaat zodat de beperking
ergens kan wonen.*
