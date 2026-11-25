# EN 301 549 V3.2.1 — bekende afwijkingen

> **Herzien:** 2026-11-25 · Stichting LibreKAT · intern werkdocument

Dit dossier hoort bij de [scopebepaling](EN-301-549-scope.md). Hieronder staan
geïdentificeerde afwijkingen met hun reden en gevolgen. De open toetsen staan
bij het bijbehorende oppervlak in de scopebepaling.

## Beeldexport verliest documentstructuur

**Clausules 5.4, 10.1.3.1, 10.1.3.2 en 11.8.3.** PDF, PPTX en ODP exporteren
dia’s als afbeeldingen. Dezelfde rasterweergave bewaart de visuele opmaak van
het diacanvas over exportformaten heen. `ExportService` levert bij die route
geen leesbare diatekst, kopstructuur, tabelrelaties of semantische leesvolgorde.
In de PDF-beeldroute gaat ook bestaande alternatieve tekst verloren (§10.1.1.1).
PPTX en ODP bewaren de alternatieve tekst en calloutbeschrijvingen van
afbeeldingendia’s gedeeltelijk in één beschrijving per vorm. De
`callout_accessibility_test.dart` controleert de beschrijving in beide formaten.

**Gevolg.** Een schermlezer kan de diatekst en betekenisvolle structuur van de
beeldexport niet doorlopen. De oorspronkelijke Markdown bewaart de tekst,
koppen en ingevoerde alt-tekst. De HTML-export bewaart onder meer tekst,
landmarks en calloutrelaties. Gebruik of controleer die versies wanneer de
ontvanger navigeerbare diatekst nodig heeft.

## Vigilis-linkkleur onder de contrastdrempel

**Clausule 9.1.4.3 voor HTML en 11.1.4.3 voor de weergegeven dia.**
De Vigilis-accentkleur `#FFB800` haalt als linktekst op wit volgens
`theme_profile_contrast_test.dart` ongeveer 1,7:1. De drempel voor gewone
tekst is 4,5:1. De uitzondering is bewust aan dit merkprofiel gekoppeld
omdat hetzelfde accent in meerdere elementen de merkweergave bepaalt
([#1819](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/1819)).

**Gevolg.** Links met deze kleur blijven voor een deel van het publiek moeilijk
leesbaar. Het diakwaliteitspaneel meet de gekozen kleuren en geeft een melding.
Een auteur kan een ander profiel of een contrastrijkere kleur kiezen. De test
bewaakt dat de geregistreerde uitzondering bij het specifieke paar blijft en
dat een overbodige uitzondering wordt verwijderd.
