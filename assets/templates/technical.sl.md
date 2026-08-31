---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Tehnična razlaga
language: sl
---

<!-- _class: title -->

# Tehnična razlaga

---

# Kontekst in cilj

- Čemu je ta komponenta namenjena: …
- Komu je ta razlaga namenjena: …
- Kaj boste razumeli na koncu: …

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

# Sestavine in odgovornosti

| Komponenta | Odgovornost | Lastnik |
| --- | --- | --- |
| Stranka | Predstavitev in vnos | Ekipa A |
| API | Validacija in usmerjanje | Ekipa B |
| Storitev | Poslovna logika | Ekipa B |
| Baza podatkov | Shranjevanje | Ekipa C |

---

# Tok podatkov ali tok procesa
<!-- ocideck_list_style: numbered -->

1. Uporabnik pošlje zahtevo
2. API jo preveri in usmeri
3. Storitev jo obdela in shrani
4. Rezultat se vrne uporabniku

---

<!-- _class: code -->

# Primer kode

```dart
/// Zamenjaj ta primer s kodo, ki jo želiš pojasniti.
Future<Result> handleRequest(Request request) async {
  final input = validate(request);
  final result = await service.process(input);
  return result;
}
```

---

# Tveganja in kompromisi

- Izbrana rešitev: … — ker: …
- Zavrnjena alternativa: … — ker: …
- Znano tveganje: …

---

# Kontrolni seznam za izvajanje
<!-- ocideck_list_style: checklist -->

- [ ] O oblikovanju smo razpravljali z ekipo
- [ ] Pisni testi
- [ ] Dokumentacija posodobljena
- [ ] Nastavljen nadzor
