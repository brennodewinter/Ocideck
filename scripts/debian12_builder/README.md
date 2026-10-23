# OciDeck lokaal bouwen voor Debian 12

Deze omgeving compileert OciDeck **binnen Debian 12**. Daardoor linkt de
gegenereerde applicatie tegen de glibc en libstdc++ van Debian 12, in plaats van
tegen de nieuwere bibliotheken uit de officiële OciDeck-release.

Het script leest OciDecks Flutter-pin uit `.tool-versions`. Een pin zoals
`3.47.7-stable` wordt voor het officiële archief genormaliseerd naar
`flutter_linux_3.47.7-stable.tar.xz`.

## Benodigd

- Docker
- circa 15–25 GB vrije schijfruimte tijdens de eerste build
- internettoegang voor de broncode, Flutter en Dart-pakketten

## Bouwen

Vanuit de root van een OciDeck-checkout bouw je de **huidige commit** met:

```bash
make build-linux-debian12
```

Dit werkt ook vanuit een Git-worktree (waar `.git` een bestand is). De uitvoer
komt in `outputs/ocideck-local-builds/` en wordt niet automatisch gepubliceerd.

Het losse script hieronder gebruikt standaard een eigen broncheckout in
`work/ocideck-src`; bij herhaald bouwen blijft die bewust op dezelfde commit
tot je `UPDATE_SOURCE=1` zet.

Open een terminal in deze map en voer uit:

```bash
chmod +x build.sh
./build.sh
```

Als Docker alleen via sudo toegankelijk is:

```bash
CONTAINER_ENGINE="sudo docker" ./build.sh
```

De eerste build duurt relatief lang doordat Flutter, systeempakketten en de
native OpenCV-laag worden opgebouwd. Latere builds hergebruiken de Docker-cache
en de lokale Dart/Flutter-packagecache in `work/ocideck-pub-cache`.

De broncode komt standaard in `work/ocideck-src`. De gebouwde bundle en een
`tar.gz` komen in `outputs/ocideck-local-builds`.

## Nieuwste broncode ophalen

Een bestaande checkout wordt bewust niet automatisch gewijzigd. Werk hem
expliciet bij met:

```bash
UPDATE_SOURCE=1 ./build.sh
```

## Starten

Pak zo nodig het archief uit en start het uitvoerbare bestand uit de bundle:

```bash
./ocideck
```

In `BUILD-COMPATIBILITY.txt` staat welke GLIBC- en GLIBCXX-versies in de lokale
build zijn aangetroffen.

## Waarom geen Python-venv?

Een Python-venv isoleert alleen Python-pakketten. OciDeck gebruikt Flutter,
CMake, GTK en native C/C++-plugins. Een Debian 12-container is daarvoor de
passende reproduceerbare buildomgeving.
