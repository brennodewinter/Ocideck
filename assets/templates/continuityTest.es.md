---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Continuidad de negocio / test de DR
language: es
---

<!-- _class: title -->

# Continuidad de negocio / test de DR

---

# Escenario de test

- Escenario: … (p. ej. caída de centro de datos, ransomware)
- Supuesto previo: …
- Tipo de test: simulación / parcial / completo

---

# Objetivos y criterios de éxito

- Objetivo del test: …
- Criterio de éxito 1: …
- Criterio de éxito 2: …

---

<!-- _class: table table-editable -->

# Procesos críticos

| Proceso | Prioridad | Depende de |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

<!-- _class: table table-editable -->

# Resumen RTO / RPO

| Proceso o sistema | RTO | RPO | ¿Cumplido? |
| --- | --- | --- | --- |
| … | … | … | Sí / no |
| … | … | … | … |

---

<!-- _class: timeline -->

# Cronología del test

- T+0 :: Inicio del test :: Escenario anunciado.
- T+… :: Conmutación iniciada
- T+… :: Recuperación verificada
- T+… :: Fin del test

---

<!-- _class: table table-editable -->

# Hallazgos

| Hallazgo | Gravedad | Componente |
| --- | --- | --- |
| … | … | … |
| … | … | … |

---

# Desviaciones y bloqueos

- Desviación del manual: …
- Bloqueo durante el test: …
- Solución alternativa usada: …

---

# Puntos de mejora
<!-- ocideck_list_style: checklist -->

- [ ] Actualizar manual en el punto: …
- [ ] Ajustar configuración técnica: …
- [ ] Programar formación o ejercicio: …

---

# Go / no-go capacidad de recuperación
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Procesos críticos recuperados dentro del RTO
- [ ] Pérdida de datos dentro del RPO
- [ ] Manual demostró ser utilizable
- [ ] Veredicto: capacidad de recuperación demostrada
