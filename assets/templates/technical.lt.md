---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Techninis paaiškinėjas
language: lt
---

<!-- _class: title -->

# Techninis paaiškinėjas

---

# Kontekstas ir tikslas

- Kam skirtas šis komponentas:…
- Kam skirtas šis paaiškinimas:…
- Ką suprasite pabaigai:…

---

### Architecture overview

```mermaid
flowchart LR
  Client --> API
  API --> Service
  Service --> Database[(Database)]
```

---

<!-- _class: table -->

# Komponentai ir pareigos

| Komponentas | Atsakomybė | Savininkas |
| --- | --- | --- |
| Klientas | Pristatymas ir įvestis | A komanda |
| API | Patvirtinimas ir maršruto parinkimas | B komanda |
| Aptarnavimas | Verslo logika | B komanda |
| Duomenų bazė | Sandėliavimas | C komanda |

---

# Duomenų srautas arba proceso srautas
<!-- ocideck_list_style: numbered -->

1. The user makes a request
2. The API validates and routes it
3. The service processes and stores it
4. The result goes back to the user

---

<!-- _class: code -->

# Kodo pavyzdys

```dart
/// Replace this example with the code you want to explain.
Future<Result> handleRequest(Request request) async {
  final input = validate(request);
  final result = await service.process(input);
  return result;
}
```

---

# Rizika ir kompromisai

- Pasirinktas sprendimas: … – nes:…
- Atmesta alternatyva: … – nes: …
- Žinoma rizika:…

---

# Įgyvendinimo kontrolinis sąrašas
<!-- ocideck_list_style: checklist -->

- [ ] Dizainas aptartas su komanda
- [ ] Testai parašyti
- [ ] Dokumentacija atnaujinta
- [ ] Stebėjimo nustatymas
