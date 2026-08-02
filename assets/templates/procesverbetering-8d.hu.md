---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: "Folyamatjavítás: 8D projekt"
language: hu
ocideck_improvement_framework: 8d
---

<!-- _class: title -->

# Folyamatfejlesztés: 8D projekt

---

<!-- skip -->

# Így dolgozhat ezzel a sablonnal

- Használja a 8D-t egy súlyos vagy visszatérő probléma esetén, és válasszon egy mérhető kulcseredményt (**Y-01**).
- Használja az egyes útmutatódiák kérdéseit ellenőrzőlistaként; majd adjon hozzá rendszeres diákat a válaszokhoz.
- Cserélje ki a chartában és a CTQ fában található magyarázatot a projekt információival, töltse ki a SIPOC-t, és válassza el az ideiglenes korlátozást a végleges korrekciótól.
- A súgódiák nem jelennek meg és nem exportálhatók. Ha meg szeretne mutatni egyet, kapcsolja ki a **Kihagyás** lehetőséget az adott diánál.

---

<!-- _class: section -->

# D0: Készülj fel

---

<!-- skip -->

# Ellenőrzőlista – Mit rögzít a 0. napon?

- Mi az első tényszerű jelzés, és mennyire súlyos vagy sürgős?
- Mely ügyfélre, biztonságra, szállításra vagy üzleti műveletekre lehet hatással?
- Megfelelő-e a 8D a komplexitás, az ismétlődés és a szükséges tudományágak miatt?
- Mely adatokat, mintákat és nyomokat kell azonnal védeni?
- Milyen azonnali intézkedésekre van szükség, mielőtt a csapat elkészül?

---

<!-- _class: canvas -->
<!-- ocideck_template: charter -->

# Projectcharter

## Probléma

Foglalja össze az első jelet anélkül, hogy bizonyított okot említene.

## Gól

Jegyezze fel a kívánt Y-01 eredményt és a szükséges helyreállítási dátumot.

## Hatály

Határozza meg a terméket, a folyamatot, a helyet, az időszakot és a kizárt eseteket.

## Csapat

A tulajdonos neve és a szükséges szakterületek; dolgozza ki a neveket a D1-nél.

## Idővonal

Határidők meghatározása a visszaszorításra, a kiváltó okok elemzésére, a korrekcióra és a lezárásra.

## Sikerkritériumok
Mikor védik meg az ügyfelet, szüntetik meg az okot és akadályozzák meg a kiújulást?

---

<!-- _class: tree -->
<!-- ocideck_template: ctq-tree -->
<!-- ocideck_layout: tree -->

# Mérhető vásárlói igények (CTQ fa)

- Milyen eredményt kell visszaállítani az ügyfél számára? — **Y-01**
  - Melyik követelmény vagy korlát nem teljesül?
  - Milyen további feltételt kell megtartani?

---

<!-- skip -->

# Ellenőrzőlista – Hogyan kell kitölteni a SIPOC-t?

- Határozza meg azt a folyamatot, ahol a probléma felmerül vagy kikerül.
- Kezdje az érintett ügyféllel és a rendellenes kimenettel.
- Foglalja össze a folyamatot 4-7 fő lépésben; okokat még ne adj hozzá.
- Rögzítse a bemeneteket és a szállítókat, hogy felfedje a lehetséges forrás- és átviteli pontokat.
- Később használja a D4 bizonyítékait az okok megerősítésére.

---

<!-- _class: matrix -->
<!-- ocideck_template: sipoc -->

# SIPOC

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |
|  |  |  |  |  |

---

<!-- _class: section -->

# D1: Építsd fel a csapatot

---

<!-- skip -->

# Ellenőrzőlista – Mit rögzít a D1-en?

- Ki rendelkezik folyamatismerettel, termékismerettel, adatokkal, döntési jogkörrel és ügyfélkapcsolattal?
- Kié a 8D eredmény, és ki vezeti a napi megközelítést?
- Milyen feladatai és felelősségei vannak az egyes csapattagoknak?
- Milyen kapacitásra és felhatalmazásra van szüksége a csapatnak?
- Milyen gyakran találkozik a csapat, és hol rögzítik a döntéseket?

---

<!-- _class: section -->

# D2: Ismertesse a problémát

---

<!-- skip -->

# Ellenőrzőlista – Mit rögzít a D2-n?

- Mi a baj pontosan, hol, mikor, milyen gyakran és milyen mértékben?
- Kivel vagy milyen termékekkel fordul elő – és hol nem?
- Mi a jelenlegi Y-01 érték a követelményhez vagy a normál teljesítményhez képest?
- Milyen fényképek, mérések, példák és forrásadatok támasztják alá a leírást?
- Mely ok-feltevéseket hagyja ki tudatosan a problémamondatból?

---

<!-- _class: section -->

# D3: Végezzen elzárási intézkedéseket

---

<!-- skip -->

# Ellenőrzőlista – Mit rögzít a D3-on?

- Melyik ideiglenes intézkedés védi meg azonnal az ügyfelet vagy az eljárást a hatás ellen?
- Hol érvényes az akció, mikortól és ki fogja megvalósítani?
- Hogyan ellenőrizték, hogy az elszigetelés valóban működik-e?
- Milyen kockázatokkal, költségekkel és korlátokkal jár az ideiglenes intézkedés?
- Mikor és milyen feltételekkel szűnik meg a korlátozás?

---

<!-- _class: section -->

# D4: A kiváltó okok azonosítása és ellenőrzése

---

<!-- skip -->

# Ellenőrzőlista – Mit rögzít a D4-en?

- Milyen ok magyarázza a probléma felmerülését?
- Milyen menekülési ok magyarázza, hogy miért nem fedezték fel hamarabb?
- Milyen bizonyítékok teszik reprodukálhatóvá vagy tesztelhetővé az egyes okokat?
- Milyen gyanúkat vizsgáltak és utasítottak el?
- Hogyan érintik a megerősített okok az Y-01-öt?

---

<!-- _class: section -->

# D5: Válassza ki és ellenőrizze a korrekciós intézkedéseket

---

<!-- skip -->

# Ellenőrzőlista – Mit rögzít a D5-ön?

- Melyik végső művelet szünteti meg melyik megerősített gyökér- vagy menekülési okot?
- Mely alternatívákat hasonlították össze hatás, kockázat és megvalósíthatóság szempontjából?
- Hogyan tesztelték a kiválasztott műveletet a széles körű megvalósítás előtt?
- Mi volt a mért hatás az Y-01-re, és milyen mellékhatások jelentkeztek?
- Ki hagyja jóvá a választott korrekciót?

---

<!-- _class: section -->

# D6: A korrekciós intézkedések végrehajtása és érvényesítése

---

<!-- skip -->

# Ellenőrzőlista – Mit rögzít a D6-on?

- Mely akciókat hol, mikor és ki vezette be véglegesen?
- Milyen eljárásokat, rendszereket, képzéseket és ellenőrzéseket alakítottak ki?
- Hogyan és mikor lehet biztonságosan megszüntetni az ideiglenes korlátozást?
- Mely eredmények bizonyítják, hogy az Y-01 fenntarthatóan megfelel a követelménynek?
- Milyen eltéréseket vagy nyitott kérdéseket kell még megoldani?

---

<!-- _class: section -->

# D7: Megismétlődés megelőzése

---

<!-- skip -->

# Ellenőrzőlista – Mit rögzít a D7-en?

- Hol máshol fordulhat elő ugyanaz az ok vagy menekülési útvonal?
- Milyen szabványokat, tervezési szabályokat, ellenőrzéseket vagy tanulságokat kell szélesebb körben adaptálni?
- Ki és mikor végzi el ezeket a megelőző intézkedéseket?
- Hogyan ellenőrizhető, hogy a változtatás ezen az eseten kívül is működik-e?
- Milyen tudást osztanak meg más csapatokkal vagy beszállítókkal?

---

<!-- _class: section -->

# D8: Ismerd fel a csapatot

---

<!-- skip -->

# Ellenőrzőlista – Mit rögzít a D8-on?

- Milyen bizonyítékok mutatják, hogy a probléma, az ok, a korrekció és a megelőzés befejeződött?
- Az ügyfél vagy a folyamat tulajdonosa elfogadta az eredményt?
- Melyik hozzájárulás és együttműködés érdemel kifejezetten elismerést?
- Milyen tanulságokat von le a csapat a következő problémához?
- Ki zárja le hivatalosan az aktát, és hol találhatók a bizonyítékok?
