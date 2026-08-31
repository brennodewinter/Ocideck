---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Míniú teicniúil
language: ga
---

<!-- _class: title -->

# Míniú teicniúil

---

# Comhthéacs agus sprioc

- Cad atá leis an gcomhpháirt seo: …
- Cé dó a bhfuil an míniú seo: …
- Cad a thuigfidh tú faoin deireadh: …

---

### Forbhreathnú ar an ailtireacht

```mermaid
flowchart LR
  Client --> API
  API --> Service
  Service --> Database[(Database)]
```

---

<!-- _class: table -->

# Comhpháirteanna agus freagrachtaí

| Comhpháirt | Freagracht | Úinéir |
| --- | --- | --- |
| Cliant | Cur i láthair agus ionchur | Foireann A |
| API | Bailíochtú agus ródú | Foireann B |
| Seirbhís | Loighic gnó | Foireann B |
| Bunachar Sonraí | Stóráil | Foireann C |

---

# Sreabhadh sonraí nó sreabhadh próisis
<!-- ocideck_list_style: numbered -->

1. Déanann an t-úsáideoir iarratas
2. Bailíochtaíonn an API é agus ródaíonn sé é
3. Próiseálann an tseirbhís é agus stórálann sí é
4. Téann an toradh ar ais chuig an úsáideoir

---

<!-- _class: code -->

# Sampla cód

```dart
/// Cuir an cód is mian leat a mhíniú in ionad an tsampla seo.
Future<Result> handleRequest(Request request) async {
  final input = validate(request);
  final result = await service.process(input);
  return result;
}
```

---

# Rioscaí agus comhbhabhtáil

- Réiteach roghnaithe: … — mar gheall ar: …
- Rogha eile a diúltaíodh: … — mar gheall ar: …
- Riosca aitheanta: …

---

# Seicliosta forfheidhmithe
<!-- ocideck_list_style: checklist -->

- [ ] Dearadh pléite leis an bhfoireann
- [ ] Tástálacha scríofa
- [ ] Nuashonraíodh an doiciméadú
- [ ] Monatóireacht a dhéanamh ar bun
