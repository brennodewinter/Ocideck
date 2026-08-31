---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: SIPOC-processöversikt
language: sv
---

<!-- _class: title -->

# SIPOC-processöversikt
## Leverantör · Input · Process · Output · Kund

---

<!-- skip -->

# Så här arbetar du med den här mallen

- Använd SIPOC för att förstå omfattningen och beroenden av en process, inte för att registrera varje åtgärd.
- Använd hjälpen och exempelraden som en checklista; skriv in dina svar på **Processgränser** och i den tomma **SIPOC**-matrisen.
- Arbeta helst från kund till leverantör, med substantiv för input och output och verb för processsteg.
- Endast bilder märkta **Hoppade över** kommer att utelämnas från presentation och export. Aktivera eller inaktivera **Hoppa över** för förklaringar som din publik kanske behöver eller inte behöver.

---

# Vad kartlägger SIPOC?

- **Leverantör:** tillhandahåller den information eller resurser som processen behöver.
- **Indata:** data, material eller andra villkor som krävs av processen.
- **Process:** 4 till 7 aktiviteter på hög nivå som omvandlar input.
- **Utdata:** den produkt, tjänst eller information som processen producerar.
- **Kund:** den interna eller externa mottagaren av utdata.

---

<!-- _class: table table-editable -->

# Sätt processgränserna

| Gräns | Värde |
| --- | --- |
| Processnamn |  |
| Startpunkt |  |
| Slutpunkt |  |

---

<!-- skip -->

# Checklista — När är gränserna tillräckligt tydliga?

- **Process:** ge det ett igenkännbart namn med verb och ämne, till exempel "Registrera beställning".
- **Utgångspunkt:** Nämn en observerbar händelse, till exempel "Begäran har tagits emot".
- **Slutpunkt:** nämn ett påvisbart resultat, till exempel "Orderbekräftelse har skickats".
- Välj gränser runt vilka teamet kan göra meningsfulla överenskommelser.
- Flytta undantag och angränsande processer utanför matrisen; skriv ner dem separat.

---

<!-- skip -->

# Checklista — Fyll i från höger till vänster

1. Ange tydliga start- och slutpunkter för processen.
2. Nämn de kunder som är beroende av resultatet.
3. Beskriv utdata de får.
4. Sammanfatta processen i 4 till 7 aktiviteter på hög nivå.
5. Bestäm vilka insatser dessa aktiviteter behöver.
6. Koppla varje ingång till leverantören som gör den tillgänglig.

---

<!-- skip -->
<!-- _class: table -->

# Checklista — Exempel på en ansluten rad

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
| Försäljning | Godkänd begäran | Kontrollera beställning → registrera → bekräfta | Orderbekräftelse | Sökande |

- Läs raden som en kedja: leverantören ger input, processen förvandlar det till output för kunden.
- Lägg bara till en ny rad om kedjan är väsentligt annorlunda.
- Kontrollera med de inblandade för att säkerställa att ingen viktig leverantör, input, output eller kund saknas.

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

# SIPOC eller ett detaljerat flödesschema?

| Karakteristisk | SIPOC | Detaljerat flödesschema |
| --- | --- | --- |
| Ändamål | Definiera omfattning och relationer | Dokumentarbete och beslut |
| Detalj | 4 till 7 aktiviteter på hög nivå | Kan innehålla dussintals steg |
| Fokus | Leverantörer, input, output och kunder | Sekvens, överlämningar och beslutspunkter |
| Använda | Start av ett förbättringsarbete | Utförande och felanalys |
