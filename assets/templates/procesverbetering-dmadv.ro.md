---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: "Îmbunătățirea procesului: proiect DMADV"
language: ro
ocideck_improvement_framework: dmadv
---

<!-- _class: title -->

# Îmbunătățirea procesului: proiect DMADV

---

<!-- skip -->

# Acesta este modul în care lucrați cu acest șablon

- Utilizați DMADV pentru un proces nou sau reproiectat fundamental și alegeți un rezultat măsurabil pentru client (**Y-01**).
- Folosiți întrebările de pe fiecare diapozitiv ghid ca o listă de verificare; apoi adăugați diapozitive regulate pentru răspunsurile dvs.
- Înlocuiți explicația din charter și arborele CTQ cu informațiile despre proiect, completați SIPOC și faceți cerințele testabile înainte de a proiecta.
- Diapozitivele de ajutor nu sunt prezentate sau exportate. Dacă doriți să afișați unul, dezactivați **Omiteți** pentru acel diapozitiv.

---

<!-- _class: section -->

# Defini

---

<!-- skip -->

# Lista de verificare — Ce înregistrați când definiți?

- Care client sau utilizator are ce nevoie nesatisfăcută?
- De ce este necesar un nou design și de ce nu este suficientă îmbunătățirea procesului existent?
- Ce rezultat ar trebui să ofere proiectarea (**Y-01**) și în ce domeniu?
- Cine decide cerințele, alegerile de design și lansarea?
- Ce planificare, condiții preliminare și criterii de succes se aplică?

---

<!-- _class: canvas -->
<!-- ocideck_template: charter -->

# Carta de proiect

## Problemă sau oportunitate

Descrieți nevoia nesatisfăcută, grupul țintă și motivul demonstrabil.

## Scop

Formulați rezultatul dorit într-un mod măsurabil și limitat în timp.

## Domeniul de aplicare

Observați punctul de pornire, punctul final, punctele de contact și ceea ce se încadrează în afara designului.

## Echipă

Numiți clientul, proprietarul designului, utilizatorii și experții necesari.

## Cronologie

Înregistrați reperele, porțile de decizie și implementarea intenționată.

## Criterii de succes
Când designul satisface în mod demonstrabil nevoile clienților?

---

<!-- _class: tree -->
<!-- ocideck_template: ctq-tree -->
<!-- ocideck_layout: tree -->

# Cerințe măsurabile ale clienților (arborele CTQ)

- De ce rezultat are nevoie clientul? — **Y-01**
  - Traduceți această nevoie în cerința măsurabilă 1
  - Traduceți această nevoie într-o cerință măsurabilă 2

---

<!-- skip -->

# Lista de verificare — Cum completați SIPOC?

- Începeți cu **Client**: cine folosește rezultatul noului proces?
- Apoi identificați **Ieșirea** necesare și 4 până la 7 pași de **Proces** pretenționați.
- Rețineți **Intrarea** necesară și **Furnizorul** care face fiecare intrare disponibilă.
- Păstrați o privire de ansamblu; detaliile de design vor urma mai târziu.
- Verificați dacă granițele selectate corespund charter și Y-01.

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

# Măsură

---

<!-- skip -->

# Lista de verificare — Ce înregistrați când măsurați?

- Ce nevoi ale clienților au fost traduse în cerințe și priorități măsurabile?
- Care sunt valoarea țintă, limita inferioară sau superioară, unitatea și metoda de măsurare a Y-01?
- Ce cazuri de utilizare, volume și excepții ar trebui să poată face față designului?
- Ce realizări sau alternative existente folosiți ca referință?
- Cum veți testa în mod obiectiv dacă fiecare cerință a fost îndeplinită?

---

<!-- _class: section -->

# Analiza

---

<!-- skip -->

# Lista de verificare — Ce înregistrați când analizați?

- Ce funcții trebuie să îndeplinească procesul pentru a îndeplini cerințele?
- Ce relații și compromisuri există între dorințele clienților, riscurile și caracteristicile de design?
- Ce ipoteze mai trebuie explorate sau testate?
- Ce moduri de eroare și dependențe sunt cele mai importante?
- Ce criterii minime de proiectare trebuie să îndeplinească fiecare soluție?

---

<!-- _class: section -->

# Proiecta

---

<!-- skip -->

# Lista de verificare — Ce înregistrați în Design?

- Ce variante de design au fost luate în considerare și pe ce criterii au fost comparate?
- Cum arată fluxul de proces ales, inclusiv rolurile, sistemele și transferurile?
- Cum previne sau controlează proiectarea modurile majore de defecțiune?
- Ce învață un prototip sau un test despre funcționare și ușurință în utilizare?
- Ce variantă merge la verificare, cu ce puncte deschise?

---

<!-- _class: section -->

# Verifica

---

<!-- skip -->

# Lista de verificare — Ce înregistrați când verificați?

- Care test demonstrează pentru fiecare cerință că proiectarea funcționează în condiții realiste?
- Ce rezultate au fost obținute și ce abateri rămân?
- Ce cred utilizatorii și proprietarii de procese despre funcționare și fezabilitate?
- Ce control, instruire și măsurare sunt necesare după punerea în funcțiune?
- Cine eliberează designul și pe baza căror dovezi?
