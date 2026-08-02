---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: SIPOC proceso apžvalga
language: lt
---

<!-- _class: title -->

# SIPOC proceso apžvalga
## Tiekėjas · Įvestis · Procesas · Išvestis · Klientas

---

<!-- skip -->

# Taip dirbate su šiuo šablonu

- Naudokite SIPOC norėdami suprasti vieno proceso apimtį ir priklausomybes, o ne įrašyti kiekvieną veiksmą.
- Naudokite žinyną ir pavyzdinę eilutę kaip kontrolinį sąrašą; įveskite savo atsakymus į **Proceso ribos** ir tuščią **SIPOC** matricą.
- Pageidautina dirbti nuo kliento iki tiekėjo, naudojant įvesties ir išvesties daiktavardžius bei proceso etapų veiksmažodžius.
- Tik skaidrės, pažymėtos **Praleisti**, nebus pateiktos ir eksportuotos. Įjunkite arba išjunkite parinktį **Praleisti**, jei norite paaiškinimų, kurių auditorijai gali prireikti arba neprireikti.

---

# Ką rodo SIPOC?

- **Tiekėjas:** teikia procesui reikalingą informaciją arba išteklius.
- **Įvestis:** duomenys, medžiagos ar kitos procesui reikalingos sąlygos.
- **Procesas:** 4–7 aukšto lygio veiklos, kurios pakeičia įvestį.
- **Išvestis:** produktas, paslauga arba informacija, kurią sukuria procesas.
- **Klientas:** vidinis arba išorinis išvesties gavėjas.

---

<!-- _class: table table-editable -->

# Nustatykite proceso ribas

| Riba | Vertė |
| --- | --- |
| Proceso pavadinimas |  |
| Pradžios taškas |  |
| Pabaigos taškas |  |

---

<!-- skip -->

# Kontrolinis sąrašas – kada ribos pakankamai aiškios?

- **Procesas:** suteikite jam atpažįstamą pavadinimą su veiksmažodžiu ir tema, pvz., „Registruoti užsakymą“.
- **Pradžios taškas:** Pavadinkite vieną stebimą įvykį, pvz., „Užklausa gauta“.
- **Pabaigos taškas:** nurodykite vieną įrodomą rezultatą, pvz., „Užsakymo patvirtinimas išsiųstas“.
- Pasirinkite ribas, per kurias komanda gali sudaryti prasmingus susitarimus.
- Perkelti išimtis ir gretimus procesus už matricos ribų; užsirašykite juos atskirai.

---

<!-- skip -->

# Kontrolinis sąrašas – užpildykite iš dešinės į kairę

1. Nustatykite aiškius proceso pradžios ir pabaigos taškus.
2. Įvardinkite klientus, kurie priklauso nuo rezultato.
3. Apibūdinkite jų gaunamus rezultatus.
4. Apibendrinkite procesą į 4–7 aukšto lygio veiklas.
5. Nustatykite, kokių įnašų reikia tai veiklai.
6. Kiekvieną įvestį susiekite su tiekėju, kuris ją pateikia.

---

<!-- skip -->
<!-- _class: table -->

# Kontrolinis sąrašas – vienos sujungtos eilutės pavyzdys

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
| Išpardavimas | Patvirtintas prašymas | Patikrinkite užsakymą → registruokitės → patvirtinkite | Užsakymo patvirtinimas | Pareiškėjas |

- Skaitykite eilutę kaip vieną grandinę: tiekėjas pateikia įvestį, o procesas paverčia jį išvestimi klientui.
- Naują eilutę pridėkite tik tuo atveju, jei grandinė labai skiriasi.
- Pasitarkite su susijusiais asmenimis, kad įsitikintumėte, jog netrūksta jokio svarbaus tiekėjo, įvesties, produkcijos ar kliento.

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

# SIPOC ar išsami schema?

| Būdingas | SIPOC | Išsami schema |
| --- | --- | --- |
| Tikslas | Apibrėžkite apimtį ir ryšius | Dokumentuoti darbą ir sprendimus |
| Detalė | Nuo 4 iki 7 aukšto lygio veiklos | Gali būti dešimtys žingsnių |
| Fokusas | Tiekėjai, įvestis, produkcija ir klientai | Seka, perdavimas ir sprendimo taškai |
| Naudokite | Tobulinimo pastangų pradžia | Vykdymas ir gedimų analizė |
