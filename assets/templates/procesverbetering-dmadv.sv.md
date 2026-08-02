---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: "Processförbättring: DMADV-projekt"
language: sv
ocideck_improvement_framework: dmadv
---

<!-- _class: title -->

# Processförbättring: DMADV-projekt

---

<!-- skip -->

# Så här arbetar du med den här mallen

- Använd DMADV för en ny eller fundamentalt omdesignad process och välj ett mätbart kundresultat (**Y-01**).
- Använd frågorna på varje guidebild som en checklista; lägg sedan till vanliga bilder för dina svar.
- Ersätt förklaringen i stadgan och CTQ-trädet med din projektinformation, fyll i SIPOC och gör kraven testbara innan du designar.
- Hjälpbilder presenteras eller exporteras inte. Om du vill visa en, stäng av **Hoppa över** för den bilden.

---

<!-- _class: section -->

# Definiera

---

<!-- skip -->

# Checklista — Vad registrerar du när du definierar?

- Vilken kund eller användare har vilket ouppfyllt behov?
- Varför är en ny design nödvändig och varför är det inte tillräckligt att förbättra den befintliga processen?
- Vilket resultat ska designen ge (**Y-01**) och inom vilken ram?
- Vem beslutar om krav, designval och release?
- Vilken planering, förutsättningar och framgångskriterier gäller?

---

<!-- _class: canvas -->
<!-- ocideck_template: charter -->

# Projektcharter

## Problem eller möjlighet

Beskriv det otillfredsställda behovet, målgrupp och påvisbar orsak.

## Mål

Formulera det önskade resultatet på ett mätbart och tidsbestämt sätt.

## Omfattning

Notera startpunkt, slutpunkt, kontaktpunkter och vad som faller utanför designen.

## Team

Namnge klient, designägare, användare och erforderliga experter.

## Tidslinje

Spela in milstolpar, beslutsportar och avsedd implementering.

## Framgångskriterier
När möter designen bevisligen kundernas behov?

---

<!-- _class: tree -->
<!-- ocideck_template: ctq-tree -->
<!-- ocideck_layout: tree -->

# Mätbara kundkrav (CTQ-träd)

- Vilket resultat behöver kunden? — **Y-01**
  - Översätt det behovet till mätbart krav 1
  - Översätt det behovet till mätbart krav 2

---

<!-- skip -->

# Checklista — Hur slutför du SIPOC?

- Börja med **Kunden**: vem använder det nya processresultatet?
- Identifiera sedan de nödvändiga **Utdata** och 4 till 7 avsedda **Process**-steg.
- Notera den nödvändiga **Input** och **Leverantören** som gör varje ingång tillgänglig.
- Håll en allmän överblick; designdetaljer kommer senare.
- Kontrollera om de valda gränserna motsvarar charter och Y-01.

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

# Mäta

---

<!-- skip -->

# Checklista — Vad registrerar du när du mäter?

- Vilka kundbehov har omsatts till mätbara krav och prioriteringar?
- Vad är målvärde, nedre eller övre gräns, enhet och mätmetod för Y-01?
- Vilka användningsfall, volymer och undantag ska designen kunna hantera?
- Vilka befintliga prestationer eller alternativ använder du som referens?
- Hur kommer du objektivt att testa om varje krav har uppfyllts?

---

<!-- _class: section -->

# Analysera

---

<!-- skip -->

# Checklista — Vad registrerar du när du analyserar?

- Vilka funktioner måste processen fylla för att uppfylla kraven?
- Vilka relationer och avvägningar finns mellan kundönskemål, risker och designegenskaper?
- Vilka antaganden behöver fortfarande utforskas eller testas?
- Vilka fellägen och beroenden är viktigast?
- Vilka minimikrav för design måste varje lösning uppfylla?

---

<!-- _class: section -->

# Design

---

<!-- skip -->

# Checklista — Vad spelar du in i Design?

- Vilka designvarianter övervägdes och på vilka kriterier jämfördes de?
- Hur ser det valda processflödet ut, inklusive roller, system och överföringar?
- Hur förhindrar eller kontrollerar designen de stora fellägena?
- Vad lär en prototyp eller test om drift och användarvänlighet?
- Vilken variant går till verifiering, med vilka öppna poäng?

---

<!-- _class: section -->

# Kontrollera

---

<!-- skip -->

# Checklista — Vad registrerar du när du verifierar?

- Vilket test bevisar för varje krav att designen fungerar under realistiska förhållanden?
- Vilka resultat har uppnåtts och vilka avvikelser kvarstår?
- Vad tycker användare och processägare om drift och genomförbarhet?
- Vilken kontroll, instruktion och mätning krävs efter idrifttagning?
- Vem släpper designen och utifrån vilka bevis?
