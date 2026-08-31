---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Technyske útlis
language: fy
---

<!-- _class: title -->

# Technyske útlis

---

# Kontekst en doel

- Waarfoar is dizze komponint foar: ...
- Foar wa is dizze útlis: ...
- Wat jo oan it ein sille begripe: ...

---

### Arsjitektueroersjoch

```mermaid
flowchart LR
  Client --> API
  API --> Service
  Service --> Database[(Database)]
```

---

<!-- _class: table -->

# Komponinten en ferantwurdlikheden

| Komponint | Ferantwurdlikens | Eigner |
| --- | --- | --- |
| Client | Presintaasje en ynfier | Team A |
| API | Validaasje en routing | Team B |
| Service | Business logika | Team B |
| Databank | Storage | Team C |

---

# Datastream of prosesstream
<!-- ocideck_list_style: numbered -->

1. De brûker docht in oanfraach
2. De API validearret en routearret
3. De tsjinst ferwurket en slaat op
4. It resultaat giet werom nei de brûker

---

<!-- _class: code -->

# Koade foarbyld

```dart
/// Replace this example with the code you want to explain.
Future<Result> handleRequest(Request request) async {
  final input = validate(request);
  final result = await service.process(input);
  return result;
}
```

---

# Risiko's en trade-offs

- Gekozen oplossing: … — omdat: …
- Ofwiisd alternatyf: … — omdat: …
- Bekend risiko: …

---

# Ymplemintaasje checklist
<!-- ocideck_list_style: checklist -->

- [ ] Untwerp besprutsen mei it team
- [ ] Tests skreaun
- [ ] Dokumintaasje bywurke
- [ ] Monitoring opset
