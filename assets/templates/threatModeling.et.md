---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Ohumodelleerimise sessioon
language: et
---

<!-- _class: title -->

# Ohumodelleerimise sessioon
## Süsteem · Kuupäev · Läbiviija · Osalejad

---

# Ulatus ja eesmärk

- Millist süsteemi või komponenti me täna modelleerime?
- Mis on selgelt reguleerimisalast väljas: …
- Eeldused, millega töötame: …
- Tulemus: kaalutud ohud koos leevendustega ja omanikuga

---

<!-- _class: table table-editable -->

# Süsteemi kaardistamine

| Element | Lahke | Märkmed |
| --- | --- | --- |
| … | Komponent | … |
| … | Andmevoog | … |
| … | Väline pidu | … |

---

# Usalduse piirid

- Kus lähevad andmed usaldusväärsetelt ebausaldusväärseteks?
- Milliseid piire me näeme: võrgustik, protsess, kasutaja, tarneahel?
- Kus toimub autentimine ja sisendi valideerimine?
- Joonistage süsteemi visandile kõik piirid: …

---

<!-- _class: table -->

# STRIDE viide

| Kategooria | Tähendus |
| --- | --- |
| Pettus | Teise kasutaja või teenusena esinemine |
| Sattumine | Andmete või koodi volitamata muutmine |
| Äraütlemine | Eitades, et tegevus kunagi aset leidis |
| Teabe avalikustamine | Teave jõuab nendeni, kellel pole lubatud seda näha |
| Teenusest keeldumine | Süsteemi muutmine kasutuskõlbmatuks või kättesaamatuks |
| Privileegide tõus | Saades rohkem privileege, kui neile antakse |

---

<!-- _class: table table-editable -->

# Ähvarduste kogumine

| Oht | STRIDE kategooria | Komponent | Risk |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Prioriteetide seadmine: tõenäosus × mõju

- Tõenäosus: kui tõenäoline on kuritarvitamine (madal, keskmine, kõrge)?
- Mõju: kui palju kahju, kui see juhtub?
- risk = tõenäosus × mõju; kõrge-kõrge läheb esimeseks
- Kahtluse korral: valige kõrgem hinnang ja märkige, miks

---

<!-- _class: table table-editable -->

# Leevendused ja tegevused

| Leevendus | Omanik | Olek |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Mida me teadlikult aktsepteerime

- Milliseid ohte me teadlikult ei käsitle: …
- Miks see on õigustatud (tõenäosus, maksumus, kontekst): …
- Kellele see otsus kuulub: roll
- Millal me seda uuesti vaatame:…

---

# Seanss lõppenud
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Salvestatud ulatus ja eeldused
- [ ] Komponendid, andmevood ja välised osapooled kaardistatud
- [ ] Usalduse piirid tõmmatud
- [ ] Kõik kuus STRIDE kategooriat läbisid
- [ ] Ohud, mille prioriteet on tõenäosus × mõju
- [ ] Leevendused on määratud omanikule
- [ ] Aktsepteeritud riskid on registreeritud ja omatud
