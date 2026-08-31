---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Üzletmenet-folytonosság / DR-teszt
language: hu
---

<!-- _class: title -->

# Üzletmenet-folytonosság / DR-teszt

---

# Teszt forgatókönyv

- Forgatókönyv: … (pl. adatközpont leállás, zsarolóprogram)
- Előzetes feltételezés:…
- Teszt típusa: asztali / részleges / teljes

---

# Célok és sikerkritériumok

- A teszt célja:…
- 1. teljesítési feltétel:…
- 2. teljesítési feltétel:…

---

<!-- _class: table table-editable -->

# Kritikus folyamatok

| Folyamat | Prioritás | attól függ |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# RTO / RPO áttekintése

| Folyamat vagy rendszer | RTO | RPO | Találkoztam? |
| --- | --- | --- | --- |
| … | … | … | Igen/nem |
| … | … | … | … |

---

<!-- _class: timeline -->

# Teszt idővonal

- T+0 :: Teszt kezdete :: Forgatókönyv bejelentése.
- T+… :: Feladatátvétel megkezdődött
- T+… :: Helyreállítás ellenőrizve
- T+… :: Teszt vége

---

<!-- _class: table table-editable -->

# Megállapítások

| Megtalálás | Súlyosság | Összetevő |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Eltérések és blokkolók

- Eltérés a játékkönyvtől:…
- Blokkoló a vizsgálat során:…
- Alkalmazott megoldás:…

---

# Fejlesztési pontok
<!-- ocideck_list_style: checklist -->

- [ ] A játékkönyv frissítése a következő ponton:…
- [ ] Módosítsa a műszaki beállításokat: …
- [ ] Edzés vagy gyakorlat ütemezése:…

---

# Go / no-go helyreállítási képesség
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] A kritikus folyamatok helyreálltak az RTO-n belül
- [ ] Az adatvesztés az RPO-n belül maradt
- [ ] A játékkönyv használhatónak bizonyult
- [ ] Ítélet: a helyreállítási képesség bizonyított
