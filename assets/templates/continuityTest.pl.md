---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Test ciągłości działania / DR
language: pl
---

<!-- _class: title -->

# Test ciągłości działania / DR

---

# Scenariusz testowy

- Scenariusz: … (np. awaria centrum danych, oprogramowanie ransomware)
- Założenie z góry: …
- Typ testu: blat / częściowy / pełny

---

# Cele i kryteria sukcesu

- Cel testu: …
- Kryterium sukcesu 1: …
- Kryterium sukcesu 2: …

---

<!-- _class: table table-editable -->

# Procesy krytyczne

| Proces | Priorytet | Zależy |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# Przegląd RTO/RPO

| Proces lub system | RTO | RPO | Spotkałem? |
| --- | --- | --- | --- |
| … | … | … | Tak / nie |
| … | … | … | … |

---

<!-- _class: timeline -->

# Oś czasu testu

- T+0 :: Rozpoczęcie testu :: Scenariusz ogłoszony.
- T+… :: Rozpoczęto pracę awaryjną
- T+… :: Odzysk zweryfikowany
- T+… :: Koniec testu

---

<!-- _class: table table-editable -->

# Ustalenia

| Odkrycie | Powaga | Część |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Odchylenia i blokady

- Odstępstwo od podręcznika: …
- Bloker podczas testu: …
- Zastosowane rozwiązanie: …

---

# Punkty ulepszeń
<!-- ocideck_list_style: checklist -->

- [ ] Zaktualizuj podręcznik w punkcie: …
- [ ] Dostosuj konfigurację techniczną: …
- [ ] Zaplanuj trening lub ćwiczenia:…

---

# Możliwość odzyskiwania w trybie Go/No-Go
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Odzyskano krytyczne procesy w RTO
- [ ] Utrata danych pozostała w ramach RPO
- [ ] Poradnik okazał się użyteczny
- [ ] Werdykt: wykazano zdolność odzyskiwania
