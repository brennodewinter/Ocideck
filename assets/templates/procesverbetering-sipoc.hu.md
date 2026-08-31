---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: SIPOC folyamatáttekintés
language: hu
---

<!-- _class: title -->

# SIPOC folyamatáttekintés
## Szállító · Bemenet · Folyamat · Kimenet · Vevő

---

<!-- skip -->

# Így dolgozhat ezzel a sablonnal

- A SIPOC segítségével megértheti egy folyamat hatókörét és függőségeit, nem pedig minden művelet rögzítésére.
- Használja a súgót és a példasort ellenőrzőlistaként; írja be a válaszait a **Folyamathatárok** és az üres **SIPOC** mátrixba.
- Lehetőleg vevőtől beszállítóig dolgozzon, főnevekkel az input és output, valamint az igékkel a folyamat lépéseihez.
- Csak a **Kihagyott** címkével ellátott diák maradnak ki a prezentációból és az exportálásból. Kapcsolja be vagy ki a **Kihagyás** funkciót, ha olyan magyarázatokat szeretne kapni, amelyekre közönségének szüksége lehet, vagy nem.

---

# Mit térképez fel a SIPOC?

- **Beszállító:** biztosítja a folyamathoz szükséges információkat vagy erőforrásokat.
- **Input:** a folyamat által megkövetelt adatok, anyagok vagy egyéb feltételek.
- **Folyamat:** 4-7 magas szintű tevékenység, amelyek átalakítják a bemenetet.
- **Kimenet:** a folyamat által előállított termék, szolgáltatás vagy információ.
- **Ügyfél:** a kimenet belső vagy külső címzettje.

---

<!-- _class: table table-editable -->

# Állítsa be a folyamat határait

| Határ | Érték |
| --- | --- |
| Folyamat neve |  |
| Kezdőpont |  |
| Végpont |  |

---

<!-- skip -->

# Ellenőrzőlista – Mikor elég világosak a határok?

- **Folyamat:** adjon neki egy felismerhető nevet igével és tárggyal, például „Rendelés regisztrálása”.
- **Kiindulópont:** Nevezzen meg egy megfigyelhető eseményt, például „Kérés érkezett”.
- **Végpont:** nevezzen meg egy kimutatható eredményt, például „Rendelési visszaigazolás elküldve”.
- Válassza ki azokat a határokat, amelyek körül a csapat értelmes megállapodásokat köthet.
- A kivételek és a szomszédos folyamatok áthelyezése a mátrixon kívülre; írja le őket külön.

---

<!-- skip -->

# Ellenőrzőlista – Töltse ki jobbról balra

1. Állítson be világos kezdő- és végpontokat a folyamathoz.
2. Nevezze meg azokat az ügyfeleket, akik az eredménytől függenek.
3. Ismertesse a kapott kimeneteket.
4. Foglalja össze a folyamatot 4-7 magas szintű tevékenységben.
5. Határozza meg, hogy ezeknek a tevékenységeknek milyen inputokra van szüksége.
6. Minden bemenetet kapcsoljon a szállítóhoz, aki azt elérhetővé teszi.

---

<!-- skip -->
<!-- _class: table -->

# Ellenőrzőlista — Példa egy összekapcsolt sorra

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
| Eladás | Jóváhagyott kérés | Megrendelés ellenőrzése → regisztrálás → megerősítés | Megrendelés visszaigazolása | Pályázó |

- Olvassa el a sort egy láncként: a szállító ad inputot, a folyamat a vevő számára outputtá alakítja.
- Csak akkor adjon hozzá új sort, ha a lánc jelentősen eltér.
- Ellenőrizze az érintettekkel, hogy nem hiányzik-e egy fontos beszállító, input, output vagy ügyfél.

---

<!-- _class: matrix -->
<!-- ocideck_template: sipoc -->

# SIPOC

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |

---

<!-- _class: table table-editable -->

# SIPOC vagy részletes folyamatábra?

| Jellegzetes | SIPOC | Részletes folyamatábra |
| --- | --- | --- |
| Cél | Határozza meg a hatókört és a kapcsolatokat | Dokumentálja a munkát és a döntéseket |
| Részlet | 4-7 magas szintű tevékenység | Több tucat lépést tartalmazhat |
| Fókusz | Szállítók, inputok, outputok és vevők | Sorrend, átadások és döntési pontok |
| Használat | A fejlesztés megkezdése | Végrehajtás és hibaelemzés |
