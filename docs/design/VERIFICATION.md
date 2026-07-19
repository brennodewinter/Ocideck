# OciDeck — Wat nog tegen de werkelijkheid moet

> **Status: een werklijst, geen ontwerp.** Dit document verzamelt wat er is
> gebouwd en zijn eigen tests haalt, maar nog nooit een echte server, een tweede
> besturingssysteem of een echt rapport heeft gezien.
>
> Het bestaat omdat die schuld verspreid raakte over fasenotities en PR-teksten.
> Een schuld die niemand opschrijft, betaalt niemand. Bijgewerkt 18-07-2026.

## Hoe je dit leest

Elk punt noemt **wat je draait** en **wat als bewijs telt**. Dat tweede is het
belangrijkste: "het leek te werken" is geen bewijs, en een groene testsuite op
je eigen machine bewijst niets over een platform waar hij nooit heeft gedraaid.

De volgorde is op wat er op het spel staat, niet op moeite. Punt 1 en 2 zijn de
enige waar een fout *stil* blijft — de rest merk je meteen.

Afvinken doe je hier: zet een punt om naar "bewezen op «datum», «platform»", of
schrap het. Laat geen half afgevinkte punten staan; dan wordt dit document
precies zo onbetrouwbaar als de fasenotities die het vervangt.

---

## 1. GitHub en GitLab tegen de echte dienst

**Waarom bovenaan.** Beide adapters zijn uit documentatie gebouwd. Alleen
Forgejo heeft ooit echt geantwoord. De nepimplementaties modelleren per forge
zijn eigen conflict-guard, dus het *contract* is echt uitgeoefend — maar een
verkeerde veldnaam, een gewijzigde statuscode of een auth-eigenaardigheid haalt
elke test hier en breekt bij het eerste echte contact.

**Wat je draait.** De hele lus, per forge: openen → opslaan → conceptbranch →
uitbrengen ter review → mergen → versie vastleggen → versies openen en
vergelijken.

**Wat als bewijs telt.** Dat de lus op github.com én op gitlab.com (of een
zelfgehoste GitLab) volledig doorloopt, mét een gelijktijdige bewerking die de
conflict-guard raakt. Slaagt de guard niet, dan is de "laatste schrijver wint"-
bescherming er niet, en dat merk je pas als iemand werk kwijt is.

## 2. OQ-10 op Windows en Linux

**Waarom hier.** De token-levering aan het `git`-subproces is bewezen op macOS
en zit in de suite. De Windows-entries van de omgevings-toelatingslijst zijn
*beredeneerd*, niet waargenomen. Mist er een, dan faalt `probe()` en valt de app
terug op REST — netjes, maar **stil**. Niemand meldt een feature die er gewoon
niet blijkt te zijn.

**Wat je draait.**

```
flutter test test/git_cli_test.dart test/native_git_mirror_test.dart
```

**Wat als bewijs telt.** Groen op Windows en groen op Linux. Plus, apart: dat
`probe()` op beide platforms daadwerkelijk *slaagt* — een groene suite met een
falende probe zou betekenen dat het native pad nooit wordt gebruikt.

## 3. Live Basic-auth-handshake per forge

Geen enkele offline test staat hiervoor in. Draai één authenticated call tegen
elk van de drie en kijk of het token aankomt zoals bedoeld.

**Wat als bewijs telt.** Een geslaagde geauthenticeerde lees- én schrijfactie, en
— dit hoort erbij — dat het token daarna nergens op schijf staat. Op macOS is dat
met een byte-scan van de clone bewezen; herhaal die scan op elk platform.

## 4. Het opslagpad tegen een echte Forgejo

Dit pad is sinds fase 2 **vier keer** van vorm veranderd: offline-wachtrij,
werkbranches, merge-bij-conflict, en de werkwoord-toelatingslijst in de
transportlaag. Elke stap had tests; het geheel is sindsdien niet meer end-to-end
langs een echte server geweest.

**Wat als bewijs telt.** Openen, bewerken, offline gaan, opslaan, weer online
komen, en zien dat de wachtrij zichzelf leegt op de juiste branch.

## 5. Een echte gelijktijdige bewerking

Twee mensen, één deck, overlappende opslagacties — in plaats van de
geconstrueerde base/ours/theirs van de mergetests.

**Wat als bewijs telt.** Dat de merge landt zonder dat iemand werk kwijtraakt,
dat een echt conflict per slide te kiezen valt, en dat het deck daarna nog
parseert. Dat laatste is hét argument voor merge-per-slide; valt dat om, dan is
de hele redenering weg.

## 6. Het MIAUW-werk tegen een echt rapport

Nieuw sinds 18-07-2026 en nog door niemand in de praktijk gebruikt:

- **Gebruikte standaarden** vastleggen, en de verouderingsmelding bij
  *Afronden & verzegelen*.
- **Hulpmiddelenbijlage**: vastleggen en als tabel-slide invoegen.
- **MASTG-checklists** (186 tests, per platform) op een mobiel scope-object.
- **MASWE in een bevinding**, inclusief de link naar de OWASP-pagina.

**Wat als bewijs telt.** Eén volledig MIAUW-rapport doorlopen tot en met export
naar PDF én PPTX, met minstens één mobiele bevinding erin. Specifiek kijken naar:
staan de bijlage en de zwakheid ook echt in de **geëxporteerde** stukken (niet
alleen op het scherm), en klopt de MASWE-link.

Dit punt bestaat omdat er deze week twee keer een compliance-claim is
teruggedraaid die niet gedekt was — beide keren omdat iets wél werd vastgelegd
maar niet in de levering terechtkwam. Een echte export is de enige controle die
dat vangt.

## 7. De verouderingspoort over de tijd

`make deps-check` bevraagt zes bronnen. Vandaag melden ze allemaal "actueel",
wat betekent dat de *afwijkende* tak nooit tegen een echte upstream-wijziging is
gedraaid.

**Wat als bewijs telt.** Een keer een versie in
`lib/services/reference_standards.dart` kunstmatig terugzetten en zien dat de
poort rood wordt met de juiste melding — en daarna terugdraaien.

## 8. PDF/A-conformiteit (open vraag, geen taak)

De huidige PDF-export versus echte PDF/A (ingesloten lettertypen + metadata).
MIAUW EIS 1.1 raakt hieraan. Dit is nog geen werk maar een **beslissing**: hoe
streng wil je zijn? Beantwoord dat voordat er iets aan gebouwd wordt.

---

## Wat hier bewust *niet* op staat

Zodat deze lijst niet als een lijst met gaten leest:

- **Assetverwijdering** (§6.2 GIT_STORAGE) — niet gebouwd bij besluit. De
  index noemt kandidaten; weggooien blijft handwerk.
- **Server-side zoeken** (§9.3 GIT_STORAGE) — uitgesteld tot deze omgeving
  draait, juist omdat het per forge verschilt en blind bouwen hetzelfde
  restrisico zou opstapelen als bij de adapters.
- **MIAUW 4.3.2 en 4.8.2.x automatisch afvinken** — bewust handmatig gelaten.
  OciDeck kan niet vaststellen dat de bijlage na het invoegen nog klopt, dus
  bevestigt de tester dat zelf.
- **Sidecar-inkt-merge** (§9.7) — vergt stroke-identiteit die er niet is.
- **CWE via `make refresh-catalogs`** — die bron is een zip van tientallen MB
  achter een gedateerde URL; met de hand is eerlijker dan een make-doel dat meer
  belooft dan het waarmaakt.

## Verwante documenten

- [`GIT_STORAGE.md`](GIT_STORAGE.md) — het ontwerp achter punten 1 tot en met 5.
- [`PENTEST_MIAUW.md`](PENTEST_MIAUW.md) — het ontwerp achter punt 6 en 8.
- [`CHECKS.md`](../CHECKS.md) — wat `make check` wél al bewijst, en waarom er
  geen CI-runner is (lokaal draaien ís hier de poort).
