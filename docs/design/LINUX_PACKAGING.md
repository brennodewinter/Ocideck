# Linux-packaging — plan en afweging

> **Status:** fase 1 gebouwd · opgesteld 2026-08-04 · onderdeel van #1227
>
> Dit was een ontwerp met een aanbeveling; **fase 1 (AppImage + `.deb` + `.rpm` +
> AUR) is inmiddels geïmplementeerd** — zie `scripts/package_linux.sh`,
> `packaging/`, de `linux`-job in `.forgejo/workflows/release.yml` en
> `docs/BUILD.md` § "Linux packaging". Fase 2 (eigen apt/rpm-repo) en fase 3
> (Flatpak/Snap achter de capaciteits-feature-flag) staan nog open. Het stuk
> hieronder legt de opties naast elkaar, weegt ze tegen de kernwaarden, en stelt
> de fasering voor. De waardenlijn volgt
> [`../../assurance/app-store-distributie-positie.md`](../../assurance/app-store-distributie-positie.md):
> **de directe download uit de eigen forge blijft canoniek; elk pakketformaat is
> een extra kanaal, nooit het enige.**

## De aanleiding

Homebrew Cask is macOS-only (#1227), dus Linux heeft een eigen route nodig. De
vraag is niet "welk formaat" maar "welke *combinatie* dekt zo veel mogelijk
distributies zonder een kanaal het canonieke te maken en zonder een gebruiker
vast te zetten." Er is bewust ook naar `.deb` en naar makkelijke
Flatpak-distributie (Flathub) gekeken.

## Het bouwblok

`flutter build linux` levert geen los binary maar een **bundelmap**: de
`ocideck`-ELF plus `lib/*.so` (waaronder `libflutter_linux_gtk.so`) en een
`data/`-boom. Elk formaat hieronder verpakt diezelfde bundel; ze verschillen in
hoe die bij de gebruiker landt en wat hij ervoor moet vertrouwen. De huidige
release levert de bundel al als `ocideck-linux-x64-<versie>.tar.gz` — dat blijft
de rauwe basis.

Runtime-afhankelijkheden (uit de gelinkte libs): `libgtk-3-0`, `libsecret-1-0`
(sleutelopslag via `flutter_secure_storage`) en `liblzma5`. Een native pakket
moet die als dependencies benoemen; een AppImage/Flatpak bundelt of levert ze
mee.

## De opties, naast elkaar

| Formaat | Bereik | Poortwachter | Sandbox | Zelf te hosten? | Moeite |
|---|---|---|---|---|---|
| **Tarball** (nu) | overal | geen | nee | ja (forge-release) | nihil (bestaat) |
| **AppImage** | vrijwel elke distro, één bestand | geen | nee | ja (forge-release) | laag |
| **`.deb`** | Debian/Ubuntu/Mint (grootste groep) | geen* | nee | ja (los bestand of eigen apt-repo) | laag–middel |
| **`.rpm`** | Fedora/openSUSE/RHEL | geen* | nee | ja (los bestand of eigen repo) | laag (naast `.deb`) |
| **AUR** (`ocideck-bin`) | Arch/Manjaro | geen (community) | nee | n.v.t. (PKGBUILD wijst naar onze release) | laag |
| **Flatpak** | distro-agnostisch | eigen remote: geen · **Flathub: ja** | **ja** | ja (eigen remote) | middel–hoog |
| **Snap** | Ubuntu-nadruk | **Snap Store (Canonical), gecentraliseerd** | ja | nee (praktisch één store) | middel |

\* Geen poortwachter zolang we het pakket zelf aanbieden (los bestand of eigen
repo). Een *externe* repo/store voegt er wel een toe.

## De waardentoets per optie

**AppImage — de draagbare basis. Aanbevolen als eerste.** Eén bestand dat je van
onze eigen release downloadt en uitvoert; geen store, geen poortwachter, geen
sandbox. Dit staat het dichtst bij de canonieke directe download — de Linux-
tegenhanger van "de zip die je zelf opent." Bouwbaar met `appimage-builder` of
via `fastforge`. Voorbehoud: oudere distro's willen FUSE (te omzeilen met
`--appimage-extract-and-run`), en desktopintegratie (menu-item) vergt `appimaged`
of een handmatige stap — voor "download en start" niet nodig.

**`.deb` — de grootste groep, waardenzuiver zelf te hosten. Aanbevolen als
tweede.** Debian/Ubuntu/Mint is het grootste Linux-segment. Twee vormen: (a) een
los `.deb` aan de release hangen — geen poortwachter, meteen te doen; (b) later
een **eigen, ondertekende apt-repo** op de forge/website, zodat `apt upgrade`
meeloopt. (b) is het meest gebruiksvriendelijk én blijft van ons; het is een
uitbreiding, geen voorwaarde. `.rpm` komt er bij `fastforge` vrijwel gratis naast
voor de Fedora/openSUSE-groep.

**AUR `ocideck-bin` — een goedkope Arch-winst.** Een PKGBUILD die onze
release-tarball ophaalt en installeert. Geen poortwachter (community-repo, door
ons onderhouden), lage moeite, en Arch-gebruikers verwachten het hier. Waarden-
neutraal zolang het naar ons eigen artefact wijst.

**Flatpak — distro-agnostisch, maar hier zit de spanning.** Flatpak draait in een
**sandbox**, en dat raakt exact het zenuwpunt uit de app-store-afweging: het
**git-subproces** en de **netwerktoegang** van de samenwerkingslaag. Anders dan
de macOS App Sandbox is dit *oplosbaar* — je bundelt `git` mee ín de flatpak
(geen host-escape nodig), zet `--share=network` en geeft toegang tot de decks via
`--filesystem=home` of portals. Maar elke van die permissies verbreedt de
sandbox, en dat heeft twee gevolgen: de beschermingswinst wordt kleiner, en
**Flathub-reviewers vragen door** op brede permissies (met name `--filesystem=home`).
Twee distributiewegen:

- **Eigen Flatpak-remote** (`flatpak remote-add librekat …` op forge/website):
  waardenzuiver, van ons, geen externe review — maar de gebruiker moet onze
  remote toevoegen (minder "makkelijk").
- **Flathub** (punt 3 uit het verzoek): dít is de makkelijke distributie —
  `flatpak install flathub <app-id>` zonder remote-gedoe, plus vindbaarheid in de
  softwarecentra van GNOME/KDE. De prijs is Flathub als **reviewpoortwachter** en
  de permissie-discussie. Technisch is de horde de **offline build**: Flathubs
  bouwsandbox heeft geen netwerk, terwijl `flutter` de Dart-SDK wil ophalen. De
  tooling `flatpak-flutter` / `flutpak` lost dat op door vooraf een
  offline-manifest met alle bronnen te genereren.

Flatpak is dus geen simpele "erbij" maar een eigen traject met een echte
waardenkeuze (eigen remote vs Flathub). Het verdient een aparte beslissing.

**Snap — laag-soeverein als kanaal, maar verdedigbaar als één van velen.** De Snap
Store is Canonical-gecentraliseerd met een propriëtaire, niet zelf te hosten
backend (de bouwtooling is wél open). Als *kanaal* scoort Snap daarmee laag op
strategische, keten- en technologische soevereiniteit. Maar dat is niet het einde
van de afweging — zie [`../../assurance/soevereiniteit-ecsf.md`](../../assurance/soevereiniteit-ecsf.md):
soevereiniteit is meerdimensionaal, en **meerdere routes verhógen de operationele
soevereiniteit (SOV-4)**. Snap als één van meerdere kanalen dwingt de
Ubuntu-gebruiker nergens toe (die heeft AppImage, `.deb`, Flatpak) en maakt
OciDeck er niet afhankelijk van — de release komt uit onze forge. De Ubuntu-markt
deels missen is een reëel nadeel; hem via een laag-soeverein kanaal alsnog
bedienen, zónder het canonieke pad te verlaten, is een nettowinst. Snap wordt dus
**niet op voorhand afgewezen**, maar als extra route gewogen met open ogen over
waar het laag scoort. Bouwen kan met de snapcraft flutter-extensie; publiceren
loopt via Canonicals store (en `classic`-confinement vergt hun per-app-goedkeuring).

## Beperkte builds: de capaciteits-feature-flag

Flatpak (strict) en Snap draaien in een **sandbox**, en die raakt functionaliteit
die op een **git-subproces** leunt (de git-opslag met de NetGuard-oplegging). Bij
Flatpak is dat oplosbaar door `git` mee te bundelen; waar dat niet kan of niet
gewenst is, mag de app **niet breken of stil verkeerd gedrag vertonen**. In plaats
daarvan hoort er een **capaciteits-feature-flag** te zijn — gezet bij de build of
gedetecteerd bij runtime — die de subproces-afhankelijke functies uitschakelt en
de gebruiker **zegt** wat deze verpakking wel en niet kan. Zo is een beperkte
verpakking een *bewuste, benoemde* beperking in plaats van een bug, en blijft de
technologische soevereiniteit overeind: de gebruiker weet wat elke build kan. Dit
is een harde bouwvoorwaarde voor elke confined verpakking (Flatpak/Snap), niet een
bijzaak. De redenering staat in
[`../../assurance/soevereiniteit-ecsf.md`](../../assurance/soevereiniteit-ecsf.md).

## Aanbevolen fasering

1. **Nu, waardenzuiver en goedkoop — GEBOUWD.** AppImage + `.deb` (+ `.rpm`
   ernaast) als losse assets aan elke release, naast de bestaande tarball,
   gedraaid in de bestaande Linux-release-job op het voorgebakken CI-image. Plus
   een AUR-`ocideck-bin`. Uitgevoerd met een eigen, transparant pakketscript
   (`scripts/package_linux.sh`: `dpkg-deb`/`rpmbuild` + een sha256-gepinde
   `appimagetool`) in plaats van `fastforge` — dat past bij de pin- en
   herkomstlijn van deze repo (alles gepind en controleerbaar) en voegt geen
   Dart-toolketen toe.
2. **Daarna, gebruiksgemak zonder de forge te verlaten:** een eigen,
   ondertekende apt-repo (en desgewenst een dnf/rpm-repo) op de forge/website,
   zodat updates meelopen.
3. **De confined kanalen — Flatpak en Snap, elk mét de capaciteits-feature-flag
   als bouwvoorwaarde.** Flatpak langs een eigen remote of een `.flatpak`-bundel
   (waardenzuiver) én Flathub (bereik + vindbaarheid); Snap voor de Ubuntu-markt.
   Elk van deze draait in een sandbox, dus geen van drieën gaat live zonder dat
   de feature-flag de subproces-afhankelijke functies netjes uitschakelt en
   benoemt. De offline-buildhorde van Flathub is met `flatpak-flutter`/`flutpak`
   te nemen.

Elke fase is op zichzelf compleet; niets hiervan maakt een kanaal canoniek. De
onderbouwing waarom óók de laag-soevereine kanalen (Snap, Flathub) hier als
nettowinst gelden, staat in
[`../../assurance/soevereiniteit-ecsf.md`](../../assurance/soevereiniteit-ecsf.md).

## De website (aparte repo — werkitems, niet in deze PR)

De installatie-uitleg op de site (librekat.nl, `nl` als brontaal, vertaald via
`vertaal.py`) moet mee:

1. **Linux volwaardig opnemen.** Nu leunt de uitleg op de tarball; er komen
   AppImage/`.deb`(/`.rpm`) bij, elk met "download en start/installeer"-tekst per
   distributiegroep. Nieuwe of gewijzigde tekst → opnieuw vertalen.
2. **macOS-tekst bijwerken.** Naast de directe download komt de Homebrew-route:
   eerst `brew tap librekat/ocideck <forge-URL>`, dan
   `brew install --cask librekat/ocideck/ocideck` (de GitHub-shorthand
   `brew install --cask brennodewinter/ocideck/ocideck` als terugvaloptie);
   de "ongetekend, zo open je hem"-tekst blijft gelden zolang releases niet
   genotariseerd zijn. Ook deze wijziging → opnieuw vertalen.
3. **Flatpak makkelijk maken** hangt aan de Flatpak-beslissing hierboven: bij
   Flathub is de site-tekst één `flatpak install`-regel; bij een eigen remote
   staat er eerst een `remote-add`.

Deze drie leven in de website-repo, niet hier; ze staan genoteerd zodat ze niet
zoekraken.

## Open beslissingen (voor de bouwfase)

- **Flatpak: eigen remote/`.flatpak`-bundel én Flathub?** De soevereiniteitstoets
  wijst richting "allebei": de eigen route voor de waarde, Flathub voor het
  bereik. Bevestiging gevraagd.
- **Snap: als extra route erbij (aanbevolen na de ECSF-weging), en zo ja strict-
  of classic-confinement?** Strict houdt de sandbox intact (feature-flag doet het
  werk); classic vergt Canonicals per-app-goedkeuring.
- **Eigen apt/rpm-repo** — bevestigd als kern van fase 1 (updates lopen mee).
- **Feature-flag** — geen open vraag maar een **bouwvoorwaarde** voor elke
  confined verpakking; hoort ontworpen te zijn vóór de eerste Flatpak/Snap.
