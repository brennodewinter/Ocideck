---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Prezentare generală a procesului SIPOC
language: ro
---

<!-- _class: title -->

# Prezentare generală a procesului SIPOC
## Furnizor · Intrare · Proces · Ieșire · Client

---

<!-- skip -->

# Acesta este modul în care lucrați cu acest șablon

- Utilizați SIPOC pentru a înțelege scopul și dependențele unui proces, nu pentru a înregistra fiecare acțiune.
- Utilizați ajutorul și rândul exemplu ca o listă de verificare; introduceți răspunsurile dvs. pe **Granițele procesului** și în matricea **SIPOC** goală.
- Lucrați de preferință de la client la furnizor, cu substantive pentru intrare și ieșire și verbe pentru etapele procesului.
- Numai diapozitivele etichetate **Omis** vor fi lăsate în afara prezentării și exportului. Activați sau dezactivați **Omiteți** pentru explicații de care publicul dvs. poate sau nu avea nevoie.

---

# Ce reprezintă harta SIPOC?

- **Furnizor:** furnizează informațiile sau resursele necesare procesului.
- **Intrare:** date, materiale sau alte condiții cerute de proces.
- **Proces:** 4 până la 7 activități de nivel înalt care transformă intrarea.
- **Ieșire:** produsul, serviciul sau informațiile pe care le produce procesul.
- **Client:** destinatarul intern sau extern al rezultatului.

---

<!-- _class: table table-editable -->

# Stabiliți limitele procesului

| Hotar | Valoare |
| --- | --- |
| Numele procesului |  |
| Punctul de pornire |  |
| Punctul final |  |

---

<!-- skip -->

# Lista de verificare — Când sunt limitele suficient de clare?

- **Proces:** dați-i un nume de recunoscut cu verb și subiect, de exemplu „Înregistrați ordinea”.
- **Punctul de pornire:** Numiți un eveniment observabil, de exemplu „Solicitare primită”.
- **Punctul final:** menționați un rezultat demonstrabil, de exemplu „Confirmarea comenzii trimisă”.
- Alegeți limite în jurul cărora echipa poate face acorduri semnificative.
- Mutați excepțiile și procesele adiacente în afara matricei; notează-le separat.

---

<!-- skip -->

# Lista de verificare — Completează de la dreapta la stânga

1. Stabiliți puncte de început și de sfârșit clare pentru proces.
2. Numiți clienții care depind de rezultat.
3. Descrieți rezultatele pe care le primesc.
4. Rezumați procesul în 4 până la 7 activități de nivel înalt.
5. Determinați ce inputuri au nevoie de acele activități.
6. Conectați fiecare intrare la furnizorul care o pune la dispoziție.

---

<!-- skip -->
<!-- _class: table -->

# Lista de verificare — Exemplu de un rând conectat

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
| Vânzare | Cerere aprobată | Verificați comanda → înregistrați → confirmați | Confirmarea comenzii | Solicitant |

- Citiți rândul ca un singur lanț: furnizorul oferă input, procesul îl transformă în output pentru client.
- Adăugați un rând nou numai dacă lanțul este semnificativ diferit.
- Verificați cu cei implicați pentru a vă asigura că nu lipsește niciun furnizor, intrare, ieșire sau client important.

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

# SIPOC sau o diagramă detaliată?

| Caracteristică | SIPOC | Diagramă detaliată |
| --- | --- | --- |
| Scop | Definiți domeniul și relațiile | Documentați munca și deciziile |
| Detaliu | 4 până la 7 activități de nivel înalt | Poate conține zeci de pași |
| Concentrează-te | Furnizori, intrări, ieșiri și clienți | Secvență, transferuri și puncte de decizie |
| Utilizare | Începutul unui efort de îmbunătățire | Executie si analiza defectelor |
