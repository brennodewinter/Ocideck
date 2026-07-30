---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Explication technique
language: fr
---

<!-- _class: title -->

# Explication technique

---

# Contexte et objectif

- A quoi sert ce composant : …
- À qui s’adresse cette explication : …
- Ce que vous comprendrez à la fin : …

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

# Composants et responsabilités

| Composant | Responsabilité | Propriétaire |
| --- | --- | --- |
| Client | Présentation et contribution | Équipe A |
| API | Validation et routage | Équipe B |
| Service | Logique métier | Équipe B |
| Base de données | Stockage | Équipe C |

---

# Flux de données ou flux de processus
<!-- ocideck_list_style: numbered -->

1. The user makes a request
2. The API validates and routes it
3. The service processes and stores it
4. The result goes back to the user

---

<!-- _class: code -->

# Exemple de code

```dart
/// Replace this example with the code you want to explain.
Future<Result> handleRequest(Request request) async {
  final input = validate(request);
  final result = await service.process(input);
  return result;
}
```

---

# Risques et compromis

- Solution retenue : … — parce que : …
- Alternative rejetée: … — parce que: …
- Risque connu : …

---

# Liste de contrôle de mise en œuvre
<!-- ocideck_list_style: checklist -->

- [ ] Design discuté avec l'équipe
- [ ] Tests écrits
- [ ] Documentation mise à jour
- [ ] Mise en place d'une surveillance
