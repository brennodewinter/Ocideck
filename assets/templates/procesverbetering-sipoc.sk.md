---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Prehľad procesu SIPOC
language: sk
---

<!-- _class: title -->

# Prehľad procesu SIPOC
## Dodávateľ · Vstup · Proces · Výstup · Zákazník

---

<!-- skip -->

# Takto sa pracuje s touto šablónou

- Použite SIPOC na pochopenie rozsahu a závislostí jedného procesu, nie na zaznamenanie každej akcie.
- Použite pomoc a riadok s príkladom ako kontrolný zoznam; zadajte svoje odpovede na **Spracovanie hraníc** a do prázdnej **SIPOC** matice.
- Prednostne pracujte od zákazníka k dodávateľovi s podstatnými menami pre vstup a výstup a so slovesami pre kroky procesu.
- Z prezentácie a exportu budú vynechané iba snímky označené **Preskočené**. Zapnite alebo vypnite **Preskočiť** a získajte vysvetlenia, ktoré vaše publikum môže alebo nemusí potrebovať.

---

# Čo mapuje SIPOC?

- **Dodávateľ:** poskytuje informácie alebo zdroje, ktoré proces potrebuje.
- **Vstup:** údaje, materiály alebo iné podmienky požadované procesom.
- **Proces:** 4 až 7 aktivít na vysokej úrovni, ktoré transformujú vstup.
- **Výstup:** produkt, služba alebo informácie, ktoré proces vytvára.
- **Zákazník:** interný alebo externý príjemca výstupu.

---

<!-- _class: table table-editable -->

# Nastavte hranice procesu

| Hranica | Hodnota |
| --- | --- |
| Názov procesu |  |
| Východiskový bod |  |
| Koncový bod |  |

---

<!-- skip -->

# Kontrolný zoznam — Kedy sú hranice dostatočne jasné?

- **Proces:** dajte mu rozpoznateľný názov so slovesom a predmetom, napríklad „Zaregistrovať objednávku“.
- **Počiatočný bod:** Pomenujte jednu pozorovateľnú udalosť, napríklad „Prijatá žiadosť“.
- **Koncový bod:** pomenujte jeden preukázateľný výsledok, napríklad „Odoslané potvrdenie objednávky“.
- Vyberte si hranice, okolo ktorých môže tím uzatvárať zmysluplné dohody.
- Presuňte výnimky a priľahlé procesy mimo matricu; zapíšte si ich samostatne.

---

<!-- skip -->

# Kontrolný zoznam — Vyplňte sprava doľava

1. Nastavte jasné počiatočné a koncové body procesu.
2. Vymenujte zákazníkov, ktorí závisia od výsledku.
3. Popíšte výstupy, ktoré dostávajú.
4. Zhrňte proces do 4 až 7 aktivít na vysokej úrovni.
5. Zistite, ktoré vstupy tieto činnosti potrebujú.
6. Prepojte každý vstup s dodávateľom, ktorý ho sprístupňuje.

---

<!-- skip -->
<!-- _class: table -->

# Kontrolný zoznam — Príklad jedného pripojeného riadku

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
| Predaj | Schválená žiadosť | Skontrolujte objednávku → zaregistrujte sa → potvrďte | Potvrdenie objednávky | Žiadateľ |

- Čítajte riadok ako jeden reťazec: dodávateľ poskytuje vstup, proces ho mení na výstup pre zákazníka.
- Nový riadok pridajte len vtedy, ak je reťaz výrazne odlišná.
- Informujte sa u zainteresovaných, aby ste sa uistili, že nechýba žiadny dôležitý dodávateľ, vstup, výstup alebo zákazník.

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

# SIPOC alebo podrobný vývojový diagram?

| Charakteristický | SIPOC | Podrobný vývojový diagram |
| --- | --- | --- |
| Účel | Definujte rozsah a vzťahy | Dokumentujte prácu a rozhodnutia |
| Detail | 4 až 7 aktivít na vysokej úrovni | Môže obsahovať desiatky krokov |
| Zamerajte sa | Dodávatelia, vstupy, výstupy a zákazníci | Postupnosť, odovzdania a rozhodovacie body |
| Použite | Začiatok úsilia o zlepšenie | Analýza vykonania a chýb |
