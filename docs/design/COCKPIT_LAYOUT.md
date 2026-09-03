# Cockpit-dia: indeling van instrument, uitlezing en label

*Ontwerp, september 2026. Gebouwd in `lib/services/cockpit_layout.dart`,
`lib/widgets/slides/previews/cockpit_*.dart` en
`lib/services/marp_html/marp_html_service_cockpit.dart`.*

## 1. Aanleiding

Een presentatie met een cockpit van zes meters — "Inspanning" in
"% van maximale hartslag", "Vocht" in "ml per uur", "Tempo ten opzichte van
plan" — liet zien dat de tekst door de meters liep. De oorzaak zat in het
ontwerp, niet in één maat:

- De waarde-uitlezing was één ongebonden regel "getal+eenheid" (één regel,
  geen afkapping, breedtegrens 16× de getalgrootte) op 0,70·h ín de
  wijzerplaat — precies de hoogte van de schaalcijfers en de bandeinden. De regel
  "70% van maximale hartslag" was 1,4× de boog-Ø en liep dwars door "50",
  "100", beide boogeinden en tot op de bezel.
- Het label onder de meter was geklemd op 13–18 px, ook op een beamer van
  1920 px breed: van achter in de zaal onleesbaar.
- Naast elke ronde bezel bleef ±160 px paneel leeg.
- Klassiek kapte de regel aan de kaartrand af ("harts…"); de HTML-export liet
  hem het buurinstrument in lopen. De export had bovendien een eigen geometrie
  (dunne buis, gele vleugels op de horizon, "P 4 / B 0" met slash).

## 2. Het ontwerp: glas vrij, venster ernaast, plaatje eronder

1. **Op de wijzerplaat staat geen vrije tekst meer.** Alleen schaal, banden,
   streepjes, naald, naaf, lampjes en de twee schaalcijfers (min/max), binnen de
   boog. De thermometer krijgt ook min/max (naast buis en bol); klim/daling
   toont "+max / 0 / min" in plaats van "+ / 0 / −"; de horizon draagt geen
   tekst meer op de grond.
2. **Getal en eenheid krijgen een uitleesvenster in de flank** — authentiek een
   plaat in face-kleur met hairline, zoals het kompasvenster van #1110, nu voor
   elk instrument; klassiek dezelfde kolom zonder plaat. Eén getalmaat per
   dia, bepaald door het langste getal (min, max of waarde, met teken): alles
   staat op één lijn en de rollende uitlezing springt nooit van maat.
3. **Het label krijgt de volle celbreedte** in een strook onder de groep.
4. **Elke passingsbeslissing volgt uit tekenaantal en celmaat** (0,55 em per
   teken tekst, 0,62 em per cijfer, regelhoogte 1,15 em), niet uit gemeten
   pixels: painter en SVG-export kiezen dezelfde regelval. Flutter meet alleen
   als vangnet (ellipsis op een enkele regel).
5. Bestandsformaat onaangeroerd; geen nieuwe vaste tekst; thema en palet
   ongewijzigd.

Het verworpen alternatief — het getal in een venster in de kin van de
wijzerplaat, label en lange eenheid op een naamplaat eronder — hield "78 %" ín
de meter, maar maakte de bezel 16–27 % kleiner, hield het getal op ~36 px en
dwong de altimeter van 300° naar 270°.

## 3. Raster

- Kolommen: 1→1×1, 2→2×1, 3→3×1 (was 2×2 met een leeg vak), 4→2×2, 5→3+2 met
  de onvolledige rij gecentreerd, 6→3×2. Cellen even groot, gap 0,018 ×
  rasterbreedte. Paneel, titel en logo-vrije zone ongewijzigd.
- Per dia kiest de celvorm a = w/h de indeling: a ≥ 1,35 → **breed** (venster
  naast de wijzerplaat), anders **gestapeld** (venster onder de wijzerplaat).
  Op 16:9: 1, 3, 4, 5, 6 meters breed; 2 meters gestapeld — 3 meters op één rij
  is ook gestapeld (a ≈ 0,7).

## 4. Cel, breed (a ≥ 1,35)

- Labelstrook Lh = 0,15·h onderaan; instrumentband ih = 0,85·h.
- Wijzerplaatvierkant d = ih, links op x0 = 0,02·w; middelpunt (x0 + d/2,
  ih/2); bezel 0,465·d, face 0,88·bezel, boog 0,335·d, bandbreedte 0,035·d (de
  bestaande factoren, nu op d in plaats van op de kortste zijde van de cel).
- Venster: van xL = cx + bezel + 0,03·w tot xR = 0,97·w, breedte
  cw = min(xR − xL, 1,4·d); plaat y 0,19·ih … 0,81·ih. De groep (plaat +
  spleet + venster) wordt in de cel gecentreerd.
- Getal: N = min(0,34·ih, 0,92·cw / (0,62 · n_dia)), w800, tabellaire cijfers.
  Een korte eenheid (≤ 3 tekens, geen spatie) staat inline erachter op 0,36·N
  met een spatie van 0,1·N. Een tussenstand tijdens de animatie houdt de
  decimalen van de eindwaarde ("1450", niet "1450.3"), en n_dia telt min en max
  in diezelfde notatie. Anders een eenheidregel eronder:
  U = clamp(0,32·N, 0,055·h, 0,085·h), w600, gedempt, max 2 regels.
- Label: L = 0,095·h, w700, breedte 0,90·w, max 2 regels; vloer 0,055·h.
- Schaalcijfers: 0,065·d, gedempte inkt op volle dekking (5,2:1 op de crème
  plaat); speedometer/altimeter op (±0,62r, +0,40r), voltmeter op (±0,78r,
  +0,54r), thermometer rechts uitgelijnd op cx − 0,10·d bij kanaaltop (max) en
  bol (min) — de buis begint op −0,25·s, onder de lampjes, en de bol staat op
  +0,14·s — klim/daling "+max", "0" en "min" in de vrije linkerhelft op
  (−0,50r, −0,52r), (−0,62r, 0) en (−0,50r, +0,52r): de naald bestrijkt de
  rechterhelft en liep op de 0°-lijn dwars door de "0".
- Horizon: het vliegtuigsymbool is wit met een donkere rand, zoals de
  horizonlijn; in accentkleur was het op de lucht (EU-blauw op #2563EB, 2,5:1)
  onzichtbaar.
- Horizon: "P {pitch}" / "B {bank}" als twee regels in het venster op N —
  de vertaalde regel "P {pitch}  B {bank}" wordt op de run van twee spaties
  gesplitst, dus zonder nieuwe vertaalstring. Kompas: ACT op
  min(N, cw/(0,62·tekens)), TGT op U, markerlabel op U in max 2 regels; het
  venster op de roos (#1110) vervalt en de roos wordt weer heel.
- Schroeven op de hoeken van de instrumentband, zodat de labelstrook vrij is.

## 5. Cel, gestapeld (a < 1,35)

Wijzerplaat d = 0,56·h, middelpunt (0,5·w, 0,29·h); instrumentband 0 … 0,86·h
met de schroeven op inzet 0,065 van haar kortste zijde; venster y 0,58·h …
0,84·h, in de breedte tussen de onderste schroeven (van 0,05·w + 2,2·inzet tot
het spiegelbeeld); getal 0,14·h, eenheid 0,06·h; labelstrook 0,86·h … h met
L = 0,08·h.

**Hoogtevangnet.** Past een regelstapel niet in 0,92× de vensterhoogte (twee
horizonregels op getalmaat; een gestapelde cel met een lange eenheid), dan
krimpen álle vensters van de dia met dezelfde factor (`cockpitReadoutScale`):
de verhouding getal/eenheid blijft, niets steekt over de plaat, en de belofte
"één getalmaat per dia" blijft staan. Een negatief getal draagt een echt
minteken (U+2212) naast de plus.

## 6. Cascade (identiek in painter en export)

Past op de grootte → klaar. Anders, voor een label: krimp tot de vloer; past
het dan niet op één regel: wikkel op spaties naar 2 regels; pas daarna een
ellipsis. Voor een eenheid en een markerlabel (`wrapFirst`): eerst de grootste
maat tussen vol en vloer waarop de tekst schoon wikkelt (geen gebroken woord,
geen ellipsis), in acht vaste stappen; dan pas krimpen. Getallen krijgen nooit
een ellipsis (hun maat volgt uit het langste getal); schaalcijfers krimpen,
verplaatsen nooit. Onder 7 px wordt tekst niet getekend (de miniatuur in de
slidestrook).

## 7. Doorrekening (zes meters, 1920×1080)

Zonder logostrook is de cel 561×379 (raster 1746×789); met het LibreKAT-logo
is hij 560×322, en dan zijn alle maten 0,85× (getal 76 → 93 px omdat het
venster relatief breder is; label 36 → 31 px; bezel Ø 300 → 254).

| zone | maat (cel 561×379) | tekst | breedte | budget |
|---|---|---|---|---|
| bezel | Ø 300 (was 328) | | | |
| getal | 76 px (was 35) | "1500" | 188 px | 189 px |
| eenheid | 24 px | "% van maximale" / "hartslag" | 185 / 106 px | 189 px |
| eenheid | 24 px | "ml per uur" | 132 px | 189 px |
| label | 36 → 34 px (was 18) | "Tempo ten opzichte van plan" | 505 px | 505 px |
| schaalcijfers | 21 px (was 16) | "1000" | 46 px | vrij binnen de boog |
| horizon | 2 × 63 px | "P 4" / "B 0" | 117 px | venster 200 px hoog |

Eén meter: getal tot 0,34× de instrumenthoogte, label 58 px, eenheid op één
regel. Vier meters (de gedocumenteerde look met "%", "/10"): eenheid inline,
wijzerplaat even groot als voorheen, kolom 451 px. Deze getallen zijn
vastgepind in `test/cockpit_layout_test.dart`.

## 8. Klassiek

Zelfde skelet en dezelfde formules; kaart met accentrand om de instrumentband,
wijzerplaat in accentkleur, getal in textColor, eenheid en schaalcijfers
gedempt, label onder de kaart. Klassiek krijgt er schaalcijfers bij; de
afkapping aan de kaartrand verdwijnt.

## 9. HTML-export

Dezelfde rekenkern in `_cockpitSvg`. Het paneel van de export heeft de
verhouding van het paneel in de app op een 16:9-dia met titel en logostrook
(viewBox 1600×640, ≈ 2,5 : 1), zodat beide werelden dezelfde breed/gestapeld-
keuze maken. Regels als `<text>` met een `<tspan>` voor de inline eenheid,
tabellaire lijncijfers via `font-variant-numeric`, elke tekstzone in een
`clipPath` van haar eigen rechthoek als laatste vangnet. Alle ids dragen een
FNV-1a-suffix van de cockpit-JSON: meerdere cockpit-dia's delen één document,
en met `#cockpit-horizon-0` in twee SVG's won de eerste en verloor de tweede
zijn geclipte tekst. Bijvangst: de export tekent nu dezelfde thermometer en
horizon als de app.

## 10. Animatie

Ongewijzigd in structuur (lampentest, naald min→max→waarde, kompaszwaai,
stagger). De rollende uitlezing staat in het venster op een vaste maat; de
inline-beslissing voor de eenheid wordt op de eindwaarde genomen, niet per
frame.

## 11. Besluiten (2 september 2026)

1. Getal en eenheid in het flankvenster; het kin-alternatief is verworpen.
2. Drie meters worden één rij en vijf meters krijgen een gecentreerde tweede
   rij, ook in bestaande decks.
3. De export kiest dezelfde indeling als de app (paneelverhouding, §9).

## 12. Wat het opgeeft

- Het getal staat niet meer ín de meter zoals "78 %" in de oude
  documentatie-screenshot.
- Eén getalmaat per dia: "70" wordt niet groter dan "1500" toestaat.
- De naald in de uiterste stand loopt over het schaalcijfer (bij een echte
  meter ook).
