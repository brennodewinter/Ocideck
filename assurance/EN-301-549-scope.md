# EN 301 549 V3.2.1 — scopebepaling

> **Herzien:** 2026-11-25 · Stichting LibreKAT · intern werkdocument

De toetssteen is **EN 301 549 V3.2.1 (2021-03)**. De norm neemt WCAG 2.1
niveau A en AA als basis voor webinhoud, niet-webdocumenten en software
(hoofdstukken 9, 10 en 11), met eigen toepassingsvoorwaarden en aanvullende
eisen. Het dossier legt per oppervlak vast waar bewijs voor is. De dekking is
gedeeltelijk. OciDeck claimt geen conformiteit en beschikt niet over een
toegankelijkheidsconformiteitsrapport of gebruikersonderzoek met hulptechnologie.

De afbakening is technisch. Of Richtlijn (EU) 2019/882 op LibreKAT van toepassing
is, blijft een juridische vraag. De Europese Commissie noemt V3.2.1 als
geharmoniseerde norm voor de richtlijn over overheidswebsites en -apps
(2016/2102). Zie de [ETSI-uitgave](https://www.etsi.org/deliver/etsi_en/301500_301599/301549/03.02.01_60/en_301549v030201p.pdf),
[WCAG 2.1](https://www.w3.org/TR/WCAG21/) en het [overzicht van de Europese Commissie](https://digital-strategy.ec.europa.eu/en/policies/web-accessibility-directive-standards-and-harmonisation).

## Toepasselijke oppervlakken

| Clausules | Oppervlak | Afbakening |
| --- | --- | --- |
| §5.4 | Omzetting van documenten | Deck- en documentexport zetten inhoud om naar andere formaten. Behoud van toegankelijkheidsinformatie geldt waar het doelformaat die kan dragen. |
| §7.1, §9.1.2, §10.1.2 en §11.1.2 | Tijdgebonden media | De app kan media afspelen en presentaties kunnen media bevatten. De inventaris hieronder toetst de verschillende ondertitel-, audio- en videoroutes nog niet. |
| §9 | Webapp en HTML-export | De browserinterface en de gegenereerde HTML hebben elk hun eigen toetsen nodig. |
| §10 | PDF-, PPTX- en ODP-uitvoer | De vaste dia-uitvoer valt onder niet-webdocumenten. Zie de [afwijkingen](EN-301-549-afwijkingen.md) voor informatieverlies in de beeldexport. |
| §11 | Native editor, lezer en presentatiebediening | Naast de softwarecriteria zijn de platformkoppeling met hulptechnologie (§11.5.2) en gebruikersvoorkeuren (§11.7) relevant. De eisen voor auteursgereedschap (§11.8) raken ook de webapp. |
| §12.1 | Meegeleverde productdocumentatie | De toegankelijkheidsgids beschrijft functies en beperkingen. De leesbaarheid van de documentatie in de app en met hulptechnologie vereist een eigen toets. |

De eisen voor hardware (§8) hebben geen onderwerp in de gedistribueerde
software. Voor aanvullende eisen, waaronder communicatie en video (§6–7) bij
de optionele vergaderkoppeling, is de toepasselijkheid per route nog te bepalen.
De tabel legt alleen de getoetste of geïdentificeerde onderwerpen vast.

## Bewijs en open toetsen

| Onderwerp | Clausules | Bestaand bewijs | Open toets of afwijking |
| --- | --- | --- | --- |
| Tekstschaling en reflow | §9.1.4.4 en §11.1.4.4.1, §9.1.4.10 en §11.1.4.10, §11.7 | `uiTextScale` in `AppSettings` maakt 100–200% mogelijk voor interfacetekst. Tests bestrijken onder meer de dialoogschil op 200%. | Volledige reflow, instellingen van het platform en behoud van bediening op alle schermen zijn niet gemeten. Het 16:9-diacanvas houdt zijn vaste afmetingen. |
| Contrast, kleur en herstelhulp | §9.1.4.1/3/11 en §11.1.4.1/3/11, §11.8.4 | `app_theme_contrast_test.dart` meet geselecteerde voor- en achtergrondparen. `theme_profile_contrast_test.dart` gebruikt dezelfde analyse als het diakwaliteitspaneel. Tekstlabels, vormen en symbolen bieden bij meerdere functies een tweede aanwijzing naast kleur. | Het HTML-exportcontrast is niet integraal gemeten. De bekende uitzondering voor Vigilis-geel staat in het afwijkingendossier. |
| Bediening en focus | §11.2.1.1.1, §11.2.4.3 en §11.2.4.7, §9.2.4.3 | De editor heeft toetsen voor een deel van de bediening. De presenter heeft focusbare keuzemenu’s en een focusring. | Volledige toetsenborddekking, focusvolgorde en zichtbaar focusgedrag zijn niet gemeten. Dat geldt ook voor de focusvolgorde van de HTML-export. |
| Alternatieve tekst, namen en status | §9.1.1.1, §11.1.1.1.1, §11.4.1.2/.3 en §11.5.2.3/.5 | Alt-tekst wordt opgeslagen in Markdown. `accessibility_labels_test.dart` controleert namen van knoppen in geselecteerde widgets en bewaakt bronpatronen. `callout_accessibility_test.dart` controleert Flutter-semantiek en HTML-beschrijvingen voor markeringen. De presenter kondigt diawissels aan. | De semantiekboom is gedeeltelijk getest. Uitvoer naar VoiceOver, NVDA, JAWS of Orca, en de leesvolgorde en statusmeldingen in volledige workflows, zijn niet end-to-end geverifieerd. |
| HTML-structuur en taal | §9.1.3.1, §9.2.4.1 en §9.3.1.1 | `MarpHtmlService` schrijft de rapporttaal op `<html>`. De export bevat een hoofdlandmark en een titelkop. Markeringen hebben tekstalternatieven en relaties. | Dit zijn afzonderlijke controles. Structuur en leesvolgorde van samengestelde exports zijn niet integraal beoordeeld. |
| Auteursgereedschap en omzetting | §5.4, §10.1.1.1, §10.1.3.1/.2, §11.8.2–.5 | Alt-tekst, contrastmeldingen en HTML met tekststructuur helpen bij het maken van toegankelijkere inhoud. PPTX en ODP bewaren bij afbeeldingendia’s gedeeltelijk beschrijvingen. | De beeldexport verliest structuur. Templates zijn niet getoetst op §11.8.5. Zie de [afwijkingen](EN-301-549-afwijkingen.md). |

De twee verwijzingen naar WCAG **2.2** in `test/accessibility_labels_test.dart`
noemen beide succescriterium **4.1.2 (naam, rol, waarde)**. Nummer en criterium
zijn gelijk in [WCAG 2.1](https://www.w3.org/TR/WCAG21/#name-role-value) en
[WCAG 2.2](https://www.w3.org/TR/WCAG22/#name-role-value). De tests leveren voor
die onderzochte knoppen bewijs bij de 2.1-toetssteen. Hun asserts beoordelen
voornamelijk de naam.

Heroverweeg dit dossier wanneer de exportstructuur, ondersteunde media,
platformsemantiek of de gekozen editie wijzigt.
