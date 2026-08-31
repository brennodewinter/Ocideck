---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Technischi Erklärig
language: gsw
---

<!-- _class: title -->

# Technischi Erklärig

---

# Kontext und Ziel

- Wozu dient diese Komponente: …
- Für wen ist diese Erklärung gedacht: …
- Was Sie am Ende verstehen werden: …

---

### Architekturübersicht

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

1. De Benutzer stellt en Aafrag
2. D API validiert und leitet si wiiter
3. De Dienscht verarbeitet und speicheret si
4. S Resultat gaht zrugg zum Benutzer

---

<!-- _class: code -->

# Codebeispiel

```dart
/// Ersetz das Bispiel dur de Code, wo du erkläre wottsch.
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
