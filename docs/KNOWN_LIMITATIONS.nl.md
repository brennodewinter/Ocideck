> 🤖 Machinevertaling — het Engelse bronbestand is leidend.
>
> _Machine translation — the English source document is authoritative. _

# OciDeck — Bekende beperkingen

> **Status:** actuele lijst van wat er nog niet is · **Status laatst nagekeken:** 2026-07-31 · **Uitgegeven door:** Stichting LibreKAT

Deze pagina bestaat zodat je hem niet zelf hoeft samen te stellen. Elk punt
hieronder stond al ergens in deze repository opgeschreven; ze waren verspreid
over vijf documenten, waardoor een lezer ze één verrassing tegelijk tegenkwam.
Niets hier is nieuw — de verwijzingen zeggen waar het volledige verhaal staat.

Voor een alfa is deze lijst een pluspunt. Lees hem voordat je besluit of OciDeck
past bij wat je aan het doen bent.

## Releases zijn alfa en niet ondertekend

Releases zijn getagd (laatste `0.1.1`, 2026-07-27) en elke release draagt de app
voor alle vier de platformen — macOS, Windows, Linux en web — plus beide
SBOM-formaten en een `SHA256SUMS`-lijst. Die lijst is zelf ondertekend met
minisign (`SHA256SUMS.minisig`, publieke sleutel `minisign.pub` in de root van de
repository), zodat de checksumketen een verifieerbaar anker heeft — één
handtekening over de lijst dekt elk artefact dat erin genoemd wordt (#1014). De
macOS-build is ondertekend met een Developer ID en genotariseerd door Apple, dus
die opent normaal; de **Windows- en Linux-builds zijn niet ondertekend**, dus
Windows waarschuwt bij de eerste start. De release-notities leggen uit hoe je
elke build opent. Bouwen vanaf de bron blijft de route waarbij je onze
bouwmachine niet hoeft te vertrouwen — de toolchain is vastgepind, en
`make check-web` toetst op jouw bundel wat wij op de onze toetsen. →
[BUILD.md](BUILD.md), [FAQ.md](FAQ.md#is-ocideck-free-to-use)

**Dat Windows niet ondertekend blijft is een afgewogen besluit, geen
nalatigheid** (#1013, gesloten 2026-07-31). Authenticode-ondertekening is
beoordeeld en afgewezen. Sinds maart 2024 verleent geen enkel certificaattype —
noch OV, noch EV — directe SmartScreen-vertrouwenstatus: reputatie wordt alleen
opgebouwd door downloadvolume, dus ondertekenen zou de waarschuwing vooraf niet
wegnemen. En elke betaalde route kost óf een hardwaretoken dat de beheerder moet
bewaren, óf een ondertekeningsgeheim dat op de release-runner leeft, wat de
least-privilege-houding van het project uitsluit. De met minisign ondertekende
`SHA256SUMS` plus bouwen vanaf de bron blijven de herkomstgarantie. Mocht
downloadvolume de SmartScreen-waarschuwing ooit tot een echte drempel maken, dan
is de terugval een OV-certificaat dat met de hand op een lokale machine wordt
ondertekend — hetzelfde handmatige model als de macOS-notarisatie — nooit een
geheim in CI. Ondertekening van Linux-artefacten wordt een niveau hoger geregeld —
door de minisign-handtekening over `SHA256SUMS` (#1014) — dus een certificaat per
binary is daar evenmin nodig. →
[BUILD.md](BUILD.md#signing-status-of-the-published-artifacts),
[SECURITY.md](../SECURITY.md#release-artifact-integrity-and-signing)

*(Gecorrigeerd 2026-07-28: deze sectie zei "Er is niets uitgebracht" en
beschreef een scope-besluit waarbij alleen een webbundel zou worden uitgebracht.
Releases bevatten alle vier de platformen sinds `0.1.0` op 2026-07-25. De
ondertekenings- en notarisatiepunten blijven waar — de Windows- en
Linux-binaries zijn niet ondertekend, macOS is genotariseerd — maar de bewering
dat er geen binary bestaat is achterhaald.)*

## De exports zijn plaatjes, geen documenten

PDF en PPTX zijn één bitmap per dia: geen tekstlaag, geen alt-tekst, geen
leesvolgorde, geen selecteerbare tekst. Geef de Markdown of de HTML-export door
wanneer de ontvanger moet kunnen *lezen* in plaats van *kijken*. Er wordt geen
WCAG-conformiteit geclaimd, en er is niets getest met een echte schermlezer. →
[ACCESSIBILITY.md](ACCESSIBILITY.md)

## Voetnoten in de HTML-export staan achteraan, nooit onderaan de bladzijde

Een document kan zijn voetnoten onderaan de bladzijde vragen waar de verwijzing op
valt, en de weergave **Pagina's** en de **LaTeX**-export doen dat ook echt. De
**HTML**-export in één bestand kan het niet: een HTML-pagina is één doorlopende
stroom zonder bladzijden erin, en de enige standaard die een noot op een gedrukt
vel zou kunnen plaatsen — `float: footnote` uit CSS Paged Media — is door geen
enkele browser geïmplementeerd. De HTML-export zet de noten daarom altijd achterin
het document, genummerd, met een sprong naar elke noot en weer terug. De nummers
zijn dezelfde als op het scherm, dus er gaat niets verloren en er wordt niets
hernummerd; alleen de plaats verschilt. Die HTML naar PDF afdrukken houdt ze
achterin. Heb je de noten in een PDF écht onderaan het vel nodig, gebruik dan de
LaTeX-export (`.tex`). *(Toegevoegd 2026-08-18.)*

## De web-export (HTML) laat de overlays op de dia weg

De app tekent een laag chroom *over* elke dia heen: de voettekst (de tekst, de
positie en het paginanummer `N / totaal`), het logo, het diagonale
classificatiewatermerk, de TLP-badge per dia en de badge voor persoonsgegevens
(PrivacyKat). De voorvertoning in de bewerker, de presentatormodus en de
**PDF/PPTX**-exports tekenen die laag allemaal, omdat ze door de eigen
dia-renderer van OciDeck gaan. De **HTML**-export in één bestand geeft daarvan
alleen het logo terug: dat wordt op elke dia die het toont als ingesloten
afbeelding gelegd, in dezelfde hoek en maat als in de app. De rest laat hij weg —
hij sluit de Markdown van elke dia in voor een renderer in de browser, samen met
de kleuren en het lettertype van het thema, en draagt de classificatie van het
deck als eigen banner boven het document in plaats van als badge per dia. Een
voettekst als `www.chateau-it.nl`, het paginanummer, het watermerk en de
TLP-/PrivacyKat-badges ontbreken dus simpelweg in de `.html` — die overlaylaag is
een eigenschap van hoe OciDeck rendert, niet van de deck-Markdown, en in het
geëxporteerde bestand staat niets om haar uit te reproduceren. Heeft de ontvanger
de voettekst of de paginanummers nodig in een gedeeld bestand, geef dan de
**PDF**- (of **PPTX**-)export, die ze wél behoudt. *(Toegevoegd 2026-08-07 — de
classificatie reist mee als banner bovenaan; het logo reist sinds 2026-08-13 ook
op elke dia mee; #1330.)*

## Een presentatie importeren is een conversie, geen kopie

Een PowerPoint-, Keynote- of Impress-bestand kan worden geïmporteerd, maar het
diamodel van OciDeck is bewust eenvoudiger dan dat van de bronnen: vaste
lay-outs, één grafiek of één tabel per dia, geen vrije plaatsing. Animaties,
overgangen, samengevoegde tabelcellen, audio en de eigen kleuren en lettertypen
van de bron komen niet mee, en vrij geplaatste tekstvakken worden samengevoegd
tot leesvolgorde. Wat is weggelaten wordt op een notitiedia geschreven naast de
dia waar het vandaan kwam in plaats van aan jou over te laten om te ontdekken, en
er worden nooit gegevens uitgedund om een dia passend te maken — maar je moet het
resultaat wel controleren. Keynote is de zwakste van de drie: de inhoud ervan is
een binair formaat waarvan de betekenis in Apples applicatie leeft, dus een
`.key` die niet gereconstrueerd kan worden valt terug op de voorbeeldafbeelding
plus geredde tekst.

Eén bestand importeren laat je per verliezende dia kiezen tussen zo volledig
mogelijk overnemen, alleen de al aanwezige plaatjes behouden, en overslaan met de
notitie die zegt waarom; de wachtrij voor meerdere bestanden tegelijk vraagt niets
en neemt altijd alles over. Let op wat "alleen de plaatjes behouden" níét is:
OciDeck kan een brondia niet naar een afbeelding renderen. Dat zou betekenen dat
een externe kantoorsuite aangestuurd moet worden, wat de import bewust niet doet,
dus een dia waarvan de betekenis in de lay-out lag kan niet als een afbeelding van
zichzelf behouden blijven. *(Toegevoegd 2026-07-24.)*

De "niet geconverteerd"-notitiedia's en de foutmeldingen van de import worden in
de eigen taal van de gebruiker geschreven en zo opgeslagen, omdat de notitie
inhoud is die in het bestand leeft (#806). Eén ding blijft bewust onvertaald: de
voortgangsregel per dia "Dia 3/10" die getoond wordt terwijl een bestand wordt
gelezen. Die is vluchtig en vrijwel volledig een getal, en hem lokaliseren zou een
aparte voortgangsnaad vergen; de notitie-inhoud en de foutmeldingen, die de
gebruiker daadwerkelijk bewaart of waarnaar hij handelt, worden gelokaliseerd als
de rest van de interface. *(Toegevoegd 2026-07-24.)*

Los daarvan: de importeurs zijn alleen ooit gedraaid tegen archieven die de
testsuite zelf bouwt. Geen enkel bestand geschreven door PowerPoint, Impress of
Keynote is er doorheen gegaan. →
[USER_GUIDE.md](USER_GUIDE.md#importing-presentations-powerpoint-keynote-impress),
[design/VERIFICATION.md](design/VERIFICATION.md) punt 11 *(toegevoegd 2026-07-24)*

## Alleen van links naar rechts

De interface en het diacanvas zijn van links naar rechts. Geen van de 32
interfacetalen is van rechts naar links, en er zijn geen richtinggevoelige
lay-outprimitieven in gebruik. Dit geldt ook voor je *inhoud*: een Arabische of
Hebreeuwse alinea op een dia krijgt de verkeerde basisrichting. →
[ACCESSIBILITY.md](ACCESSIBILITY.md)

## De vertalingen zijn niet nagekeken

Ongeveer 71.500 vertalingen over 32 talen, geproduceerd tijdens AI-ondersteunde
ontwikkeling en nooit woord voor woord nagekeken door een moedertaalspreker. Een
build-poort vangt een *ontbrekende* string, niet een verkeerde. Los daarvan tonen
ongeveer vijftig veldlabels in de dia-editors en een handvol blokkerende
meldingen nog steeds hun Nederlandse brontekst, ongeacht je taalinstelling. →
[README.md](../README.md#contributing)

## De webbuild kan minder dan de desktopbuild

Geen lokale video, geen lokale CVE-database, geen WebDAV-verkenning, en een
URL-import die de browser op CORS-gronden blokkeert wordt opnieuw geprobeerd via
een proxy op de host die de app serveerde — dus die host ziet het adres dat je
typte. Het eerste bezoek downloadt een grote bundel. → [HOSTING.md](HOSTING.md),
sectie *Web build limitations to communicate*

## Marp CLI-compatibiliteit is niet geverifieerd

De opgeslagen `.md` is ontworpen om verwerkt te worden door de Marp CLI en de VS
Code Marp-extensie. Dat is niet getest tegen de echte tools — er is geen
Node-gereedschap in deze repository en geen test die er een draait. →
[FILE_FORMAT.md](FILE_FORMAT.md)

## Veel ervan heeft nog nooit een echte server ontmoet

Een werklijst van wat gebouwd is, zijn eigen tests doorstaat, en nog nooit is
beproefd tegen een echte forge, een tweede besturingssysteem of een echt rapport
wordt bewust bijgehouden. Hij is in het Nederlands. →
[design/VERIFICATION.md](design/VERIFICATION.md)

## De privacycheck is een hulpmiddel, geen garantie

Hij verkleint de kans dat persoonsgegevens onbedoeld naar buiten lekken. Hij
belooft niet dat alles gevonden wordt, en afbeeldingsscanning kan niet zien wat
een foto *voorstelt*. → [PRIVACY.md](PRIVACY.md),
[USER_GUIDE.md](USER_GUIDE.md#privacy-check)

## Schermafbeeldingen staan in de root-README

*(Gecorrigeerd 2026-07-28: hier stond "Er zijn geen schermafbeeldingen" — de
root-[`README.md`](../README.md) draagt nu schermafbeeldingen van de editor, de
presentator, grafieken, cockpit, tijdlijn, quiz, TLP-markering, donkere modus,
het privacypaneel en het exportvenster, en `docs/images/` bevat twaalf
afbeeldingen.)*

---

*Deze pagina vervangt de roadmap-sectie die vroeger in [FAQ.md](FAQ.md) stond —
een roadmap die niemand onderhoudt is erger dan geen. Wat gepland staat, wordt in
de issue-tracker beslist, in het openbaar.*
