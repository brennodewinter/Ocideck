# OciDeck — Sneltoetsen

> **Status:** referentie, actueel · **Status laatst nagekeken:** 2026-09-03 · **Uitgegeven door:** Stichting LibreKAT

`Ctrl` wordt getoond voor Windows/Linux; gebruik `Cmd` (⌘) op macOS.

## Editor (in de hele app)

| Sneltoets | Actie |
| --- | --- |
| `Ctrl/Cmd + K` | Open het opdrachtenpalet (doorzoekbare lijst met acties) |
| `Ctrl/Cmd + O` | Open een presentatie (in de dialoog: `Ctrl/Cmd`-klik of `Shift`-klik op rijen om er meerdere tegelijk te openen) |
| `Ctrl/Cmd + W` | Sluit het actieve tabblad (vraagt eerst als er niet-opgeslagen werk is) |
| `Ctrl/Cmd + S` | Sla het actieve tabblad op — een presentatie of een document (*gecorrigeerd 2026-08-08: slaat ook een document op, in elke modus, niet alleen een deck*) |
| `Ctrl/Cmd + Z` | Ongedaan maken |
| `Ctrl/Cmd + Shift + Z` | Opnieuw uitvoeren |
| `Ctrl + Y` | Opnieuw uitvoeren (alternatief) |
| `Ctrl/Cmd + F` | Zoeken (presentatie: dialoogvenster in visuele modus, balk in de editor in markdown-modus; document: balk in de editor, ongeacht waar het tabblad focus heeft) |
| `Ctrl/Cmd + H` | Zoeken en vervangen (presentatie: dialoogvenster in visuele modus, balk in de editor in markdown-modus; document: balk in de editor, ongeacht waar het tabblad focus heeft) |
| `Ctrl/Cmd + V` (in een tabelcel) | Plak een selectie uit een spreadsheet/CSV/markdown als tabel (ook `Shift + Insert`) |
| `Ctrl/Cmd + +` · `Ctrl/Cmd + -` (documentmodus) | Zoom het schrijfvlak in · uit |
| `Ctrl/Cmd + 0` (documentmodus) | Terug naar ware grootte |
| `←` `→` (in een tabelcel) | Verplaats de cursor door de celtekst; aan de rand naar de buurcel |
| `↑` `↓` (in een tabelcel) | Eén rij omhoog · omlaag, als de cursor op de eerste · laatste regel van de cel staat |
| `Tab` naar de paneelscheiding, dan `←` / `→` | Pas de breedte van het slidepaneel aan |
| `←` `↑` `Page Up` · `→` `↓` `Page Down` (klik eerst op de voorvertoning) | Vorige · volgende slide, waarbij je door de pagina's van een lange rich-text-slide of een overlopende bevinding stapt voordat je verdergaat |

*Toegevoegd 2026-07-22: `Ctrl/Cmd + F` was in de hele app gekoppeld maar alleen
vermeld onder de markdown-modus, waardoor het in de visuele modus leek alsof er
geen zoektoets was.*

*Toegevoegd 2026-09-02: `Ctrl/Cmd + W` was sinds 0.5.0 in de hele app gekoppeld
maar alleen vermeld voor de presentator, waardoor het sluiten van een tabblad
via het toetsenbord ongedocumenteerd was.*

De sneltoetsen in deze tabel werken op de editor achter wat er ook voor staat,
dus ze doen niets terwijl een dialoog, de documentatielezer of het
presentatiescherm bovenop ligt — druk eerst op `Esc`. Voor 2026-09-02 gingen
ze er dwars doorheen, en twee keer snel `Ctrl/Cmd + O` liet twee
'Presentatie openen'-dialogen op elkaar gestapeld staan (#1927).

In het **dialoogvenster slide toevoegen** verplaatst `Tab` de focus tussen de
typekaarten, kiest `Enter` de gefocuste kaart en annuleert `Esc`. De kaart die
focus heeft, stuurt ook de uitlegstrook onder het raster aan, zodat je bij het
tabben door de typen te horen krijgt waar elk type voor bedoeld is.

## macOS-menubalk

Op macOS heeft de app een echte menubalk. Het is het enige oppervlak dat laat
zien wat OciDeck kan zonder dat je weet waar je moet kijken, dus het herhaalt de
sneltoetsen hierboven in plaats van er een tweede set aan toe te voegen. Er
bestaan **alleen** daar twee sneltoetsen: `Cmd + ,` voor de instellingen en
`Cmd + N` voor een nieuw tabblad. Windows en Linux krijgen hun venstermenu van de
bureaubladomgeving en de browserbouw heeft er geen, dus deze balk wordt buiten
macOS niet gebouwd.

| Menu | Items |
| --- | --- |
| **OciDeck** | Over · Instellingen (`Cmd + ,`) · Verbergen, Anderen verbergen, Alles tonen · Afsluiten |
| **Bestand** | Nieuwe presentatie (`Cmd + N`, opent een nieuw tabblad op het welkomstscherm) · Openen… (`Cmd + O`) · Opslaan (`Cmd + S`) · Exporteren · Eigenschappen |
| **Bewerken** | Ongedaan maken (`Cmd + Z`) · Opnieuw uitvoeren (`Cmd + Shift + Z`) · Knippen, Kopiëren, Plakken, Alles selecteren (`Cmd + X/C/V/A`) · Zoeken (`Cmd + F`) · Zoeken en vervangen (`Cmd + H`) |
| **Presentatie** | Presenteren · Voorvertoning van het hele deck · Opdrachten… (`Cmd + K`, het opdrachtenpalet) |
| **Venster** | Minimaliseren · Zoomen · Volledig scherm aan/uit |
| **Help** | Gebruikershandleiding · Sneltoetsen |

Items die een geopende presentatie nodig hebben, blijven **zichtbaar maar
grijs** wanneer er geen is, en *Exporteren*, *Ongedaan maken* en *Opnieuw
uitvoeren* worden grijs wanneer ze niets te doen hebben. Grijs maken in plaats
van verbergen is bewust: een menu-item dat komt en gaat, leert niemand wat de app
kan.

Knippen, kopiëren, plakken en alles selecteren gaan naar het veld dat focus
heeft, precies zoals de toetscombinaties doen. Ze staan in de lijst omdat deze
balk het standaard macOS-menu vervangt, en het toevoegen van een menubalk mag het
bewerken van tekst niet wegnemen.

## Markdown-modus

Wanneer de editor in de **markdown-modus** staat, werkt zoeken en vervangen op de
levende markdown-tekst (inclusief front matter, slidescheidingen en
HTML-commentaar), niet op de laatst toegepaste slidevelden.

| Sneltoets | Actie |
| --- | --- |
| `Ctrl/Cmd + F` | Open de zoekbalk |
| `Ctrl/Cmd + H` | Open de zoekbalk met vervangen |
| `Ctrl/Cmd + B` | Maak de selectie vet |
| `Ctrl/Cmd + I` | Maak de selectie cursief |
| `Ctrl/Cmd + K` | Voeg een link toe rond de selectie |
| `Ctrl/Cmd + Space` | Open de doorzoekbare invoeg- en opmaakopdrachten |
| `Tab` / `Shift + Tab` | Verspring de geselecteerde bronregels naar binnen / naar buiten |
| `Enter` / `Shift + Enter` (in het zoekveld) | Volgende / vorige overeenkomst |
| `Esc` | Sluit de zoekbalk |

De zoekbalk biedt ook knoppen voor vorige/volgende, een teller met overeenkomsten
(`1 / 3`), een schakelaar voor hoofdlettergevoeligheid, **Vervangen** (huidige
overeenkomst) en **Alles vervangen**. In het bronveld zelf zet `Enter` een
opsommingsteken, genummerde lijst of citaat voort; haakjes en ronde haken worden
automatisch gepaard, en een derde backtick opent een fenced blok.

## Presentator op volledig scherm

Navigatie:

| Sneltoets | Actie |
| --- | --- |
| `→` · `Space` · `Page Down` · klik | Volgende slide |
| `←` · `Page Up` | Vorige slide |
| `Enter` | Volgende slide (of springen, als er een nummer is getypt) |
| cijfers, dan `Enter` | Spring naar dat slidenummer |
| `Backspace` | Wis het laatste cijfer van een getypt slidenummer |
| `Home` · `End` | Eerste · laatste slide |
| `G` | Overzicht in sliderooster (pijlen + `Enter` om te springen) |
| `Tab` · `⇧Tab` | Op een keuzemenu-slide: door de categorieën en blokken lopen |
| `Enter` · `Space` (met een blok gefocust) | Dat blok volgen, of categorie wisselen |
| `Escape` (met een blok gefocust) | Toetsen teruggeven aan de slide |

*Volgende* en *vorige* bewegen eerst **binnen** een slide die meer te tonen heeft:
de pagina's van een rich-text-tekst die te lang is voor één slide (de
bedieningsbalk toont dan `Slide 7 / 24 · Pagina 2 / 3`), en een tijdlijn in
stapmodus die haar volgende gebeurtenis onthult. Terugstappen naar de vorige
slide komt uit op de laatste pagina daarvan. Een vraagslide houdt *volgende* vast
totdat de vraag is beantwoord.

Weergave en timing:

| Sneltoets | Actie |
| --- | --- |
| `P` | Presentatorweergave aan/uit (notities, klok, aftelling, timer per slide, volgende slide) |
| `F` | Los het kwaliteitsprobleem op de huidige slide ter plekke op — splits een te volle slide (het overloopdeel wordt vervolgpagina's) of knip opsommingstekens met meerdere zinnen uiteen. Werkt op één en twee schermen; een geredigeerde slide wordt met rust gelaten, en een slide zonder iets op te lossen toont een korte notitie |
| `N` · `Ctrl/Cmd + N` | Paneel **mijn notities** aan/uit (notities voor ontvanger/cursus; alleen lokaal, nooit op de beamer). Binnen het paneel typt een kale `N` een letter, dus alleen `Ctrl/Cmd + N` (of `Esc`) sluit het |
| `S` | Verplaats de presentatie naar een ander scherm |
| `B` · `W` | Zwart · wit scherm |
| `K` | Stel de streeftijd / aftelling in (typ `MMSS`, `Backspace` wist een cijfer, `Enter` om te bevestigen, `0` = uit) |
| `R` | Reset de tijd en de oefenrun (verstreken en per-slide-tijden; het streefdoel blijft) |
| `A` | Automatisch doorschakelen aan/uit |
| `L` | Herhalen (opnieuw starten na de laatste slide) aan/uit |
| `M` | Automatisch doorschakelen nadat de audio van een slide is afgelopen |
| `+` · `-` | Zoom in · uit op een Mermaid-diagram op de huidige dia (ook de `+`/`-` van het numerieke deel). Op een dia zonder zoombaar diagram doen de toetsen niets, en de zoom spiegelt naar de beamer *(opgenomen 2026-08-30; de toetsen waren er al en stonden nergens)* |
| `H` · `?` | Toon het overzicht met sneltoetsen in de app |
| `Ctrl/Cmd + W` | Sluit de presentatie (werkt vanuit het presentator- en het beamervenster) |

Elke sneltoets op deze pagina werkt vanuit **beide** vensters in de
tweeschermsmodus: het beamervenster stuurt de toetsen die het zelf niet afhandelt
door naar de presentator, zodat een verdwaalde klik op het beamerbeeld het
toetsenbord niet langer dood laat liggen.

Vragen met een getypt antwoord:

Zolang een vraag van het type **getypt antwoord** open en onbeantwoord is, gaan de
toetsen naar het invoerveld in plaats van naar de sneltoetsen — anders zou een `3`
in het antwoord naar slide 3 springen. Vier toetsen worden achtergehouden:

| Sneltoets | Actie |
| --- | --- |
| `Enter` | Bevestig het getypte antwoord |
| `Page Up` · `Page Down` | Vorige · volgende slide (zodat een presentatieklikker blijft werken) |
| `Esc` | Valt door naar de normale gelaagde `Esc` hieronder — zodat het nog steeds de presentatie verlaat vanuit een open vraag |
| `Ctrl/Cmd + W` | Sluit de presentatie |

Het veld leeft aan de **presentator**-kant; het beamervenster toont wat er wordt
getypt maar kan niet worden ingetypt. Zodra het antwoord is gegeven, gaat het
toetsenbord terug naar de normale set sneltoetsen.

Annotatiegereedschap:

| Sneltoets | Actie |
| --- | --- |
| `D` | Pen |
| `T` | Markeerstift |
| `E` | Tabelbewerking aan/uit — alleen op tabellen die in de bouwer zijn gemarkeerd als *bewerkbaar tijdens presenteren*; anders werkt het als de gum |
| `⇧E` | Gum |
| `X` | Laserpointer |
| `C` | Wis de annotaties van de huidige slide |

Live tabelbewerking:

Een tabel kan tijdens een presentatie alleen worden bewerkt wanneer die in de
bouwer is gemarkeerd als **bewerkbaar tijdens presenteren** (een selectievakje per
tabel; standaard uit). Op zulke slides verschijnt een subtiel potloodicoon in de
rechterbovenhoek — gedimd wanneer uit, gemarkeerd wanneer aan — dat het bewerken
met een muis/klikker in- en uitschakelt, net als `E`.

| Sneltoets | Actie |
| --- | --- |
| `E` · potloodicoon | Tabelbewerking aan/uit |
| `←` · `→` · `↑` · `↓` | Verplaats de tekstcursor binnen de gefocuste cel |
| `Tab` · `⇧Tab` | Ga naar de volgende · vorige cel (voorbij de laatste cel wordt een nieuwe rij toegevoegd) |
| `Esc` | Verlaat tabelbewerking |

`Esc` is gelaagd: het sluit eerst het paneel **mijn notities** (`Ctrl/Cmd + N`),
verlaat vervolgens tabelbewerking, bergt daarna het actieve annotatiegereedschap
op, wist dan een getypt slidenummer, verwijdert vervolgens een zwart/wit scherm,
en verlaat ten slotte de presentatie. `Ctrl/Cmd + W` sluit de presentatie meteen,
vanuit elke modus, in overeenstemming met hoe elders in het systeem een venster
sluit.

> In de **tweeschermsmodus** (macOS, Windows, Linux) blijft het toetsenbord bij
> het laptopvenster (presentator); klikken op de beamer schakelen de slide ook
> door. `Ctrl/Cmd + W` werkt ook wanneer het beamervenster de focus heeft — het
> vraagt het presentatorvenster om de presentatie te sluiten.
