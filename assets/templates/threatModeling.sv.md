---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Hotmodelleringssession
language: sv
---

<!-- _class: title -->

# Hotmodelleringssession
## System · Datum · Handledare · Deltagare

---

# Omfattning och mål

- Vilket system eller vilken komponent modellerar vi idag?
- Vad som uttryckligen ligger utanför räckvidden: …
- Antaganden vi arbetar med: …
- Resultat: viktade hot med begränsningar och en ägare

---

<!-- _class: table table-editable -->

# Kartläggning av systemet

| Element | Slag | Anteckningar |
| --- | --- | --- |
| … | Komponent | … |
| … | Dataflöde | … |
| … | Extern part | … |

---

# Lita på gränser

- Var går data från betrodd till opålitlig?
- Vilka gränser ser vi: nätverk, process, användare, försörjningskedja?
- Var sker autentisering och indatavalidering?
- Rita varje gräns på systemskissen: …

---

<!-- _class: table -->

# STRIDE referens

| Kategori | Menande |
| --- | --- |
| Spoofing | Utger sig för att vara en annan användare eller tjänst |
| manipulering | Obehörig ändring av data eller kod |
| Förkastande | Förnekar att en åtgärd någonsin har ägt rum |
| Informationsutlämnande | Information som når dem som inte får se den |
| Denial of service | Göra systemet oanvändbart eller oåtkomligt |
| Förhöjning av privilegier | Får fler privilegier än beviljat |

---

<!-- _class: table table-editable -->

# Samlar in hot

| Hot | STRIDE kategori | Komponent | Risk |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Prioritering: sannolikhet × påverkan

- Sannolikhet: hur troligt är missbruk (låg, medel, hög)?
- Effekt: hur mycket skada om det händer?
- Risk = sannolikhet × påverkan; hög-hög går först
- I tvivel: välj den högre uppskattningen och notera varför

---

<!-- _class: table table-editable -->

# Åtgärder och åtgärder

| Begränsning | Ägare | Status |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Vad vi medvetet accepterar

- Vilka hot tar vi medvetet inte upp: …
- Varför är det motiverat (sannolikhet, kostnad, sammanhang): ...
- Vem äger detta beslut: Roll
- När återkommer vi till detta:...

---

# Session klar
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Omfattning och antaganden registrerade
- [ ] Komponenter, dataflöden och externa parter kartlagda
- [ ] Förtroendegränser dragna
- [ ] Alla sex STRIDE-kategorierna gick igenom
- [ ] Hot prioriteras efter sannolikhet × effekt
- [ ] Åtgärder tilldelade en ägare
- [ ] Accepterade risker registrerade och ägda
