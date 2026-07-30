---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Technischer Erklärer
language: de
---

<!-- _class: title -->

# Technischer Erklärer

---

# Kontext und Ziel

- Wozu dient diese Komponente: …
- Für wen ist diese Erklärung gedacht: …
- Was Sie am Ende verstehen werden: …

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

# Bestandteile und Verantwortlichkeiten

| Komponente | Verantwortung | Besitzer |
| --- | --- | --- |
| Kunde | Präsentation und Input | Team A |
| API | Validierung und Routing | Team B |
| Service | Geschäftslogik | Team B |
| Datenbank | Lagerung | Team C |

---

# Datenfluss oder Prozessfluss
<!-- ocideck_list_style: numbered -->

1. The user makes a request
2. The API validates and routes it
3. The service processes and stores it
4. The result goes back to the user

---

<!-- _class: code -->

# Codebeispiel

```dart
/// Replace this example with the code you want to explain.
Future<Result> handleRequest(Request request) async {
  final input = validate(request);
  final result = await service.process(input);
  return result;
}
```

---

# Risiken und Kompromisse

- Gewählte Lösung: … – weil: …
- Abgelehnte Alternative: … – weil: …
- Bekanntes Risiko: …

---

# Checkliste für die Umsetzung
<!-- ocideck_list_style: checklist -->

- [ ] Design mit dem Team besprochen
- [ ] Tests geschrieben
- [ ] Dokumentation aktualisiert
- [ ] Überwachung eingerichtet
