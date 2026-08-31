---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: "Îmbunătățirea procesului: proiect 8D"
language: ro
ocideck_improvement_framework: 8d
---

<!-- _class: title -->

# Îmbunătățirea procesului: proiect 8D

---

<!-- skip -->

# Acesta este modul în care lucrați cu acest șablon

- Utilizați 8D pentru o problemă gravă sau recurentă și alegeți un rezultat cheie măsurabil (**Y-01**).
- Folosiți întrebările de pe fiecare diapozitiv ghid ca o listă de verificare; apoi adăugați diapozitive regulate pentru răspunsurile dvs.
- Înlocuiți explicația din charter și arborele CTQ cu informațiile despre proiect, completați SIPOC și separați limitarea temporară de corecția permanentă.
- Diapozitivele de ajutor nu sunt prezentate sau exportate. Dacă doriți să afișați unul, dezactivați **Omiteți** pentru acel diapozitiv.

---

<!-- _class: section -->

# D0: Pregătește-te

---

<!-- skip -->

# Lista de verificare — Ce înregistrați la D0?

- Care este primul semnal de fapt și cât de grav sau urgent este?
- Ce client, siguranță, livrare sau operațiuni comerciale pot fi afectate?
- Este 8D adecvat având în vedere complexitatea, repetarea și disciplinele necesare?
- Ce date, mostre și urme trebuie securizate imediat?
- Ce acțiune imediată este necesară înainte ca echipa să fie completă?

---

<!-- _class: canvas -->
<!-- ocideck_template: charter -->

# Carta de proiect

## Problemă

Rezumați primul semnal fără a cita o cauză nedovedită.

## Scop

Înregistrați rezultatul Y-01 dorit și data de recuperare necesară.

## Domeniul de aplicare

Definiți produsul, procesul, locația, perioada și cazurile excluse.

## Echipă

Numele proprietarului și domeniile de expertiză necesare; calculează numele la D1.

## Cronologie

Stabiliți termene limită pentru izolare, analiza cauzei principale, corecție și închidere.

## Criterii de succes
Când este protejat clientul, cauza eliminată și reapariția prevenită?

---

<!-- _class: tree -->
<!-- ocideck_template: ctq-tree -->
<!-- ocideck_layout: tree -->

# Cerințe măsurabile ale clienților (arborele CTQ)

- Ce rezultat trebuie restabilit pentru client? — **Y-01**
  - Care cerință sau limită nu este îndeplinită?
  - Ce condiție suplimentară ar trebui păstrată?

---

<!-- skip -->

# Lista de verificare — Cum completați SIPOC?

- Definiți procesul în care apare sau scapă problema.
- Începeți cu clientul afectat și producția anormală.
- Rezumați procesul în 4 până la 7 pași principali; nu adăugați încă cauze.
- Înregistrați intrările și furnizorii pentru a dezvălui posibile surse și puncte de transfer.
- Mai târziu, utilizați dovezile din D4 pentru a confirma cauzele.

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

# D1: Construiește echipa

---

<!-- skip -->

# Lista de verificare — Ce înregistrați la D1?

- Cine are cunoștințe despre proces, cunoștințe despre produs, date, autoritate de luare a deciziilor și contact cu clienții?
- Cine deține rezultatul 8D și cine conduce abordarea de zi cu zi?
- Ce roluri și responsabilități are fiecare membru al echipei?
- De ce capacitate și autoritate are nevoie echipa?
- Cât de des se întâlnește echipa și unde sunt înregistrate deciziile?

---

<!-- _class: section -->

# D2: Descrieți problema

---

<!-- skip -->

# Lista de verificare — Ce înregistrați la D2?

- Ce este în neregulă, unde, când, cât de des și în ce măsură?
- Cu cine sau cu ce produse apare - și unde nu apare?
- Care este valoarea curentă Y-01 în comparație cu cerințele sau cu performanța normală?
- Ce fotografii, măsurători, exemple și date sursă susțin descrierea?
- Ce presupuneri de cauză omiteți în mod conștient din propoziția cu probleme?

---

<!-- _class: section -->

# D3: Implementarea acțiunilor de izolare

---

<!-- skip -->

# Lista de verificare — Ce înregistrați la D3?

- Ce acțiune temporară protejează imediat clientul sau procesul împotriva efectului?
- Unde se aplică promoția, de când și cine o va implementa?
- Cum s-a verificat dacă sistemul de izolație funcționează efectiv?
- Ce riscuri, costuri și limitări presupune măsura temporară?
- Când și în ce condiții se va încheia restricția?

---

<!-- _class: section -->

# D4: Identificați și verificați cauzele fundamentale

---

<!-- skip -->

# Lista de verificare — Ce înregistrați la D4?

- Ce cauză explică de ce a apărut problema?
- Ce cauză de evadare explică de ce nu a fost descoperită mai devreme?
- Ce dovezi fac fiecare cauză reproductibilă sau testabilă?
- Ce suspiciuni au fost investigate și respinse?
- Cum afectează cauzele confirmate Y-01?

---

<!-- _class: section -->

# D5: Alegeți și verificați acțiunile corective

---

<!-- skip -->

# Lista de verificare — Ce înregistrați la D5?

- Care acțiune finală elimină cauza rădăcină sau de evacuare confirmată?
- Ce alternative au fost comparate pentru efect, risc și fezabilitate?
- Cum a fost testată acțiunea aleasă înainte de implementarea pe scară largă?
- Care a fost efectul măsurat asupra Y-01 și ce efecte secundare au apărut?
- Cine aprobă corectarea aleasă?

---

<!-- _class: section -->

# D6: Implementarea și validarea acțiunilor corective

---

<!-- skip -->

# Lista de verificare — Ce înregistrați la D6?

- Ce acțiuni au fost introduse definitiv unde, când și de către cine?
- Ce proceduri, sisteme, instruire și controale au fost adaptate?
- Cum și când va fi eliminată treptat restricția temporară?
- Care rezultate demonstrează că Y-01 îndeplinește în mod durabil cerința?
- Ce abateri sau puncte deschise mai trebuie rezolvate?

---

<!-- _class: section -->

# D7: Preveniți recurența

---

<!-- skip -->

# Lista de verificare — Ce înregistrați la D7?

- Unde altundeva ar putea apărea aceeași cauză sau cale de evacuare?
- Ce standarde, reguli de proiectare, controale sau lecții trebuie adaptate mai larg?
- Cine realizează aceste acțiuni preventive și când?
- Cum verifici dacă schimbarea funcționează și în afara acestui caz?
- Ce cunoștințe sunt împărtășite cu alte echipe sau furnizori?

---

<!-- _class: section -->

# D8: Recunoașteți echipa

---

<!-- skip -->

# Lista de verificare — Ce înregistrați la D8?

- Ce dovezi arată că problema, cauza, corectarea și prevenirea au fost finalizate?
- Clientul sau proprietarul procesului a acceptat rezultatul?
- Care contribuție și colaborare merită o recunoaștere explicită?
- Ce lecții va lua echipa cu ei la următoarea problemă?
- Cine va închide formal dosarul și unde pot fi găsite probele?
