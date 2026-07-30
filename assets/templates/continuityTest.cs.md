---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Test kontinuity provozu / DR
language: cs
---

<!-- _class: title -->

# Test kontinuity provozu / DR

---

# Testovací scénář

- Scénář: … (např. výpadek datového centra, ransomware)
- Předpoklad: …
- Typ testu: stolní / částečná / plná

---

# Cíle a kritéria úspěchu

- Cíl testu:…
- Kritérium úspěšnosti 1: …
- Kritérium úspěšnosti 2: …

---

<!-- _class: table table-editable -->

# Kritické procesy

| Proces | Priorita | Záleží na |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# Přehled RTO / RPO

| Proces nebo systém | RTO | RPO | Setkal se? |
| --- | --- | --- | --- |
| … | … | … | ano / ne |
| … | … | … | … |

---

<!-- _class: timeline -->

# Testovací časová osa

- T+0 :: Začátek testu :: Scénář oznámen.
- T+… :: Spuštěno převzetí služeb při selhání
- T+… :: Obnovení ověřeno
- T+… :: Konec testu

---

<!-- _class: table table-editable -->

# Zjištění

| Hledání | Závažnost | Komponenta |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Odchylky a blokátory

- Odchylka od příručky: …
- Blokátor během testu: …
- Použité řešení:…

---

# Body zlepšení
<!-- ocideck_list_style: checklist -->

- [ ] Aktualizujte příručku na místě:…
- [ ] Upravit technické nastavení:…
- [ ] Naplánujte si trénink nebo cvičení:…

---

# Schopnost obnovy Go / No-Go
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Kritické procesy obnoveny v rámci RTO
- [ ] Ztráta dat zůstala v RPO
- [ ] Playbook se ukázal jako použitelný
- [ ] Verdikt: schopnost obnovy prokázána
