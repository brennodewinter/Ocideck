---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Technical explainer
language: en
---

<!-- _class: title -->

# Technical explainer

---

# Context and goal

- What this component is for: …
- Who this explanation is for: …
- What you'll understand by the end: …

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

# Components and responsibilities

| Component | Responsibility | Owner |
| --- | --- | --- |
| Client | Presentation and input | Team A |
| API | Validation and routing | Team B |
| Service | Business logic | Team B |
| Database | Storage | Team C |

---

# Data flow or process flow
<!-- ocideck_list_style: numbered -->

1. The user makes a request
2. The API validates and routes it
3. The service processes and stores it
4. The result goes back to the user

---

<!-- _class: code -->

# Code example

```dart
/// Replace this example with the code you want to explain.
Future<Result> handleRequest(Request request) async {
  final input = validate(request);
  final result = await service.process(input);
  return result;
}
```

---

# Risks and trade-offs

- Chosen solution: … — because: …
- Rejected alternative: … — because: …
- Known risk: …

---

# Implementation checklist
<!-- ocideck_list_style: checklist -->

- [ ] Design discussed with the team
- [ ] Tests written
- [ ] Documentation updated
- [ ] Monitoring set up
