---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Relace modelování hrozeb
language: cs
---

<!-- _class: title -->

# Relace modelování hrozeb
## Systém · Datum · Facilitátor · Účastníci

---

# Rozsah a cíl

- Který systém nebo komponentu dnes modelujeme?
- Co je výslovně mimo rozsah: …
- Předpoklady, se kterými pracujeme: …
- Výsledek: vážené hrozby se zmírněním a vlastníkem

---

<!-- _class: table table-editable -->

# Mapování systému

| prvek | Laskavý | Poznámky |
| --- | --- | --- |
| … | Komponenta | … |
| … | Datový tok | … |
| … | Externí strana | … |

---

# Hranice důvěry

- Kde se data kříží od důvěryhodných k nedůvěryhodným?
- Jaké hranice vidíme: síť, proces, uživatel, dodavatelský řetězec?
- Kde probíhá ověřování a ověřování vstupu?
- Nakreslete každou hranici na náčrtu systému: …

---

<!-- _class: table -->

# Reference STRIDE

| Kategorie | Význam |
| --- | --- |
| Spoofing | Předstírání, že jste jiný uživatel nebo služba |
| Manipulace | Neoprávněná úprava dat nebo kódu |
| Odmítnutí | Popírá, že k nějaké akci kdy došlo |
| Zveřejňování informací | Informace se dostávají k těm, kteří je nemají dovoleno vidět |
| Odepření služby | Učinit systém nepoužitelným nebo nedostupným |
| Zvýšení výsady | Získání více privilegií, než je uděleno |

---

<!-- _class: table table-editable -->

# Sbírání hrozeb

| hrozba | kategorie STRIDE | Komponenta | Riziko |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Stanovení priorit: pravděpodobnost × dopad

- Pravděpodobnost: jak pravděpodobné je zneužití (nízké, střední, vysoké)?
- Dopad: jak velká škoda, pokud k tomu dojde?
- Riziko = pravděpodobnost × dopad; high-high jde první
- Nejste na pochybách: vyberte vyšší odhad a poznamenejte si proč

---

<!-- _class: table table-editable -->

# Zmírnění a opatření

| Zmírnění | vlastník | Stav |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Co vědomě přijímáme

- Které hrozby záměrně neřešíme: …
- Proč je to oprávněné (pravděpodobnost, náklady, kontext): …
- Komu patří toto rozhodnutí: Role
- Kdy se k tomu vrátíme:…

---

# Relace dokončena
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Rozsah a předpoklady zaznamenané
- [ ] Mapované komponenty, datové toky a externí strany
- [ ] Hranice důvěry vytyčené
- [ ] Prošlo všech šest kategorií STRIDE
- [ ] Hrozby upřednostněné podle pravděpodobnosti × dopadu
- [ ] Snížení rizika přiřazená vlastníkovi
- [ ] Přijatá rizika zaznamenaná a vlastněná
