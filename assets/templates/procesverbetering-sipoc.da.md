---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: SIPOC-procesoversigt
language: da
---

<!-- _class: title -->

# SIPOC-procesoversigt
## Leverandør · Input · Proces · Output · Kunde

---

<!-- skip -->

# Sådan arbejder du med denne skabelon

- Brug SIPOC til at forstå omfanget og afhængighederne af én proces, ikke til at registrere hver handling.
- Brug hjælpen og eksempelrækken som en tjekliste; indtast dine svar på **Procesgrænser** og i den tomme **SIPOC** matrix.
- Arbejd gerne fra kunde til leverandør, med navneord til input og output og verber til procestrin.
- Kun dias mærket **Sprang over** vil blive udeladt af præsentation og eksport. Slå **Spring over** til eller fra for at få forklaringer, som dit publikum måske eller måske ikke har brug for.

---

# Hvad kortlægger SIPOC?

- **Leverandør:** leverer de oplysninger eller ressourcer, som processen har brug for.
- **Input:** data, materialer eller andre forhold, der kræves af processen.
- **Proces:** 4 til 7 aktiviteter på højt niveau, der transformerer input.
- **Output:** produktet, tjenesten eller informationen, som processen producerer.
- **Kunde:** den interne eller eksterne modtager af output.

---

<!-- _class: table table-editable -->

# Sæt procesgrænserne

| Grænse | Værdi |
| --- | --- |
| Procesnavn |  |
| Startpunkt |  |
| Slutpunkt |  |

---

<!-- skip -->

# Tjekliste — Hvornår er grænserne klare nok?

- **Proces:** giv det et genkendeligt navn med verbum og emne, for eksempel "Registrer ordre".
- **Udgangspunkt:** Nævn én observerbar hændelse, f.eks. "Anmodning modtaget".
- **Endpunkt:** Nævn ét påviselig resultat, for eksempel "Ordrebekræftelse sendt".
- Vælg grænser, som teamet kan lave meningsfulde aftaler omkring.
- Flyt undtagelser og tilstødende processer uden for matrixen; skriv dem ned separat.

---

<!-- skip -->

# Tjekliste — Udfyldes fra højre mod venstre

1. Sæt klare start- og slutpunkter for processen.
2. Nævn de kunder, der er afhængige af resultatet.
3. Beskriv de output, de modtager.
4. Opsummer processen i 4 til 7 aktiviteter på højt niveau.
5. Bestem, hvilke input disse aktiviteter har brug for.
6. Link hvert input til leverandøren, der stiller det til rådighed.

---

<!-- skip -->
<!-- _class: table -->

# Tjekliste — Eksempel på én forbundet række

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
| Udsalg | Godkendt anmodning | Tjek ordre → tilmeld → bekræft | Ordrebekræftelse | Ansøger |

- Læs rækken som én kæde: Leverandøren giver input, processen gør det til output for kunden.
- Tilføj kun en ny række, hvis kæden er væsentlig anderledes.
- Tjek med de involverede for at sikre, at ingen vigtig leverandør, input, output eller kunde mangler.

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

# SIPOC eller et detaljeret flowchart?

| Karakteristisk | SIPOC | Detaljeret flowchart |
| --- | --- | --- |
| Formål | Definer omfang og relationer | Dokumentarbejde og beslutninger |
| Detalje | 4 til 7 aktiviteter på højt niveau | Kan indeholde snesevis af trin |
| Fokus | Leverandører, input, output og kunder | Rækkefølge, afleveringer og beslutningspunkter |
| Bruge | Start på en forbedringsindsats | Udførelse og fejlanalyse |
