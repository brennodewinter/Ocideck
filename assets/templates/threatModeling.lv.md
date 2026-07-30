---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Draudu modelēšanas sesija
language: lv
---

<!-- _class: title -->

# Draudu modelēšanas sesija
## Sistēma · Datums · Vadītājs · Dalībnieki

---

# Darbības joma un mērķis

- Kuru sistēmu vai komponentu mēs šodien modelējam?
- Kas ir nepārprotami ārpus darbības jomas: …
- Pieņēmumi, ar kuriem mēs strādājam:…
- Rezultāts: svērti draudi ar mazināšanas pasākumiem un īpašnieku

---

<!-- _class: table table-editable -->

# Sistēmas kartēšana

| Elements | Laipni | Piezīmes |
| --- | --- | --- |
| … | Komponents | … |
| … | Datu plūsma | … |
| … | Ārējā ballīte | … |

---

# Uzticības robežas

- Kur dati pāriet no uzticamiem uz neuzticamiem?
- Kādas robežas mēs redzam: tīklu, procesu, lietotāju, piegādes ķēdi?
- Kur notiek autentifikācija un ievades validācija?
- Uzzīmējiet visas robežas sistēmas skicē: …

---

<!-- _class: table -->

# STRIDE atsauce

| Kategorija | Nozīme |
| --- | --- |
| Maldināšana | Izliekas par citu lietotāju vai pakalpojumu |
| Iejaukšanās | Neatļauta datu vai koda modificēšana |
| Atteikšanās | Noliedzot, ka kāda darbība jebkad būtu notikusi |
| Informācijas izpaušana | Informācija sasniedz tos, kuriem nav atļauts to redzēt |
| Pakalpojuma atteikums | Padarot sistēmu nelietojamu vai nesasniedzamu |
| Privilēģiju paaugstināšana | Iegūt vairāk privilēģiju nekā piešķirts |

---

<!-- _class: table table-editable -->

# Draudu vākšana

| Draudi | STRIDE kategorija | Komponents | Risks |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Prioritātes noteikšana: iespējamība × ietekme

- Varbūtība: cik liela ir ļaunprātīgas izmantošanas iespējamība (zema, vidēja, augsta)?
- Ietekme: cik daudz bojājumu, ja tas notiek?
- Risks = iespējamība × ietekme; high-high iet pirmais
- Ja rodas šaubas: izvēlieties augstāku aplēsi un atzīmējiet, kāpēc

---

<!-- _class: table table-editable -->

# Mīkstināšanas un darbības

| Mīkstināšana | Īpašnieks | Statuss |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Ko mēs apzināti pieņemam

- Kurus draudus mēs apzināti nerisinām:…
- Kāpēc tas ir pamatoti (iespējamība, izmaksas, konteksts): …
- Kam pieder šis lēmums: loma
- Kad mēs to pārskatīsim:…

---

# Sesija pabeigta
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Reģistrēts darbības joma un pieņēmumi
- [ ] Sastāvdaļas, datu plūsmas un ārējās puses ir kartētas
- [ ] Novilktas uzticības robežas
- [ ] Visas sešas STRIDE kategorijas tika izietas cauri
- [ ] Draudi prioritātes pēc iespējamības × ietekmes
- [ ] Īpašniekam piešķirti atvieglojumi
- [ ] Pieņemtie riski reģistrēti un pieder
