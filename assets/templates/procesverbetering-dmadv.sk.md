---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: "Zlepšenie procesov: projekt DMADV"
language: sk
ocideck_improvement_framework: dmadv
---

<!-- _class: title -->

# Zlepšenie procesov: projekt DMADV

---

<!-- skip -->

# Takto sa pracuje s touto šablónou

- Použite DMADV na nový alebo zásadne prepracovaný proces a vyberte si jeden merateľný zákaznícky výsledok (**Y-01**).
- Použite otázky na každej snímke sprievodcu ako kontrolný zoznam; potom pridajte bežné snímky pre svoje odpovede.
- Nahraďte vysvetlenie v charte a strome CTQ informáciami o svojom projekte, vyplňte SIPOC a urobte testovateľné požiadavky pred návrhom.
- Snímky pomocníka sa nezobrazujú ani neexportujú. Ak ju chcete zobraziť, vypnite pre danú snímku možnosť **Preskočiť**.

---

<!-- _class: section -->

# Definujte

---

<!-- skip -->

# Kontrolný zoznam — Čo zaznamenávate pri definovaní?

- Ktorý zákazník alebo používateľ má akú neuspokojenú potrebu?
- Prečo je potrebný nový dizajn a prečo nestačí zlepšovať existujúci proces?
- Aký výsledok by mal návrh priniesť (**Y-01**) a v akom rozsahu?
- Kto rozhoduje o požiadavkách, výbere dizajnu a vydaní?
- Aké plánovanie, predpoklady a kritériá úspechu platia?

---

<!-- _class: canvas -->
<!-- ocideck_template: charter -->

# Projektová charta

## Problém alebo príležitosť

Popíšte nenaplnenú potrebu, cieľovú skupinu a preukázateľný dôvod.

## Cieľ

Formulujte požadovaný výsledok merateľným a časovo ohraničeným spôsobom.

## Rozsah

Všimnite si počiatočný bod, koncový bod, body kontaktu a to, čo nespadá do návrhu.

## Tím

Pomenujte klienta, vlastníka dizajnu, používateľov a požadovaných odborníkov.

## Časová os

Zaznamenajte míľniky, rozhodovacie brány a plánované nasadenie.

## Kritériá úspechu
Kedy dizajn preukázateľne vyhovuje potrebám zákazníkov?

---

<!-- _class: tree -->
<!-- ocideck_template: ctq-tree -->
<!-- ocideck_layout: tree -->

# Merateľné požiadavky zákazníkov (strom CTQ)

- Aký výsledok potrebuje zákazník? — **Y-01**
  - Premeňte túto potrebu na merateľnú požiadavku 1
  - Premeňte túto potrebu na merateľnú požiadavku 2

---

<!-- skip -->

# Kontrolný zoznam — Ako vyplníte SIPOC?

- Začnite s **Zákazníkom**: kto používa nový výsledok procesu?
- Potom identifikujte požadovaný **Výstup** a 4 až 7 zamýšľaných **Procesných** krokov.
- Všimnite si požadovaný **Vstup** a **Dodávateľ**, ktorý sprístupňuje každý vstup.
- Majte všeobecný prehľad; detaily dizajnu budú nasledovať neskôr.
- Skontrolujte, či vybrané hranice zodpovedajú charte a Y-01.

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

# Zmerajte

---

<!-- skip -->

# Kontrolný zoznam — Čo zaznamenávate pri meraní?

- Ktoré potreby zákazníkov sa premietli do merateľných požiadaviek a priorít?
- Čo je cieľová hodnota, dolná alebo horná hranica, jednotka a metóda merania Y-01?
- Aké prípady použitia, objemy a výnimky by mal dizajn zvládnuť?
- Ktoré existujúce úspechy alebo alternatívy používate ako referenciu?
- Ako budete objektívne testovať, či bola každá požiadavka splnená?

---

<!-- _class: section -->

# Analyzovať

---

<!-- skip -->

# Kontrolný zoznam — Čo zaznamenávate pri analýze?

- Aké funkcie musí proces spĺňať, aby splnil požiadavky?
- Aké vzťahy a kompromisy existujú medzi prianiami zákazníkov, rizikami a konštrukčnými prvkami?
- Aké predpoklady je ešte potrebné preskúmať alebo otestovať?
- Ktoré spôsoby zlyhania a závislosti sú najdôležitejšie?
- Aké minimálne kritériá návrhu musí spĺňať každé riešenie?

---

<!-- _class: section -->

# Dizajn

---

<!-- skip -->

# Kontrolný zoznam — Čo zaznamenávate v dizajne?

- Ktoré varianty dizajnu sa zvažovali a podľa akých kritérií sa porovnávali?
- Ako vyzerá zvolený procesný tok vrátane rolí, systémov a presunov?
- Ako návrh predchádza alebo kontroluje hlavné poruchy?
- Čo učí prototyp alebo test o prevádzke a jednoduchosti použitia?
- Ktorý variant ide na overenie, s ktorými otvorenými bodmi?

---

<!-- _class: section -->

# Overiť

---

<!-- skip -->

# Kontrolný zoznam — Čo zaznamenávate pri overovaní?

- Ktorý test pre každú požiadavku dokazuje, že návrh funguje za reálnych podmienok?
- Aké výsledky sa dosiahli a aké odchýlky pretrvávajú?
- Čo si používatelia a vlastníci procesov myslia o prevádzke a uskutočniteľnosti?
- Aké kontroly, inštrukcie a merania sú potrebné po uvedení do prevádzky?
- Kto zverejňuje dizajn a na základe akých dôkazov?
