---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: MIAUW pentesti aruanne
language: et
---

<!-- _class: title -->

# MIAUW pentesti aruanne

---

<!-- _class: section -->

# 1. Üldine

---

# Dokumendihaldus

- Selle aruande digitaalne edastamine koos kinnitusräsi (SHA-256).
- Reporter ja nõutav sertifikaat (OSCP/OSEP/OSCE/OSWE/eWPTX).
- Aruande versioon ja avaldamise kuupäev.
- Konfidentsiaalsus ja TLP klassifikatsioon.
- Jaotusnimekiri: kes selle aruande saab.

---

<!-- _class: sign-off -->

# Aus aruandlus


---

<!-- _class: section -->

# 2. Lähenemisplaan

---

# Ülesanne ja ulatus

- Sissevõtt ja uurimise põhjus.
- Eesmärk ja uurimisküsimused.
- Omandiõigus, jurisdiktsioon ja allakirjutamine ulatuse kohta.
- Aruandluskeel.
- Hüvitis ja juriidilised tingimused.

---

<!-- _class: scope-matrix -->

# Ulatus ja standardid

| Objekt | Tüüp | Standardne | Olek | Märkus | C | I | A |
| --- | --- | --- | --- | --- | --- | --- | --- |
|  | Veeb | WSTG |  |  |  |  |  |

---

<!-- _class: section -->

# 3. Täitmine

---

# Täitmistegevused

- Eeldage rikkumist lähtepunktiks.
- Kvalifikatsioon CVSS 4.0-ga (skoor + vektoristring).
- Tõendid: tõendusmaterjali räsid (SHA1/SHA-256).
- Skaneerimistulemuste kinnitamine (skanneri pime usaldus puudub).
- Kasutatud juurdepääsuteede dokumenteerimine.

---

<!-- _class: section -->

# 4. Aruandlus

---

<!-- _class: findings-summary -->

# Kokkuvõte

| Raskusaste | Count |
| --- | --- |
| Kriitiline | 0 |
| Kõrge | 0 |
| Keskmine | 0 |
| Madal | 0 |
| Mitte ühtegi | 0 |
| Lahendatud | 0 |

---

<!-- _class: timeline -->

# Uurimise ajakava

- Sissevõtt :: Algus :: Ulatus ja kokkulepped kehtestatud.
- Test :: Täitmine :: Uurimise katseperiood.
- Raport :: Kohaletoimetamine :: Kavand ja lõpparuanne.

---

<!-- _class: finding -->

# F-01 · Näidisleidmine

**Scope object:** `<scope-object>`

## Description

Kirjeldage siin asjalikult ja tehniliselt, milles turvaprobleem seisneb.

## Confirmation (reproduction)

Kirjeldage korratavalt (koos tõenditega), kuidas leid tuvastati.

## Possible impact

Kirjeldage võimalikku tehnilist ja ärilist mõju.

## Recommendation

Kirjeldage konkreetset ja teostatavat leevendust.

---

<!-- _class: checklist -->

# Kontrollnimekiri vastavalt standardile

| ID | Test | Olek | Leidmine | Märkus |
| --- | --- | --- | --- | --- |
|  |  |  | — |  |
|  |  |  | — |  |

---

# Lisad

- Sõnastik.
- Kasutatud tööriistad.
- Vastu võetud dokumendid ja failid (SHA1-ga).
- Kasutatud kontod.
- Skanni tulemused.
- Tõendusmaterjal (koos SHA1-ga).
- Kontrollnimekirjad vastavalt standardile.
- Ligipääsmatud objektid.

