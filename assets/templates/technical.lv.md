---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Tehniskais skaidrotājs
language: lv
---

<!-- _class: title -->

# Tehniskais skaidrotājs

---

# Konteksts un mērķis

- Kam šis komponents ir paredzēts:…
- Kam šis skaidrojums ir paredzēts:…
- Ko jūs sapratīsit beigās:…

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

# Sastāvdaļas un pienākumi

| Komponents | Atbildība | Īpašnieks |
| --- | --- | --- |
| Klients | Prezentācija un ievade | A komanda |
| API | Validācija un maršrutēšana | B komanda |
| Serviss | Biznesa loģika | B komanda |
| Datu bāze | Uzglabāšana | C komanda |

---

# Datu plūsma vai procesa plūsma
<!-- ocideck_list_style: numbered -->

1. The user makes a request
2. The API validates and routes it
3. The service processes and stores it
4. The result goes back to the user

---

<!-- _class: code -->

# Koda piemērs

```dart
/// Replace this example with the code you want to explain.
Future<Result> handleRequest(Request request) async {
  final input = validate(request);
  final result = await service.process(input);
  return result;
}
```

---

# Riski un kompromisi

- Izvēlētais risinājums: … — jo: …
- Noraidīta alternatīva: … — jo: …
- Zināmais risks:…

---

# Īstenošanas kontrolsaraksts
<!-- ocideck_list_style: checklist -->

- [ ] Dizains apspriests ar komandu
- [ ] Rakstīti testi
- [ ] Dokumentācija atjaunināta
- [ ] Uzraudzības iestatīšana
