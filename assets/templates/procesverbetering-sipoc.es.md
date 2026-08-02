---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Resumen del proceso SIPOC
language: es
---

<!-- _class: title -->

# Descripción general del proceso SIPOC
## Proveedor · Entrada · Proceso · Salida · Cliente

---

<!-- skip -->

# Así es como se trabaja con esta plantilla

- Utilice SIPOC para comprender el alcance y las dependencias de un proceso, no para registrar cada acción.
- Utilice la ayuda y la fila de ejemplo como lista de verificación; ingrese sus respuestas en **Límites del proceso** y en la matriz vacía **SIPOC**.
- Preferiblemente trabaje desde el cliente hasta el proveedor, con sustantivos para entrada y salida y verbos para pasos del proceso.
- Solo las diapositivas etiquetadas como **Omitidas** quedarán fuera de la presentación y exportación. Active o desactive **Omitir** para obtener explicaciones que su audiencia pueda necesitar o no.

---

# ¿Qué mapea SIPOC?

- **Proveedor:** proporciona la información o recursos que el proceso necesita.
- **Input:** datos, materiales u otras condiciones requeridas por el proceso.
- **Proceso:** 4 a 7 actividades de alto nivel que transforman el input.
- **Salida:** el producto, servicio o información que produce el proceso.
- **Cliente:** el destinatario interno o externo del resultado.

---

<!-- _class: table table-editable -->

# Establecer los límites del proceso

| Límite | Valor |
| --- | --- |
| Nombre del proceso |  |
| Punto de inicio |  |
| Punto final |  |

---

<!-- skip -->

# Lista de verificación: ¿Cuándo están los límites lo suficientemente claros?

- **Proceso:** asígnale un nombre reconocible con verbo y sujeto, por ejemplo “Registrar orden”.
- **Punto de partida:** Nombre un evento observable, por ejemplo "Solicitud recibida".
- **Punto final:** mencione un resultado demostrable, por ejemplo "Confirmación de pedido enviada".
- Elija límites en torno a los cuales el equipo pueda llegar a acuerdos significativos.
- Mover excepciones y procesos adyacentes fuera de la matriz; escríbalos por separado.

---

<!-- skip -->

# Lista de verificación: completa de derecha a izquierda

1. Establezca puntos claros de inicio y finalización del proceso.
2. Nombra los clientes que dependen del resultado.
3. Describa los resultados que reciben.
4. Resumir el proceso en 4 a 7 actividades de alto nivel.
5. Determine qué insumos necesitan esas actividades.
6. Vincular cada insumo al proveedor que lo pone a disposición.

---

<!-- skip -->
<!-- _class: table -->

# Lista de verificación: ejemplo de una fila conectada

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
| Venta | Solicitud aprobada | Consultar pedido → registrarse → confirmar | Confirmación de pedido | Solicitante |

- Lea la fila como una cadena: el proveedor proporciona insumos, el proceso los convierte en resultados para el cliente.
- Solo agregue una nueva fila si la cadena es significativamente diferente.
- Consulte con los involucrados para asegurarse de que no falte ningún proveedor, insumo, producto o cliente importante.

---

<!-- _class: matrix -->
<!-- ocideck_template: sipoc -->

# SIPOC

| Supplier | Input | Process | Output | Customer |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |
|  |  |  |  |  |

---

<!-- _class: table table-editable -->

# ¿SIPOC o un diagrama de flujo detallado?

| Característica | SIPOC | Diagrama de flujo detallado |
| --- | --- | --- |
| Objetivo | Definir alcance y relaciones. | Documentar el trabajo y las decisiones. |
| Detalle | 4 a 7 actividades de alto nivel | Puede contener docenas de pasos. |
| Enfocar | Proveedores, insumos, productos y clientes. | Secuencia, traspasos y puntos de decisión. |
| Usar | Inicio de un esfuerzo de mejora | Ejecución y análisis de fallos. |
