# Assurance — intern werkdossier

> **Status:** levend werkdocument · laatst bijgewerkt 2026-07-22 · Stichting LibreKAT
>
> **Dit is geen keurmerk en geen auditrapport.** Er wordt hier tegen niets
> gecertificeerd en er wordt niets aan derden toegezegd. Wat hier staat is de
> eigen redenering: welke lat we onszelf opleggen, waarom bepaalde delen ervan
> hier niet van toepassing zijn, en wat er open staat.

## Waarom dit niet in `docs/` staat

Alles onder `docs/` wordt als asset meegeleverd en is in de app leesbaar — het
is productdocumentatie. Dit dossier is dat niet. Het bevat scopekeuzes,
afwegingen en openstaande punten: stuurinformatie voor wie eraan werkt, geen
belofte aan wie het gebruikt.

Dat sluit aan op een vaste lijn in dit project: **standaarden worden in gedrag
aangehouden, niet in opgeschreven beloftes.** Een toezegging in
productdocumentatie is een producteigenschap die onwaar kan worden. Een norm die
je meet, kun je missen en bijstellen; een norm die je publiceert, is iets waarop
je wordt afgerekend. Daarom staat er nergens in `docs/` een zin als "voldoet aan
ASVS Level 2", en daarom hoort dit dossier hier.

De repository is wel openbaar. Dit is dus niet geheim — het is alleen geen
onderdeel van wat het product over zichzelf beweert.

## Wat er in deze map staat

| Bestand | Wat het is |
|---|---|
| [`ASVS-5.0.0-scope.md`](ASVS-5.0.0-scope.md) | Welke ASVS-hoofdstukken hier een onderwerp hebben en welke niet, mét de motivering. Het waardevolle deel. |
| [`ASVS-5.0.0-afwijkingen.md`](ASVS-5.0.0-afwijkingen.md) | Eisen die bewust niet worden gehaald, en waarom dat de juiste keuze is. |

## De bronnen, en waar het weten ophoudt

**OWASP ASVS 5.0.0** (mei 2025) is vrij beschikbaar. De machineleesbare lijst
met alle 345 eisen is ingelezen uit de officiële CSV in de OWASP/ASVS-repository;
elke eis-id en -tekst waarnaar hier verwezen wordt, komt daaruit. Er is geen
eisnummer gereconstrueerd uit het geheugen. 253 eisen staan op Level 1 of 2.

**ISO/IEC/IEEE 15289:2019** (documentatie) is betaald en is *niet* in zijn
geheel ingezien. Uit het officiële gratis voorbeeld is geverifieerd: de zeven
generieke itemsoorten van clausule 7 plus Record (9.2), de lijst van 74
specifieke items in clausule 10, dat clausule 5 tailoring uitdrukkelijk toestaat
(items mogen worden samengevoegd, hertiteld of weggelaten), en de normatieve
kwaliteitskenmerken uit 3.1. De inhoudsopsommingen bínnen 7.2–7.8 en 9.2 staan
achter de betaalmuur en zijn niet gelezen — er wordt hier nergens op gesteund en
er worden geen clausulenummers verzonnen.

Waar iets niet vast te stellen was, staat dat er als "niet vastgesteld". Dat is
geen slordigheid maar het punt: een dossier dat gaten dichtpraat, is minder waard
dan een dossier dat ze aanwijst.

## Hoe dit bijgewerkt hoort te worden

- Verwijs naar **bestandsnaam plus symboolnaam**, nooit naar een regelnummer.
  Regelnummers schuiven; de acht `file:line`-verwijzingen die ooit in
  `docs/PERFORMANCE_GUIDE.md` stonden, klopten alle acht niet meer.
- Een eis geldt pas als "gehaald" wanneer er in de code is nagekeken dát hij
  gehaald wordt. Dat een ontwerpdocument het beweert, is niet genoeg.
- Verandert de scope van het product — komt er een server, een account, een
  sessie — dan is de scopebepaling het eerste wat herzien moet worden, niet het
  laatste.
