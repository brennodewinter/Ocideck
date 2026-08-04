# Linux-packaging — plan en afweging

> **Status:** plan · opgesteld 2026-08-04 · onderdeel van #1227
>
> Dit is een ontwerp met een aanbeveling, geen belofte. Het legt de opties naast
> elkaar, weegt ze tegen de kernwaarden, en stelt een fasering voor. De
> waardenlijn volgt [`../../assurance/app-store-distributie-positie.md`](../../assurance/app-store-distributie-positie.md):
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

**Snap — waarschijnlijk niet.** De Snap Store is Canonical-gecentraliseerd met een
proprietary backend; er is praktisch geen alternatieve store. Dat botst met
soevereiniteit (waarde 3) op dezelfde manier als een gesloten app-store, en zonder
de vindbaarheidswinst die Flathub biedt op méér dan één distro. Voorlopig
afgeraden; genoteerd, niet gebouwd.

## Aanbevolen fasering

1. **Nu, waardenzuiver en goedkoop:** AppImage + `.deb` (+ `.rpm` gratis ernaast)
   als losse assets aan elke release, naast de bestaande tarball. Eén
   `fastforge`-config, gedraaid in de bestaande Linux-release-job op het
   voorgebakken CI-image. Plus een AUR-`ocideck-bin`.
2. **Daarna, gebruiksgemak zonder de forge te verlaten:** een eigen,
   ondertekende apt-repo (en desgewenst een dnf/rpm-repo) op de forge/website,
   zodat updates meelopen.
3. **Aparte beslissing:** Flatpak — eerst een eigen remote (waardenzuiver), en
   pas daarna de vraag of Flathub erbij komt (bereik vs poortwachter +
   permissie-review). De offline-buildhorde is met bestaande tooling te nemen.

Elke fase is op zichzelf compleet; niets hiervan maakt een kanaal canoniek.

## De website (aparte repo — werkitems, niet in deze PR)

De installatie-uitleg op de site (librekat.nl, `nl` als brontaal, vertaald via
`vertaal.py`) moet mee:

1. **Linux volwaardig opnemen.** Nu leunt de uitleg op de tarball; er komen
   AppImage/`.deb`(/`.rpm`) bij, elk met "download en start/installeer"-tekst per
   distributiegroep. Nieuwe of gewijzigde tekst → opnieuw vertalen.
2. **macOS-tekst bijwerken.** Naast de directe download komt
   `brew install --cask librekat/ocideck/ocideck` (zodra de tap live is, #1227);
   de "ongetekend, zo open je hem"-tekst blijft gelden zolang releases niet
   genotariseerd zijn. Ook deze wijziging → opnieuw vertalen.
3. **Flatpak makkelijk maken** hangt aan de Flatpak-beslissing hierboven: bij
   Flathub is de site-tekst één `flatpak install`-regel; bij een eigen remote
   staat er eerst een `remote-add`.

Deze drie leven in de website-repo, niet hier; ze staan genoteerd zodat ze niet
zoekraken.

## Open beslissingen (voor de bouwfase)

- **Flatpak: eigen remote, Flathub, of allebei?** De enige echte waardenkeuze in
  dit plan.
- **Snap: definitief niet, of toch classic-confinement overwegen?**
- **Eigen apt/rpm-repo nu of later** — hangt aan of updates-meelopen zwaar genoeg
  weegt tegen het onderhoud van een ondertekende repo.
