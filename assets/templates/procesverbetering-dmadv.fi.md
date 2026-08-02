---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: "Prosessin parantaminen: DMADV-projekti"
language: fi
ocideck_improvement_framework: dmadv
---

<!-- _class: title -->

# Prosessin parantaminen: DMADV-projekti

---

<!-- skip -->

# Näin työskentelet tämän mallin kanssa

- Käytä DMADV:tä uudessa tai perusteellisesti uudelleen suunnitellussa prosessissa ja valitse yksi mitattavissa oleva asiakastulos (**Y-01**).
- Käytä kunkin opasdian kysymyksiä tarkistuslistana; lisää sitten tavallisia dioja vastauksillesi.
- Korvaa peruskirjan ja CTQ-puun selitys projektitiedoillasi, täytä SIPOC ja tee vaatimuksista testattavia ennen suunnittelua.
- Ohjedioja ei esitetä tai viedä. Jos haluat näyttää yhden, poista **Ohita** käytöstä kyseiseltä dialta.

---

<!-- _class: section -->

# Määritä

---

<!-- skip -->

# Tarkistuslista — Mitä tallennat määrittäessäsi?

- Kenellä asiakkaalla tai käyttäjällä on mikä tyydyttämätön tarve?
- Miksi uusi suunnittelu on tarpeen ja miksi nykyisen prosessin parantaminen ei riitä?
- Millaisen tuloksen suunnittelun tulisi tuottaa (**Y-01**) ja missä laajuudessa?
- Kuka päättää vaatimuksista, suunnitteluvalinnoista ja julkaisusta?
- Mitä suunnittelua, ehtoja ja menestyskriteerejä sovelletaan?

---

<!-- _class: canvas -->
<!-- ocideck_template: charter -->

# Projectcharter

## Ongelma tai mahdollisuus

Kuvaa tyydyttämätön tarve, kohderyhmä ja todistettavissa oleva syy.

## Maali

Muotoile haluttu tulos mitattavissa olevalla ja ajallisesti sidottulla tavalla.

## Laajuus

Huomaa aloituspiste, päätepiste, kosketuspisteet ja se, mikä jää suunnittelun ulkopuolelle.

## Joukkue

Nimeä asiakas, suunnittelun omistaja, käyttäjät ja tarvittavat asiantuntijat.

## Aikajana

Tallenna virstanpylväät, päätöksentekoportit ja suunniteltu käyttöönotto.

## Menestyskriteerit
Milloin suunnittelu vastaa todistetusti asiakkaiden tarpeita?

---

<!-- _class: tree -->
<!-- ocideck_template: ctq-tree -->
<!-- ocideck_layout: tree -->

# Mitattavissa olevat asiakkaiden vaatimukset (CTQ-puu)

- Millaisen lopputuloksen asiakas tarvitsee? — **Y-01**
  - Muunna tämä tarve mitattavissa olevaksi vaatimukseksi 1
  - Muunna tämä tarve mitattavissa olevaksi vaatimukseksi 2

---

<!-- skip -->

# Tarkistuslista – Kuinka täytät SIPOC:n?

- Aloita **Asiakkaasta**: kuka käyttää uutta prosessitulosta?
- Määritä sitten tarvittava **lähtö** ja 4–7 suunniteltua **Prosessi**-vaihetta.
- Huomaa vaadittu **Input** ja **Supplier**, jotka tekevät kunkin tulon käytettävissä.
- Pidä yleiskuva; Suunnittelun yksityiskohdat selviävät myöhemmin.
- Tarkista, vastaavatko valitut rajat peruskirjaa ja Y-01.

---

<!-- _class: matrix -->
<!-- ocideck_template: sipoc -->

# SIPOC

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |
|  |  |  |  |  |

---

<!-- _class: section -->

# Mittaa

---

<!-- skip -->

# Tarkistuslista – Mitä tallennat mittaaessasi?

- Mitkä asiakkaiden tarpeet on muutettu mitattavissa oleviksi vaatimuksiksi ja prioriteeteiksi?
- Mitkä ovat Y-01:n tavoitearvo, ala- tai yläraja, yksikkö ja mittausmenetelmä?
- Mitä käyttötapauksia, volyymeja ja poikkeuksia suunnittelun tulee pystyä käsittelemään?
- Mitä olemassa olevia saavutuksia tai vaihtoehtoja käytät viitteenä?
- Kuinka testaat objektiivisesti, onko jokainen vaatimus täytetty?

---

<!-- _class: section -->

# Analysoi

---

<!-- skip -->

# Tarkistuslista – Mitä tallennat analysoiessasi?

- Mitä toimintoja prosessin tulee täyttää täyttääkseen vaatimukset?
- Mitä suhteita ja kompromisseja asiakkaiden toiveiden, riskien ja suunnittelun ominaisuuksien välillä on?
- Mitä oletuksia on vielä tutkittava tai testattava?
- Mitkä vikatilat ja riippuvuudet ovat tärkeimpiä?
- Mitä suunnittelun vähimmäiskriteerejä jokaisen ratkaisun tulee täyttää?

---

<!-- _class: section -->

# Design

---

<!-- skip -->

# Tarkistuslista – Mitä tallennat suunnittelussa?

- Mitä suunnitteluvaihtoehtoja harkittiin ja millä kriteereillä niitä verrattiin?
- Miltä valittu prosessivirta näyttää roolit, järjestelmät ja siirrot mukaan lukien?
- Kuinka suunnittelu estää tai hallitsee suuria vikatiloja?
- Mitä prototyyppi tai testi opettaa toiminnasta ja käytön helppoudesta?
- Mikä versio menee varmennukseen, minkä avoimien kohtien kanssa?

---

<!-- _class: section -->

# Vahvista

---

<!-- skip -->

# Tarkistuslista – Mitä tallennat vahvistaessasi?

- Mikä testi osoittaa kullekin vaatimukselle, että suunnittelu toimii realistisissa olosuhteissa?
- Mitä tuloksia on saavutettu ja mitä poikkeamia on jäljellä?
- Mitä käyttäjät ja prosessien omistajat ajattelevat toiminnasta ja toteutettavuudesta?
- Mitä ohjausta, ohjeita ja mittauksia tarvitaan käyttöönoton jälkeen?
- Kuka julkaisee suunnitelman ja minkä todisteiden perusteella?
