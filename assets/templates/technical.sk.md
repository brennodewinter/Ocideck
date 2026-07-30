---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Technický vysvetľovač
language: sk
---

<!-- _class: title -->

# Technický vysvetľovač

---

# Kontext a cieľ

- Na čo slúži tento komponent:…
- Pre koho je toto vysvetlenie:…
- Čo pochopíte na konci:…

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

# Komponenty a zodpovednosti

| Komponent | Zodpovednosť | Vlastník |
| --- | --- | --- |
| Klient | Prezentácia a vstup | Tím A |
| API | Validácia a smerovanie | Tím B |
| servis | Obchodná logika | Tím B |
| Databáza | Skladovanie | Tím C |

---

# Dátový tok alebo procesný tok
<!-- ocideck_list_style: numbered -->

1. The user makes a request
2. The API validates and routes it
3. The service processes and stores it
4. The result goes back to the user

---

<!-- _class: code -->

# Príklad kódu

```dart
/// Replace this example with the code you want to explain.
Future<Result> handleRequest(Request request) async {
  final input = validate(request);
  final result = await service.process(input);
  return result;
}
```

---

# Riziká a kompromisy

- Zvolené riešenie: … — pretože: …
- Zamietnutá alternatíva: … — pretože: …
- Známe riziko:…

---

# Kontrolný zoznam implementácie
<!-- ocideck_list_style: checklist -->

- [ ] Dizajn prediskutovaný s tímom
- [ ] Napísané testy
- [ ] Dokumentácia bola aktualizovaná
- [ ] Nastavenie monitorovania
