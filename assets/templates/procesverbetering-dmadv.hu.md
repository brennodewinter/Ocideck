---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: "Folyamatjavítás: DMADV projekt"
language: hu
ocideck_improvement_framework: dmadv
---

<!-- _class: title -->

# Folyamatfejlesztés: DMADV projekt

---

<!-- skip -->

# Így dolgozhat ezzel a sablonnal

- Használja a DMADV-t egy új vagy alapvetően újratervezett folyamathoz, és válasszon egy mérhető ügyféleredményt (**Y-01**).
- Használja az egyes útmutatódiák kérdéseit ellenőrzőlistaként; majd adjon hozzá rendszeres diákat a válaszokhoz.
- Cserélje ki a chartában és a CTQ fában található magyarázatot a projekt információival, töltse ki a SIPOC-t, és tegye tesztelhetővé a követelményeket a tervezés előtt.
- A súgódiák nem jelennek meg és nem exportálhatók. Ha meg szeretne mutatni egyet, kapcsolja ki a **Kihagyás** lehetőséget az adott diánál.

---

<!-- _class: section -->

# Határozza meg

---

<!-- skip -->

# Ellenőrzőlista – Mit rögzít a meghatározáskor?

- Melyik ügyfélnek vagy felhasználónak milyen kielégítetlen szükséglete van?
- Miért van szükség új tervezésre, és miért nem elég a meglévő folyamat javítása?
- Milyen eredményt kell elérnie a tervezésnek (**Y-01**), és milyen terjedelemben?
- Ki dönt a követelményekről, a tervezési lehetőségekről és a kiadásról?
- Milyen tervezési, előfeltételek és sikerkritériumok érvényesek?

---

<!-- _class: canvas -->
<!-- ocideck_template: charter -->

# Projectcharter

## Probléma vagy lehetőség

Ismertesse a kielégítetlen szükségletet, a célcsoportot és a kimutatható okot!

## Gól

Mérhető és időhöz kötött módon fogalmazza meg a kívánt eredményt.

## Hatály

Jegyezze fel a kiindulási pontot, a végpontot, az érintkezési pontokat és azt, ami kívül esik a tervezésen.

## Csapat

Nevezze meg az ügyfelet, a tervezés tulajdonosát, a felhasználókat és a szükséges szakértőket.

## Idővonal

Rögzítse a mérföldköveket, a döntési kapukat és a tervezett telepítést.

## Sikerkritériumok
Mikor felel meg kimutathatóan a tervezés a vásárlói igényeknek?

---

<!-- _class: tree -->
<!-- ocideck_template: ctq-tree -->
<!-- ocideck_layout: tree -->

# Mérhető vásárlói igények (CTQ fa)

- Milyen eredményre van szüksége az ügyfélnek? — **Y-01**
  - Fordítsa le ezt az igényt mérhető szükségletté 1
  - Fordítsa le ezt az igényt mérhető szükségletté 2

---

<!-- skip -->

# Ellenőrzőlista – Hogyan kell kitölteni a SIPOC-t?

- Kezdje az **Ügyféllel**: ki használja az új folyamateredményt?
- Ezután azonosítsa a szükséges **Kimenetet** és 4-7 tervezett **Feldolgozás** lépést.
- Vegye figyelembe a szükséges **Bemenetet** és a **Beszállítót**, amely minden bemenetet elérhetővé tesz.
- Tartson általános áttekintést; a tervezés részleteit később követjük.
- Ellenőrizze, hogy a kiválasztott határvonalak megfelelnek-e a charternek és az Y-01-nak.

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

# Mérje meg

---

<!-- skip -->

# Ellenőrzőlista – Mit rögzít a mérés során?

- Mely ügyféligények váltak mérhető követelményekké és prioritásokká?
- Mi az Y-01 célértéke, alsó vagy felső határa, mértékegysége és mérési módszere?
- Milyen felhasználási eseteket, mennyiségeket és kivételeket kell kezelnie a tervezésnek?
- Milyen meglévő eredményeket vagy alternatívákat használ referenciaként?
- Hogyan fogja objektíven tesztelni, hogy az egyes követelmények teljesültek-e?

---

<!-- _class: section -->

# Elemezze

---

<!-- skip -->

# Ellenőrzőlista – Mit rögzít az elemzés során?

- Milyen funkciókat kell teljesítenie a folyamatnak, hogy megfeleljen a követelményeknek?
- Milyen összefüggések és kompromisszumok léteznek az ügyfelek kívánságai, kockázatai és tervezési jellemzői között?
- Milyen feltevéseket kell még feltárni vagy tesztelni?
- Mely hibamódok és függőségek a legfontosabbak?
- Milyen minimális tervezési kritériumoknak kell megfelelnie minden megoldásnak?

---

<!-- _class: section -->

# Tervezés

---

<!-- skip -->

# Ellenőrzőlista – Mit rögzít a Designban?

- Mely tervezési változatokat vették figyelembe és milyen szempontok alapján hasonlították össze?
- Hogyan néz ki a kiválasztott folyamatfolyamat, beleértve a szerepeket, rendszereket és átviteleket?
- Hogyan akadályozza meg vagy szabályozza a tervezés a nagyobb meghibásodási módokat?
- Mit tanít a prototípus vagy teszt a működésről és a könnyű használatról?
- Melyik változat megy ellenőrzésre, mely nyitott pontokkal?

---

<!-- _class: section -->

# Ellenőrizze

---

<!-- skip -->

# Ellenőrzőlista – Mit rögzít az ellenőrzés során?

- Melyik teszt bizonyítja az egyes követelményekre, hogy a tervezés reális körülmények között működik?
- Milyen eredményeket értek el, és milyen eltérések maradtak?
- Mit gondolnak a felhasználók és a folyamattulajdonosok a működésről és a megvalósíthatóságról?
- Milyen ellenőrzés, utasítás és mérés szükséges az üzembe helyezés után?
- Ki adja ki a tervet és milyen bizonyítékok alapján?
