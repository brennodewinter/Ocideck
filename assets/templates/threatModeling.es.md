---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Sesión de modelado de amenazas
language: es
---

<!-- _class: title -->

# Sesión de modelado de amenazas
## Sistema · Fecha · Facilitador · Participantes

---

# Alcance y objetivo

- ¿Qué sistema o componente estamos modelando hoy?
- Qué está explícitamente fuera del alcance: …
- Supuestos con los que trabajamos: …
- Resultado: amenazas ponderadas con mitigaciones y un responsable

---

<!-- _class: table table-editable -->

# Mapeo del sistema

| Elemento | Tipo | Notas |
| --- | --- | --- |
| … | Componente | … |
| … | Flujo de datos | … |
| … | Parte externa | … |

---

# Fronteras de confianza

- ¿Dónde cruzan los datos de confianza a no confiable?
- ¿Qué fronteras vemos: red, proceso, usuario, cadena de suministro?
- ¿Dónde ocurren autenticación y validación de entrada?
- Dibuja cada frontera en el esquema del sistema: …

---

<!-- _class: table -->

# Referencia STRIDE

| Categoría | Significado |
| --- | --- |
| Suplantación | Fingir ser otro usuario o servicio |
| Manipulación | Modificación no autorizada de datos o código |
| Repudio | Negar que una acción haya ocurrido |
| Divulgación de información | Información llega a quienes no pueden verla |
| Denegación de servicio | Hacer el sistema inutilizable o inalcanzable |
| Elevación de privilegios | Obtener más privilegios de los concedidos |

---

<!-- _class: table table-editable -->

# Recopilación de amenazas

| Amenaza | Categoría STRIDE | Componente | Riesgo |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Priorización: probabilidad × impacto

- Probabilidad: ¿qué tan probable es el abuso (baja, media, alta)?
- Impacto: ¿cuánto daño si ocurre?
- Riesgo = probabilidad × impacto; alto-alto va primero
- En duda: elige la estimación más alta y anota por qué

---

<!-- _class: table table-editable -->

# Mitigaciones y acciones

| Mitigación | Responsable | Estado |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# Lo que aceptamos conscientemente

- Qué amenazas no abordamos deliberadamente: …
- Por qué está justificado (probabilidad, coste, contexto): …
- Quién es responsable de esta decisión: Rol
- Cuándo lo revisamos: …

---

# Sesión completada
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Alcance y supuestos registrados
- [ ] Componentes, flujos de datos y partes externas mapeados
- [ ] Fronteras de confianza dibujadas
- [ ] Las seis categorías STRIDE recorridas
- [ ] Amenazas priorizadas por probabilidad × impacto
- [ ] Mitigaciones asignadas a un responsable
- [ ] Riesgos aceptados registrados y con responsable
