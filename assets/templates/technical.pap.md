---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Splikashon tékniko
language: pap
---

<!-- _class: title -->

# Splikashon tékniko

---

# Konteksto i meta

- Pa kiko e komponente aki ta: …
- Pa ken e splikashon aki ta: …
- Loke bo lo komprondé na final: …

---

### Bista general di arkitektura

```mermaid
flowchart LR
  Client --> API
  API --> Service
  Service --> Database[(Database)]
```

---

<!-- _class: table -->

# Komponentenan i responsabilidatnan

| Komponente | Responsabilidat | Doño |
| --- | --- | --- |
| Kliente | Presentashon i entrada | Tim A |
| API | Validashon i enrutamentu | Tim B |
| Servisio | Lógika di negoshi | Tim B |
| Base di Dato | Almasenamentu | Tim C |

---

# Fluho di dato òf fluho di proseso
<!-- ocideck_list_style: numbered -->

1. E usuario ta hasi un petishon
2. E API ta validá i ruteá e petishon
3. E servisio ta prosesá i warda e petishon
4. E resultado ta bai bèk pa e usuario

---

<!-- _class: code -->

# Ehèmpel di kódigo

```dart
/// Remplasá e ehèmpel aki ku e kódigo ku bo ke splika.
Future<Result> handleRequest(Request request) async {
  final input = validate(request);
  final result = await service.process(input);
  return result;
}
```

---

# Riesgonan i kompromisonan

- Solushon skohé: … — pasobra: …
- Alternativa rechasá: … — pasobra: …
- Riesgo konosí: …

---

# Lista di kòntròl di implementashon
<!-- ocideck_list_style: checklist -->

- [ ] Diseño a wòrdu diskutí ku e tim
- [ ] Pruebanan skirbí
- [ ] Dokumentashon aktualisá
- [ ] Konfigurashon di monitoreo
