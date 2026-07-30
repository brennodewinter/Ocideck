---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Uhkamallinnusistunto
language: fi
---

<!-- _class: title -->

# Uhkamallinnusistunto
## Järjestelmä · Päivämäärä · Ohjaaja · Osallistujat

---

# Laajuus ja tavoite

- Mitä järjestelmää tai komponenttia mallinnetaan tänään?
- Mikä on nimenomaisesti soveltamisalan ulkopuolella:…
- Oletukset, joiden kanssa työskentelemme:…
- Tulos: painotetut uhat lievennyksellä ja omistajalla

---

<!-- _class: table table-editable -->

# Järjestelmän kartoitus

| Elementti | Ystävällinen | Huomautuksia |
| --- | --- | --- |
| … | Komponentti | … |
| … | Tiedonkulku | … |
| … | Ulkopuolinen puolue | … |

---

# Luottamuksen rajat

- Missä data siirtyy luotetusta epäluotettavaksi?
- Mitä rajoja näemme: verkoston, prosessin, käyttäjän, toimitusketjun?
- Missä todennus ja syötteen validointi tapahtuu?
- Piirrä kaikki rajat järjestelmäluonnokseen: …

---

<!-- _class: table -->

# STRIDE-viite

| Luokka | Merkitys |
| --- | --- |
| Huijausta | Toisena käyttäjänä tai palveluna esittäminen |
| Peukalointi | Tietojen tai koodin luvaton muuttaminen |
| Kieltäminen | Kiistää, että toimintaa olisi koskaan tapahtunut |
| Tietojen paljastaminen | Tieto tavoittaa ne, jotka eivät saa nähdä sitä |
| Palvelun kieltäminen | Järjestelmän tekeminen käyttökelvottomaksi tai tavoittamattomaksi |
| Etuoikeuksien korotus | Saa enemmän etuoikeuksia kuin myönnettiin |

---

<!-- _class: table table-editable -->

# Uhkien kerääminen

| Uhka | STRIDE-luokka | Komponentti | Riski |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Priorisointi: todennäköisyys × vaikutus

- Todennäköisyys: kuinka todennäköistä väärinkäyttö on (pieni, keskitaso, korkea)?
- Vaikutus: kuinka paljon vahinkoa tapahtuu?
- Riski = todennäköisyys × vaikutus; high-high menee ensin
- Jos olet epävarma: valitse korkeampi arvio ja merkitse miksi

---

<!-- _class: table table-editable -->

# Lievennykset ja toimet

| Lieventäminen | Omistaja | Tila |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Mitä me tietoisesti hyväksymme

- Mihin uhkiin emme tietoisesti puutu:…
- Miksi se on perusteltua (todennäköisyys, hinta, konteksti): …
- Kuka omistaa tämän päätöksen: Rooli
- Milloin palataan tähän:…

---

# Istunto valmis
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Laajuus ja oletukset kirjattu
- [ ] Komponentit, tietovirrat ja ulkopuoliset osapuolet kartoitetaan
- [ ] Luottamuksen rajat vedetty
- [ ] Kaikki kuusi STRIDE-luokkaa menivät läpi
- [ ] Uhkat priorisoidaan todennäköisyyden × vaikutuksen mukaan
- [ ] Omistajalle määrätyt lievennykset
- [ ] Hyväksytyt riskit kirjattu ja omistettu
