---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Relácia modelovania hrozieb
language: sk
---

<!-- _class: title -->

# Relácia modelovania hrozieb
## Systém · Dátum · Facilitátor · Účastníci

---

# Rozsah a cieľ

- Ktorý systém alebo komponent dnes modelujeme?
- Čo je výslovne mimo rozsahu pôsobnosti: …
- Predpoklady, s ktorými pracujeme: …
- Výsledok: vážené hrozby so zmiernením a vlastníkom

---

<!-- _class: table table-editable -->

# Mapovanie systému

| Prvok | Milý | Poznámky |
| --- | --- | --- |
| … | Komponent | … |
| … | Dátový tok | … |
| … | Externá strana | … |

---

# Hranice dôvery

- Kde prechádzajú údaje od dôveryhodných k nedôveryhodným?
- Aké hranice vidíme: sieť, proces, používateľ, dodávateľský reťazec?
- Kde prebieha overenie a overenie vstupu?
- Nakreslite každú hranicu na náčrte systému: …

---

<!-- _class: table -->

# Referencia STRIDE

| Kategória | Význam |
| --- | --- |
| Spoofing | Vydávanie sa za iného používateľa alebo služby |
| Manipulácia | Neoprávnená úprava údajov alebo kódu |
| Odmietanie | Popieranie, že by k nejakej akcii niekedy došlo |
| Zverejňovanie informácií | Informácie sa dostanú k tým, ktorí ich nemôžu vidieť |
| Odmietnutie služby | Robiť systém nepoužiteľným alebo nedostupným |
| Zvýšenie výsady | Získanie viac privilégií, ako bolo udelených |

---

<!-- _class: table table-editable -->

# Zbieranie hrozieb

| Hrozba | kategória STRIDE | Komponent | Riziko |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Stanovenie priorít: pravdepodobnosť × vplyv

- Pravdepodobnosť: aká je pravdepodobnosť zneužitia (nízka, stredná, vysoká)?
- Vplyv: aké veľké škody, ak sa to stane?
- Riziko = pravdepodobnosť × vplyv; high-high ide prvý
- Na pochybách: vyberte vyšší odhad a poznačte si prečo

---

<!-- _class: table table-editable -->

# Zmiernenie a opatrenia

| Zmiernenie | Vlastník | Stav |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Čo vedome prijímame

- Ktorými hrozbami sa zámerne nezaoberáme: …
- Prečo je to opodstatnené (pravdepodobnosť, náklady, kontext): …
- Kto vlastní toto rozhodnutie: Rola
- Kedy sa k tomu vrátime:…

---

# Relácia je dokončená
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Zaznamenaný rozsah a predpoklady
- [ ] Mapované komponenty, dátové toky a externé strany
- [ ] Vytýčené hranice dôvery
- [ ] Prešlo všetkých šesť kategórií STRIDE
- [ ] Hrozby zoradené podľa pravdepodobnosti × vplyvu
- [ ] Zmiernenia priradené vlastníkovi
- [ ] Akceptované riziká zaznamenané a vlastnené
