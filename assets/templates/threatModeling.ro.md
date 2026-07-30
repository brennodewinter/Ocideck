---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Sesiune de modelare a amenințărilor
language: ro
---

<!-- _class: title -->

# Sesiune de modelare a amenințărilor
## Sistem · Data · Facilitator · Participanți

---

# Domeniul de aplicare și scopul

- Ce sistem sau componentă modelăm astăzi?
- Ceea ce este în mod explicit în afara domeniului de aplicare: …
- Ipoteze cu care lucrăm:…
- Rezultat: amenințări ponderate cu atenuări și un proprietar

---

<!-- _class: table table-editable -->

# Cartografierea sistemului

| Element | Fel | Note |
| --- | --- | --- |
| … | Componentă | … |
| … | Fluxul de date | … |
| … | Partea externă | … |

---

# Granițele de încredere

- Unde trec datele de la de încredere la neîncredere?
- Ce granițe vedem: rețea, proces, utilizator, lanț de aprovizionare?
- Unde au loc autentificarea și validarea intrărilor?
- Desenați fiecare graniță pe schița sistemului: …

---

<!-- _class: table -->

# Referință STRIDE

| Categorie | Sens |
| --- | --- |
| Falsificarea | Pretinde a fi un alt utilizator sau serviciu |
| Falsificarea | Modificarea neautorizată a datelor sau codului |
| Repudiere | Negând că a avut loc vreodată o acțiune |
| Dezvăluirea informațiilor | Informații ajung la cei care nu au voie să o vadă |
| Refuzarea serviciului | Facerea sistemului inutilizabil sau inaccesibil |
| Ridicarea privilegiilor | Obține mai multe privilegii decât s-a acordat |

---

<!-- _class: table table-editable -->

# Colectarea amenințărilor

| Ameninţare | Categoria STRIDE | Componentă | Risc |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Prioritizare: probabilitate × impact

- Probabilitate: cât de probabil este abuzul (scăzut, mediu, mare)?
- Impact: cât de mult daune dacă se întâmplă?
- Risc = probabilitate × impact; high-high merge primul
- În îndoială: alegeți estimarea mai mare și notați de ce

---

<!-- _class: table table-editable -->

# Atenuări și acțiuni

| Atenuare | Proprietar | Stare |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Ceea ce acceptăm cu bună știință

- Ce amenințări nu le abordăm în mod deliberat:...
- De ce este justificat (probabilitate, cost, context): …
- Cine deține această decizie: Rol
- Când revedem asta:...

---

# Sesiune finalizată
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Domeniul de aplicare și ipotezele înregistrate
- [ ] Componentele, fluxurile de date și părțile externe mapate
- [ ] Granițele de încredere trasate
- [ ] Au trecut toate cele șase categorii STRIDE
- [ ] Amenințări prioritizate în funcție de probabilitate × impact
- [ ] Atenuări atribuite unui proprietar
- [ ] Riscuri acceptate înregistrate și deținute
