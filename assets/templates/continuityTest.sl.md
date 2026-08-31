---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Neprekinjeno poslovanje / test DR
language: sl
---

<!-- _class: title -->

# Neprekinjeno poslovanje / test DR

---

# Testni scenarij

- Scenarij: … (npr. izpad podatkovnega centra, izsiljevalska programska oprema)
- Predpostavka: …
- Vrsta testa: namizni / delni / polni

---

# Cilji in merila uspeha

- Cilj testa: …
- Merilo uspeha 1: …
- Merilo uspeha 2: …

---

<!-- _class: table table-editable -->

# Kritični procesi

| Proces | Prioriteta | Odvisno od |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# Pregled RTO / RPO

| Proces ali sistem | RTO | RPO | srečal? |
| --- | --- | --- | --- |
| … | … | … | Da/ne |
| … | … | … | … |

---

<!-- _class: timeline -->

# Časovnica preizkusa

- T+0 :: Testni začetek :: Objavljen scenarij.
- T+… :: Failover se je začel
- T+… :: Izterjava preverjena
- T+… :: Konec testa

---

<!-- _class: table table-editable -->

# Ugotovitve

| Najdba | Resnost | Komponenta |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Deviacije in blokatorji

- Odstopanje od priročnika: …
- Blokada med preskusom: …
- Uporabljena rešitev: …

---

# Točke za izboljšanje
<!-- ocideck_list_style: checklist -->

- [ ] Posodobite priročnik o točki: …
- [ ] Prilagodite tehnične nastavitve: …
- [ ] Urnik treninga ali vadbe: …

---

# Možnost obnovitve Go/No-Go
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Kritični procesi, obnovljeni znotraj RTO
- [ ] Izguba podatkov je ostala znotraj RPO
- [ ] Playbook se je izkazal za uporabnega
- [ ] Razsodba: dokazana sposobnost obnovitve
