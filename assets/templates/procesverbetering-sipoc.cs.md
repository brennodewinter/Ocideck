---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Přehled procesu SIPOC
language: cs
---

<!-- _class: title -->

# Přehled procesů SIPOC
## Dodavatel · Vstup · Proces · Výstup · Zákazník

---

<!-- skip -->

# Takto se pracuje s touto šablonou

- Použijte SIPOC k pochopení rozsahu a závislostí jednoho procesu, nikoli k zaznamenání každé akce.
- Použijte nápovědu a ukázkový řádek jako kontrolní seznam; zadejte své odpovědi na **Hranice procesu** a do prázdné matice **SIPOC**.
- Přednostně pracujte od zákazníka k dodavateli s podstatnými jmény pro vstup a výstup a slovesy pro kroky procesu.
- Z prezentace a exportu budou vynechány pouze snímky označené **Přeskočeno**. Zapněte nebo vypněte **Přeskočit** pro vysvětlení, která vaše publikum může nebo nemusí potřebovat.

---

# Co SIPOC mapuje?

- **Dodavatel:** poskytuje informace nebo zdroje, které proces potřebuje.
- **Vstup:** data, materiály nebo jiné podmínky požadované procesem.
- **Proces:** 4 až 7 aktivit na vysoké úrovni, které transformují vstup.
- **Výstup:** produkt, služba nebo informace, které proces produkuje.
- **Zákazník:** interní nebo externí příjemce výstupu.

---

<!-- _class: table table-editable -->

# Nastavte hranice procesu

| Hranice | Hodnota |
| --- | --- |
| Název procesu |  |
| Výchozí bod |  |
| Koncový bod |  |

---

<!-- skip -->

# Kontrolní seznam — Kdy jsou hranice dostatečně jasné?

- **Proces:** dejte mu rozpoznatelný název se slovesem a předmětem, například „Zaregistrovat objednávku“.
- **Výchozí bod:** Pojmenujte jednu pozorovatelnou událost, například „Žádost přijata“.
- **Koncový bod:** pojmenujte jeden prokazatelný výsledek, například „Potvrzení objednávky odesláno“.
- Zvolte hranice, kolem kterých může tým uzavírat smysluplné dohody.
- Přesunout výjimky a sousední procesy mimo matici; zapište je samostatně.

---

<!-- skip -->

# Kontrolní seznam — Vyplňte zprava doleva

1. Nastavte jasné počáteční a koncové body procesu.
2. Vyjmenujte zákazníky, kteří jsou na výsledku závislí.
3. Popište výstupy, které dostávají.
4. Shrňte proces do 4 až 7 činností na vysoké úrovni.
5. Určete, které vstupy tyto činnosti potřebují.
6. Propojte každý vstup s dodavatelem, který jej zpřístupňuje.

---

<!-- skip -->
<!-- _class: table -->

# Kontrolní seznam — Příklad jednoho připojeného řádku

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
| Prodej | Schválená žádost | Zkontrolovat objednávku → zaregistrovat → potvrdit | Potvrzení objednávky | Žadatel |

- Čtěte řádek jako jeden řetězec: dodavatel poskytuje vstup, proces jej mění na výstup pro zákazníka.
- Nový řádek přidejte pouze v případě, že se řetěz výrazně liší.
- Informujte se u zúčastněných, abyste se ujistili, že nechybí žádný důležitý dodavatel, vstup, výstup nebo zákazník.

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

# SIPOC nebo podrobný vývojový diagram?

| Charakteristický | SIPOC | Podrobný vývojový diagram |
| --- | --- | --- |
| Účel | Definujte rozsah a vztahy | Dokumentovat práci a rozhodnutí |
| Detail | 4 až 7 aktivit na vysoké úrovni | Může obsahovat desítky kroků |
| Soustředit | Dodavatelé, vstupy, výstupy a zákazníci | Posloupnost, předávání a rozhodovací body |
| Použití | Začátek snahy o zlepšení | Analýza provedení a chyb |
