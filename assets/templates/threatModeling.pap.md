---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Seshon di threat modeling
language: pap
---

<!-- _class: title -->

# Seshon di threat modeling
## Sistema · Fecha · Fasilitadó · Partisipantenan

---

# Alkanse i meta

- Kua sistema òf komponente nos ta modelando awe?
- Loke ta eksplísitamente for di alkanse: …
- Suposishonnan ku nos ta trahando kuné: …
- Resultado: menasanan ponderá ku mitigashonnan i un doño

---

<!-- _class: table table-editable -->

# Mapeo di e sistema

| Elemento | Amabel | Notanan |
| --- | --- | --- |
| … | Komponente | … |
| … | Fluho di dato | … |
| … | Partido eksterno | … |

---

# Fronteranan di konfiansa

- Unda dato ta krusa di konfiabel pa no konfiabel?
- Kua fronteranan nos ta mira: ret, proseso, usuario, kadena di suministro?
- Unda outentikashon i validashon di entrada ta sosodé?
- Traha kada frontera riba e sketch di sistema: …

---

<!-- _class: table -->

# referensia di STRIDE

| Kategoria | Nifikashon |
| --- | --- |
| Parodia | Pretendiendo di ta un otro usuario òf servisio |
| Manipulashon | Modifikashon no outorisá di dato òf kódigo |
| Repudiashon | Negando ku un akshon a yega di tuma lugá |
| Divulgashon di informashon | Informashon ku ta yega na esnan ku no tin mag di mir’é |
| Negashon di servisio | Hasiendo e sistema inutilisabel òf inalkansabel |
| Elevashon di privilegio | Ganando mas privilegio ku a wòrdu otorgá |

---

<!-- _class: table table-editable -->

# Kolekshonando menasanan

| Menasa | kategoria STRIDE | Komponente | Riesgo |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Prioridat: probabilidat × impakto

- Probabilidat: kon probabel ta abusu (abou, mediano, haltu)?
- Impakto: kuantu daño si e sosodé?
- Riesgo = probabilidat × impakto; haltu-haltu ta bai promé
- Den duda: skohe e kalkulashon mas haltu i tuma nota dikon

---

<!-- _class: table table-editable -->

# Mitigashonnan i akshonnan

| Mitigashon | Doño | Status |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Loke nos ta aseptá konsientemente

- Kua menasanan nos no ta atendé deliberadamente: …
- Dikon esei ta hustifiká (probabilidat, kosto, konteksto): …
- Ken ta doño di e desishon aki: Rol
- Ki dia nos ta rebishitá esaki: …

---

# Seshon kompleto
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Alkanse i suposishonnan registrá
- [ ] Komponentenan, fluhonan di dato i partidonan eksterno mapa
- [ ] Limitenan di konfiansa trahá
- [ ] Tur seis kategoria di STRIDE a pasa
- [ ] Menasanan priorisá pa probabilidat × impakto
- [ ] Mitigashonnan asigná na un doño
- [ ] Riesgonan aseptá registrá i propiedat
