---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Technical explicator
language: la
---

<!-- _class: title -->

# Technical explicator

---

# Contextus et finis

- Quae haec pars est pro: ...
- Quis haec explicatio est pro: ...
- Quid scies in fine: ...

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

# Components et officia

| Component | Cura | dominus |
| --- | --- | --- |
| Client | Praesentatio et initus | Team A |
| API | Sanatio et profectus | Team B |
| Service | Negotia logica | Team B |
| Database | Repono | Team C |

---

# Data fluxus seu processus influunt
<!-- ocideck_list_style: numbered -->

1. The user makes a request
2. The API validates and routes it
3. The service processes and stores it
4. The result goes back to the user

---

<!-- _class: code -->

# exemplum codicis

```dart
/// Replace this example with the code you want to explain.
Future<Result> handleRequest(Request request) async {
  final input = validate(request);
  final result = await service.process(input);
  return result;
}
```

---

# Pericula et commercia-peracti

- Solutio electa: ... - quia: ...
- Reprobavit alternative: ... - quia: ...
- Periculum notum: …

---

# Genus exsequendam
<!-- ocideck_list_style: checklist -->

- [ ] Consilium tractatum cum bigas
- [ ] Testis scriptum
- [ ] Documenta updated
- [ ] Cras extruxerat
