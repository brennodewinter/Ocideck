---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Threat modeling-sesje
language: fy
---

<!-- _class: title -->

# Threat modeling-sesje
## Systeem · Datum · Fasilitator · Dielnimmers

---

# Doel en omfang

- Hokker systeem of komponint modellearje wy hjoed?
- Wat is eksplisyt bûten it berik: ...
- Oannames dêr't wy mei wurkje: ...
- Resultaat: gewogen bedrigings mei mitigaasjes en in eigner

---

<!-- _class: table table-editable -->

# Mapping it systeem

| Elemint | Kind | Notysjes |
| --- | --- | --- |
| … | Komponint | … |
| … | Gegevensstream | … |
| … | Eksterne partij | … |

---

# Fertrouwen grinzen

- Wêr krúst gegevens fan fertroud nei net fertroud?
- Hokker grinzen sjogge wy: netwurk, proses, brûker, supply chain?
- Wêr bart autentikaasje en ynfiervalidaasje?
- Teken elke grins op 'e systeemskets: ...

---

<!-- _class: table -->

# STRIDE referinsje

| Kategory | Betsjutting |
| --- | --- |
| Spoofing | Foardwaan as in oare brûker of tsjinst |
| Tampering | Unautorisearre wiziging fan gegevens of koade |
| Repudiation | It ûntkennen dat der oait in aksje plakfûn |
| Ynformaasje iepenbiering | Ynformaasje dy't berikt dyjingen dy't net tastien om te sjen it |
| Denial of tsjinst | It systeem ûnbrûkber of ûnberikber meitsje |
| Ferheging fan privileezjes | Mear privileezjes krije as ferliend |

---

<!-- _class: table table-editable -->

# It sammeljen fan bedrigingen

| Bedriging | STRIDE kategory | Komponint | Risiko |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Prioriteit: kâns × ynfloed

- Wierskynlikens: hoe wierskynlik is misbrûk (leech, medium, heech)?
- Impact: hoefolle skea as it bart?
- Risiko = kâns × ynfloed; heech-heech giet earst
- Yn twifel: kies de hegere skatting en notearje wêrom

---

<!-- _class: table table-editable -->

# Mitigaasjes en aksjes

| Mitigaasje | Eigner | Status |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Wat wy bewust akseptearje

- Hokker bedrigingen pakke wy bewust net oan: ...
- Wêrom is dat terjochte (wierskynlikens, kosten, kontekst): ...
- Wa is eigner fan dit beslút: Rol
- Wannear sille wy dit opnij besjen: ...

---

# Sesje klear
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Omfang en oannames opnommen
- [ ] Komponinten, gegevensstreamen en eksterne partijen yn kaart brocht
- [ ] Trust grinzen lutsen
- [ ] Alle seis STRIDE-kategoryen rûnen troch
- [ ] Bedrigingen prioritearre troch kâns × ynfloed
- [ ] Mitigaasjes tawiisd oan in eigner
- [ ] Akseptearre risiko's opnommen en eigendom
