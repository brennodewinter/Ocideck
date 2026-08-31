---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Tehničko objašnjenje
language: hr
---

<!-- _class: title -->

# Tehničko objašnjenje

---

# Kontekst i cilj

- Čemu služi ova komponenta: …
- Za koga je ovo objašnjenje: …
- Što ćete shvatiti na kraju: …

---

### Pregled arhitekture

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

1. Korisnik šalje zahtjev
2. API ga potvrđuje i usmjerava
3. Usluga ga obrađuje i pohranjuje
4. Rezultat se vraća korisniku

---

<!-- _class: code -->

# Primjer koda

```dart
/// Zamijenite ovaj primjer kodom koji želite objasniti.
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
