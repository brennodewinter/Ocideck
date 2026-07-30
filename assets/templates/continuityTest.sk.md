---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Kontinuita prevádzky / test DR
language: sk
---

<!-- _class: title -->

# Kontinuita prevádzky / test DR

---

# Testovací scenár

- Scenár: … (napr. výpadok dátového centra, ransomvér)
- Vopred predpoklad: …
- Typ testu: stolová / čiastočná / plná

---

# Ciele a kritériá úspechu

- Cieľ testu:…
- Kritérium úspešnosti 1: …
- Kritérium úspešnosti 2: …

---

<!-- _class: table table-editable -->

# Kritické procesy

| Proces | Priorita | Závisí od |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# Prehľad RTO / RPO

| Proces alebo systém | RTO | RPO | Stretli ste sa? |
| --- | --- | --- | --- |
| … | … | … | áno / nie |
| … | … | … | … |

---

<!-- _class: timeline -->

# Časová os testu

- T+0 :: Začiatok testu :: Oznámený scenár.
- T+… :: Prepnutie pri zlyhaní začalo
- T+… :: Obnovenie overené
- T+… :: Koniec testu

---

<!-- _class: table table-editable -->

# Zistenia

| Hľadanie | Závažnosť | Komponent |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Odchýlky a blokátory

- Odchýlka od príručky: …
- Blokátor počas testu: …
- Použité riešenie:…

---

# Body zlepšenia
<!-- ocideck_list_style: checklist -->

- [ ] Aktualizujte príručku na mieste:…
- [ ] Úprava technického nastavenia:…
- [ ] Naplánujte si tréning alebo cvičenie:…

---

# Schopnosť obnovy Go / No-go
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Kritické procesy obnovené v rámci RTO
- [ ] Strata dát zostala v rámci RPO
- [ ] Playbook sa ukázal ako použiteľný
- [ ] Verdikt: preukázaná schopnosť obnovy
