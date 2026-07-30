---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Informe de pentest MIAUW
language: es
---

<!-- _class: title -->

# Informe de pentest MIAUW

---

<!-- _class: section -->

# 1. General

---

# Gestión del documento

- Entrega digital de este informe, con hash de verificación (SHA-256).
- Reportero y certificación requerida (OSCP/OSEP/OSCE/OSWE/eWPTX).
- Versión del informe y fecha de publicación.
- Confidencialidad y clasificación TLP.
- Lista de distribución: quién recibe este informe.

---

<!-- _class: sign-off -->

# Informe veraz


---

<!-- _class: section -->

# 2. Plan de abordaje

---

# Asignación y alcance

- Intake y motivo de la investigación.
- Objetivo y preguntas de investigación.
- Propiedad, jurisdicción y aprobación del alcance.
- Idioma del informe.
- Indemnización y condiciones legales.

---

<!-- _class: scope-matrix -->

# Alcance y estándares

| Objeto | Tipo | Estándar | Estado | Nota | C | I | A |
| --- | --- | --- | --- | --- | --- | --- | --- |
|  | Web | WSTG |  |  |  |  |  |

---

<!-- _class: section -->

# 3. Ejecución

---

# Actividades de ejecución

- Assume breach como punto de partida.
- Calificación con CVSS 4.0 (puntuación + vector string).
- Evidencia: hashes del material probatorio (SHA1/SHA-256).
- Validación de resultados de escaneo (sin confianza ciega en el escáner).
- Documentación de rutas de acceso utilizadas.

---

<!-- _class: section -->

# 4. Informe

---

<!-- _class: findings-summary -->

# Resumen ejecutivo

| Gravedad | Cantidad |
| --- | --- |
| Crítico | 0 |
| Alto | 0 |
| Medio | 0 |
| Bajo | 0 |
| Ninguno | 0 |
| Resuelto | 0 |

---

<!-- _class: timeline -->

# Cronología de la investigación

- Intake :: Kickoff :: Alcance y acuerdos establecidos.
- Test :: Ejecución :: Periodo de pruebas de la investigación.
- Informe :: Entrega :: Borrador e informe final.

---

<!-- _class: finding -->

# F-01 · Hallazgo de ejemplo

**Objeto de alcance:** `<scope-object>`

## Descripción

Describe aquí, de forma factual y técnica, cuál es el problema de seguridad.

## Confirmación (reproducción)

Describe, de forma reproducible (con evidencia), cómo se estableció el hallazgo.

## Posible impacto

Describe el posible impacto técnico y de negocio.

## Recomendación

Describe la mitigación concreta y alcanzable.

---

<!-- _class: checklist -->

# Checklist por estándar

| ID | Test | Estado | Hallazgo | Nota |
| --- | --- | --- | --- | --- |
|  |  |  | — |  |
|  |  |  | — |  |

---

# Anexos

- Glosario.
- Herramientas utilizadas.
- Documentos y archivos recibidos (con SHA1).
- Cuentas utilizadas.
- Resultados de escaneo.
- Material probatorio (con SHA1).
- Checklists por estándar.
- Objetos inalcanzables.

