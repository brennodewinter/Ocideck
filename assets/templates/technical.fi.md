---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Tekninen selitys
language: fi
---

<!-- _class: title -->

# Tekninen selitys

---

# Konteksti ja tavoite

- Mihin tämä komponentti on tarkoitettu:…
- Kenelle tämä selitys on tarkoitettu:…
- Mitä ymmärrät lopussa:…

---

### Arkkitehtuurin yleiskuva

```mermaid
flowchart LR
  Client --> API
  API --> Service
  Service --> Database[(Database)]
```

---

<!-- _class: table -->

# Komponentit ja vastuut

| Komponentti | Vastuullisuus | Omistaja |
| --- | --- | --- |
| Asiakas | Esittely ja syöttö | Joukkue A |
| API | Validointi ja reititys | Joukkue B |
| Palvelu | Liiketoiminnan logiikkaa | Joukkue B |
| Tietokanta | Varastointi | Joukkue C |

---

# Tietovirta tai prosessivirta
<!-- ocideck_list_style: numbered -->

1. Käyttäjä tekee pyynnön
2. API vahvistaa ja reitittää sen
3. Palvelu käsittelee ja tallentaa sen
4. Tulos palaa käyttäjälle

---

<!-- _class: code -->

# Esimerkki koodista

```dart
/// Korvaa tämä esimerkki koodilla, jonka haluat selittää.
Future<Result> handleRequest(Request request) async {
  final input = validate(request);
  final result = await service.process(input);
  return result;
}
```

---

# Riskit ja kompromissit

- Valittu ratkaisu: … — koska: …
- Hylätty vaihtoehto: … – koska: …
- Tunnettu riski:…

---

# Toteutuksen tarkistuslista
<!-- ocideck_list_style: checklist -->

- [ ] Suunnittelusta keskusteltiin joukkueen kanssa
- [ ] Testit kirjoitettu
- [ ] Dokumentaatio päivitetty
- [ ] Valvonta asetettu
