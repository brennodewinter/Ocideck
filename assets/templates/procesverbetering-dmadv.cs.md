---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: "Zlepšení procesů: projekt DMADV"
language: cs
ocideck_improvement_framework: dmadv
---

<!-- _class: title -->

# Zlepšení procesů: projekt DMADV

---

<!-- skip -->

# Takto se pracuje s touto šablonou

- Použijte DMADV pro nový nebo zásadně přepracovaný proces a vyberte si jeden měřitelný zákaznický výsledek (**Y-01**).
- Použijte otázky na každém snímku průvodce jako kontrolní seznam; pak pro své odpovědi přidejte běžné snímky.
- Nahraďte vysvětlení v chartě a stromu CTQ informacemi o vašem projektu, vyplňte SIPOC a před návrhem udělejte testovatelné požadavky.
- Snímky nápovědy nejsou prezentovány ani exportovány. Chcete-li některý zobrazit, vypněte u tohoto snímku **Přeskočit**.

---

<!-- _class: section -->

# Definujte

---

<!-- skip -->

# Kontrolní seznam — Co zaznamenáváte při definování?

- Který zákazník nebo uživatel má jakou neuspokojenou potřebu?
- Proč je nutný nový design a proč zlepšení stávajícího procesu nestačí?
- Jaký výsledek by měl návrh přinést (**Y-01**) a v jakém rozsahu?
- Kdo rozhoduje o požadavcích, volbě designu a vydání?
- Jaké plánování, předpoklady a kritéria úspěchu platí?

---

<!-- _class: canvas -->
<!-- ocideck_template: charter -->

# Projektová charta

## Problém nebo příležitost

Popište nenaplněnou potřebu, cílovou skupinu a prokazatelný důvod.

## Cíl

Formulujte požadovaný výsledek měřitelným a časově omezeným způsobem.

## Rozsah

Všimněte si počátečního bodu, koncového bodu, bodů kontaktu a toho, co spadá mimo návrh.

## Tým

Jmenujte klienta, vlastníka designu, uživatele a požadované odborníky.

## Časová osa

Zaznamenávejte milníky, rozhodovací brány a zamýšlené nasazení.

## Kritéria úspěchu
Kdy návrh prokazatelně vyhovuje potřebám zákazníka?

---

<!-- _class: tree -->
<!-- ocideck_template: ctq-tree -->
<!-- ocideck_layout: tree -->

# Měřitelné požadavky zákazníků (strom CTQ)

- Jaký výsledek zákazník potřebuje? — **Y-01**
  - Převeďte tuto potřebu na měřitelný požadavek 1
  - Převeďte tuto potřebu na měřitelný požadavek 2

---

<!-- skip -->

# Kontrolní seznam — Jak vyplníte SIPOC?

- Začněte s **Zákazníkem**: kdo používá nový výsledek procesu?
- Poté identifikujte požadovaný **Výstup** a 4 až 7 zamýšlených **Procesních** kroků.
- Poznamenejte si požadovaný **Vstup** a **Dodavatele**, který každý vstup zpřístupňuje.
- Udržujte si všeobecný přehled; detaily designu budou následovat později.
- Zkontrolujte, zda vybrané hranice odpovídají chartě a Y-01.

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

# Změřte

---

<!-- skip -->

# Kontrolní seznam — Co zaznamenáváte při měření?

- Které potřeby zákazníků byly převedeny do měřitelných požadavků a priorit?
- Jaké jsou cílové hodnoty, spodní nebo horní limit, jednotka a metoda měření Y-01?
- Jaké případy použití, objemy a výjimky by měl návrh zvládnout?
- Které existující úspěchy nebo alternativy používáte jako reference?
- Jak budete objektivně testovat, zda byl každý požadavek splněn?

---

<!-- _class: section -->

# Analyzujte

---

<!-- skip -->

# Kontrolní seznam — Co zaznamenáváte při analýze?

- Jaké funkce musí proces splňovat, aby splnil požadavky?
- Jaké vztahy a kompromisy existují mezi přáními zákazníků, riziky a konstrukčními prvky?
- Jaké předpoklady je ještě třeba prozkoumat nebo otestovat?
- Které způsoby selhání a závislosti jsou nejdůležitější?
- Jaká minimální kritéria návrhu musí splňovat každé řešení?

---

<!-- _class: section -->

# Design

---

<!-- skip -->

# Kontrolní seznam — Co zaznamenáváte v Designu?

- Které varianty návrhu byly zvažovány a podle jakých kritérií byly porovnávány?
- Jak vypadá zvolený procesní tok, včetně rolí, systémů a převodů?
- Jak návrh zabraňuje nebo kontroluje hlavní režimy selhání?
- Co učí prototyp nebo test o provozu a snadném použití?
- Která varianta jde k ověření, s jakými otevřenými body?

---

<!-- _class: section -->

# Ověřte

---

<!-- skip -->

# Kontrolní seznam — Co zaznamenáváte při ověřování?

- Který test pro každý požadavek prokáže, že návrh funguje za reálných podmínek?
- Jakých výsledků bylo dosaženo a jaké odchylky přetrvávají?
- Co si uživatelé a vlastníci procesů myslí o provozu a proveditelnosti?
- Jaká kontrola, instrukce a měření jsou vyžadovány po uvedení do provozu?
- Kdo uvolňuje design a na základě jakých důkazů?
