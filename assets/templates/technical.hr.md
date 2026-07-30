---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Tehnički objašnjavač
language: hr
---

<!-- _class: title -->

# Tehnički objašnjavač

---

# Kontekst i cilj

- Čemu služi ova komponenta: …
- Za koga je ovo objašnjenje: …
- Što ćete shvatiti na kraju: …

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

# Komponente i odgovornosti

| komponenta | Odgovornost | Vlasnik |
| --- | --- | --- |
| Klijent | Prezentacija i unos | Tim A |
| API | Validacija i usmjeravanje | Tim B |
| Usluga | Poslovna logika | Tim B |
| Baza podataka | Skladištenje | Tim C |

---

# Tijek podataka ili tijek procesa
<!-- ocideck_list_style: numbered -->

1. The user makes a request
2. The API validates and routes it
3. The service processes and stores it
4. The result goes back to the user

---

<!-- _class: code -->

# Primjer koda

```dart
/// Replace this example with the code you want to explain.
Future<Result> handleRequest(Request request) async {
  final input = validate(request);
  final result = await service.process(input);
  return result;
}
```

---

# Rizici i kompromisi

- Izabrano rješenje: … — jer: …
- Odbijena alternativa: … — jer: …
- Poznati rizik: …

---

# Kontrolni popis za provedbu
<!-- ocideck_list_style: checklist -->

- [ ] O dizajnu razgovarano s timom
- [ ] Testovi pismeni
- [ ] Dokumentacija ažurirana
- [ ] Postavljen nadzor
