---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Sesija modeliranja prijetnji
language: hr
---

<!-- _class: title -->

# Sesija modeliranja prijetnji
## Sustav · Datum · Voditelj · Sudionici

---

# Opseg i cilj

- Koji sustav ili komponentu danas modeliramo?
- Što je izričito izvan opsega: …
- Pretpostavke s kojima radimo: …
- Ishod: ponderirane prijetnje s ublažavanjima i vlasnikom

---

<!-- _class: table table-editable -->

# Mapiranje sustava

| Element | ljubazan | Bilješke |
| --- | --- | --- |
| … | komponenta | … |
| … | Tijek podataka | … |
| … | Vanjska stranka | … |

---

# Granice povjerenja

- Gdje podaci prelaze iz pouzdanih u nepouzdane?
- Koje granice vidimo: mreža, proces, korisnik, opskrbni lanac?
- Gdje se odvijaju autentifikacija i provjera valjanosti unosa?
- Nacrtajte svaku granicu na skici sustava: …

---

<!-- _class: table -->

# STRIDE referenca

| Kategorija | Značenje |
| --- | --- |
| lažiranje | Pretvarajući se da ste drugi korisnik ili usluga |
| petljanje | Neovlaštena izmjena podataka ili koda |
| Poricanje | Poricanje da se akcija ikada dogodila |
| Otkrivanje informacija | Informacije dopiru do onih koji ih ne smiju vidjeti |
| Uskraćivanje usluge | Čini sustav neupotrebljivim ili nedostupnim |
| Povećanje privilegija | Stjecanje više privilegija od dodijeljenih |

---

<!-- _class: table table-editable -->

# Skupljanje prijetnji

| Prijetnja | Kategorija STRIDE | komponenta | Rizik |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Određivanje prioriteta: vjerojatnost × učinak

- Vjerojatnost: koliko je vjerojatno zlostavljanje (nisko, srednje, visoko)?
- Utjecaj: kolika je šteta ako se dogodi?
- Rizik = vjerojatnost × utjecaj; visoko-visoko ide prvo
- U nedoumici: odaberite višu procjenu i zabilježite zašto

---

<!-- _class: table table-editable -->

# Ublažavanja i radnje

| Ublažavanje | Vlasnik | Status |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Ono što svjesno prihvaćamo

- Koje prijetnje namjerno ne rješavamo: …
- Zašto je to opravdano (vjerojatnost, cijena, kontekst): …
- Tko je vlasnik ove odluke: Uloga
- Kada ćemo se vratiti na ovo: …

---

# Sesija završena
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Zabilježeni opseg i pretpostavke
- [ ] Mapirane komponente, tokovi podataka i vanjske strane
- [ ] Povučene su granice povjerenja
- [ ] Prošlo je svih šest STRIDE kategorija
- [ ] Prijetnje s prioritetom prema vjerojatnosti × utjecaju
- [ ] Ublažavanja dodijeljena vlasniku
- [ ] Prihvaćeni rizici evidentirani i posjedovani
