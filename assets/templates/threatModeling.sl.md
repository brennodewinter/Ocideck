---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Seja modeliranja groženj
language: sl
---

<!-- _class: title -->

# Seja modeliranja groženj
## Sistem · Datum · Moderator · Udeleženci

---

# Obseg in cilj

- Kateri sistem ali komponento modeliramo danes?
- Kaj je izrecno izven obsega: …
- Predpostavke, s katerimi delamo: …
- Rezultat: tehtane grožnje z ublažitvami in lastnikom

---

<!-- _class: table table-editable -->

# Kartiranje sistema

| Element | prijazna | Opombe |
| --- | --- | --- |
| … | Komponenta | … |
| … | Pretok podatkov | … |
| … | Zunanja stranka | … |

---

# Meje zaupanja

- Kje podatki prehajajo iz zaupanja vrednih v nezaupljive?
- Katere meje vidimo: omrežje, proces, uporabnik, dobavna veriga?
- Kje poteka preverjanje pristnosti in preverjanje vnosa?
- Narišite vse meje na skici sistema: …

---

<!-- _class: table -->

# Referenca STRIDE

| Kategorija | Pomen |
| --- | --- |
| Prevara | Pretvarjanje, da ste drug uporabnik ali storitev |
| Nedovoljeno poseganje | Nepooblaščeno spreminjanje podatkov ali kode |
| Zavračanje | Zanikanje, da se je dejanje kdaj zgodilo |
| Razkritje informacij | Informacije dosežejo tiste, ki jih ne smejo videti |
| Zavrnitev storitve | Sistem postane neuporaben ali nedosegljiv |
| Zvišanje privilegijev | Pridobivanje več privilegijev kot odobrenih |

---

<!-- _class: table table-editable -->

# Zbiranje groženj

| Grožnja | Kategorija STRIDE | Komponenta | Tveganje |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Določanje prednosti: verjetnost × učinek

- Verjetnost: kako verjetna je zloraba (nizka, srednja, velika)?
- Vpliv: koliko škode, če se zgodi?
- Tveganje = verjetnost × učinek; visoko-visoko gre najprej
- Če dvomite: izberite višjo oceno in zabeležite, zakaj

---

<!-- _class: table table-editable -->

# Omilitve in ukrepi

| Ublažitev | Lastnik | Stanje |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Kar zavestno sprejemamo

- Katerih groženj namenoma ne obravnavamo: …
- Zakaj je to upravičeno (verjetnost, stroški, kontekst): …
- Kdo je lastnik te odločitve: Vloga
- Kdaj si ponovno ogledamo tole: …

---

# Seja končana
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Obseg in predpostavke zabeleženi
- [ ] Komponente, tokovi podatkov in zunanji udeleženci so preslikani
- [ ] Začrtane meje zaupanja
- [ ] Prehodilo je vseh šest kategorij STRIDE
- [ ] Grožnje, razvrščene glede na verjetnost × učinek
- [ ] Omilitve, dodeljene lastniku
- [ ] Sprejeta tveganja so evidentirana in v lasti
