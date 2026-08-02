---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Pregled SIPOC procesa
language: hr
---

<!-- _class: title -->

# Pregled SIPOC procesa
## Dobavljač · Ulaz · Proces · Izlaz · Kupac

---

<!-- skip -->

# Ovako radite s ovim predloškom

- Koristite SIPOC za razumijevanje opsega i ovisnosti jednog procesa, a ne za bilježenje svake akcije.
- Koristite pomoć i redak primjera kao popis za provjeru; unesite svoje odgovore na **Granice procesa** i u praznu matricu **SIPOC**.
- Po mogućnosti raditi od kupca do dobavljača, s imenicama za ulaz i izlaz i glagolima za korake procesa.
- Samo će slajdovi označeni kao **Preskočeni** biti izostavljeni iz prezentacije i izvoza. Uključite ili isključite **Preskoči** za objašnjenja koja će vašoj publici možda trebati, a možda i neće.

---

# Što SIPOC mapira?

- **Dobavljač:** pruža informacije ili resurse potrebne procesu.
- **Unos:** podaci, materijali ili drugi uvjeti koje zahtijeva proces.
- **Proces:** 4 do 7 aktivnosti visoke razine koje transformiraju unos.
- **Izlaz:** proizvod, usluga ili informacija koju proces proizvodi.
- **Kupac:** unutarnji ili vanjski primatelj izlaza.

---

<!-- _class: table table-editable -->

# Postavite granice procesa

| Granica | Vrijednost |
| --- | --- |
| Naziv procesa |  |
| Početna točka |  |
| Krajnja točka |  |

---

<!-- skip -->

# Kontrolni popis — Kada su granice dovoljno jasne?

- **Proces:** dajte mu prepoznatljivo ime s glagolom i subjektom, na primjer “Registrirajte nalog”.
- **Polazna točka:** Imenujte jedan vidljivi događaj, na primjer “Primljen zahtjev”.
- **Krajnja točka:** navedite jedan rezultat koji se može dokazati, na primjer "Potvrda narudžbe poslana".
- Odaberite granice oko kojih se tim može dogovoriti.
- Premjestiti iznimke i susjedne procese izvan matrice; zapišite ih odvojeno.

---

<!-- skip -->

# Kontrolni popis — Ispunite s desna na lijevo

1. Postavite jasne početne i krajnje točke procesa.
2. Imenujte kupce koji ovise o rezultatu.
3. Opišite rezultate koje dobivaju.
4. Sažmite proces u 4 do 7 aktivnosti visoke razine.
5. Odredite koji inputi su potrebni za te aktivnosti.
6. Povežite svaki unos s dobavljačem koji ga stavlja na raspolaganje.

---

<!-- skip -->
<!-- _class: table -->

# Kontrolni popis — primjer jednog povezanog retka

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
| Prodaja | Odobren zahtjev | Provjerite narudžbu → registrirajte → potvrdite | Potvrda narudžbe | Podnositelj zahtjeva |

- Čitajte red kao jedan lanac: dobavljač daje ulaz, proces ga pretvara u izlaz za kupca.
- Dodajte novi red samo ako se lanac značajno razlikuje.
- Provjerite s onima koji su uključeni kako biste bili sigurni da nijedan važan dobavljač, input, output ili kupac ne nedostaje.

---

<!-- _class: matrix -->
<!-- ocideck_template: sipoc -->

# SIPOC

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |

---

<!-- _class: table table-editable -->

# SIPOC ili detaljan dijagram toka?

| Karakteristično | SIPOC | Detaljan dijagram toka |
| --- | --- | --- |
| Svrha | Definirajte opseg i odnose | Dokumentirajte rad i odluke |
| Detalj | 4 do 7 aktivnosti visoke razine | Može sadržavati desetke koraka |
| Fokus | Dobavljači, ulazi, izlazi i kupci | Redoslijed, predaje i odluke |
| Koristiti | Početak napora za poboljšanje | Izvođenje i analiza grešaka |
