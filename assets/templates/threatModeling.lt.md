---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Grėsmių modeliavimo sesija
language: lt
---

<!-- _class: title -->

# Grėsmių modeliavimo sesija
## Sistema · Data · Pagalbininkas · Dalyviai

---

# Taikymo sritis ir tikslas

- Kurią sistemą ar komponentą šiandien modeliuojame?
- Kas aiškiai nepatenka į taikymo sritį: …
- Prielaidos, su kuriomis dirbame:…
- Rezultatas: svertiniai grasinimai su švelninimu ir savininku

---

<!-- _class: table table-editable -->

# Sistemos kartografavimas

| Elementas | Malonus | Pastabos |
| --- | --- | --- |
| … | Komponentas | … |
| … | Duomenų srautas | … |
| … | Išorinis vakarėlis | … |

---

# Pasitikėjimo ribos

- Kur duomenys pereina nuo patikimų prie nepatikimų?
- Kokias ribas matome: tinklą, procesą, vartotoją, tiekimo grandinę?
- Kur vyksta autentifikavimas ir įvesties patvirtinimas?
- Nubrėžkite visas sistemos eskizo ribas: …

---

<!-- _class: table -->

# STRIDE nuoroda

| Kategorija | Reikšmė |
| --- | --- |
| Apgaulė | Apsimesti kitu vartotoju ar paslauga |
| Sugadinimas | Neleistinas duomenų ar kodo keitimas |
| Atsisakymas | Neigė, kad veiksmas kada nors vyko |
| Informacijos atskleidimas | Informacija pasiekia tuos, kuriems neleidžiama jos matyti |
| Paslaugų atsisakymas | Sistema tampa netinkama naudoti arba nepasiekiama |
| Privilegijų pakėlimas | Įgyti daugiau privilegijų nei suteikta |

---

<!-- _class: table table-editable -->

# Grasinimų rinkimas

| Grėsmė | STRIDE kategorija | Komponentas | Rizika |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Prioritetas: tikimybė × poveikis

- Tikimybė: kiek piktnaudžiavimo tikimybė (maža, vidutinė, didelė)?
- Poveikis: kiek žalos, jei taip atsitiks?
- Rizika = tikimybė × poveikis; aukštas-aukštas eina pirmas
- Jei abejojate: pasirinkite didesnę sąmatą ir pažymėkite, kodėl

---

<!-- _class: table table-editable -->

# Švelninimo priemonės ir veiksmai

| Sušvelninimas | Savininkas | Būsena |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Ką mes sąmoningai priimame

- Į kokių grėsmių mes sąmoningai nereaguojame:…
- Kodėl tai pagrįsta (tikimybė, kaina, kontekstas): …
- Kam priklauso šis sprendimas: Vaidmuo
- Kada tai dar kartą peržiūrėsime:…

---

# Sesija baigta
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Taikymo sritis ir užrašytos prielaidos
- [ ] Komponentai, duomenų srautai ir išorinės šalys susietos
- [ ] Nubrėžtos pasitikėjimo ribos
- [ ] Įveiktos visos šešios STRIDE kategorijos
- [ ] Grėsmės, suteiktos pagal tikimybę × poveikį
- [ ] Savininkui priskirtos švelninimo priemonės
- [ ] Priimta rizika užfiksuota ir priklausanti
