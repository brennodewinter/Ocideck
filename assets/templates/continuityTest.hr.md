---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Kontinuitet poslovanja / DR test
language: hr
---

<!-- _class: title -->

# Kontinuitet poslovanja / DR test

---

# Testni scenarij

- Scenarij: … (npr. ispad podatkovnog centra, ransomware)
- Pretpostavka unaprijed: …
- Vrsta testa: stolni / djelomični / puni

---

# Ciljevi i kriteriji uspjeha

- Cilj testa: …
- Kriterij uspjeha 1: …
- Kriterij uspjeha 2: …

---

<!-- _class: table table-editable -->

# Kritični procesi

| Proces | Prioritet | Ovisi o |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# RTO / RPO pregled

| Proces ili sustav | RTO | RPO | upoznao? |
| --- | --- | --- | --- |
| … | … | … | Da/ne |
| … | … | … | … |

---

<!-- _class: timeline -->

# Testna vremenska traka

- T+0 :: Početak testa :: Objavljen scenarij.
- T+… :: Započeto preusmjeravanje greške
- T+… :: Oporavak potvrđen
- T+… :: Kraj testa

---

<!-- _class: table table-editable -->

# Nalazi

| Pronalaženje | Ozbiljnost | komponenta |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Devijacije i blokatori

- Odstupanje od priručnika: …
- Blokator tijekom testa: …
- Korišteno zaobilazno rješenje: …

---

# Bodovi poboljšanja
<!-- ocideck_list_style: checklist -->

- [ ] Ažurirajte priručnik o točki: …
- [ ] Prilagodite tehničke postavke: …
- [ ] Raspored treninga ili vježbi: …

---

# Go / no-go sposobnost oporavka
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Kritični procesi oporavljeni unutar RTO
- [ ] Gubitak podataka ostao je unutar RPO-a
- [ ] Playbook se pokazao upotrebljivim
- [ ] Presuda: dokazana sposobnost oporavka
