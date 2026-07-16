// GEGENEREERD noch handwerk-vrij: de proza hieronder is vertaald, de rest is
// vastgezet. Zie PENTEST_MIAUW §12.1/§12.3 en
// test/finding_template_languages_test.dart.
//
// Wat NIET vertaald mag worden, en waarom:
//  - de `## …`-koppen zijn parse-ankers van FindingSpec; vertaal je ze, dan
//    komt de sectie leeg terug bij het invoegen;
//  - `cwe:` is een MITRE-citaat en `severity:` het door FIRST gepubliceerde
//    bandlabel dat een bevinding zélf ook opslaat;
//  - `cvss_vector`/`cvss_version` zijn tokens, `references` zijn URL's.
//
// Vertaald is wat van ons is: de titel (die de kop van de bevinding wordt) en
// de vier prozasecties — een skelet dat de tester per opdracht aanscherpt.

/// De meegeleverde finding-sjablonen in het Spaans (es).
const Map<String, String> findingTemplatesEs = {
  'sql-injection': '''
---
title: Inyección SQL
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

La entrada del usuario se incorpora a una consulta SQL sin una parametrización
adecuada, lo que permite a un atacante alterar la lógica de la consulta.

## Confirmation (reproduction)

Envíe un valor manipulado en el parámetro afectado y observe que la aplicación
devuelve datos fuera del conjunto de resultados previsto.

## Possible impact

Un atacante puede leer, modificar o eliminar datos de la base de datos y, según
su configuración, lograr un acceso mayor al host.

## Recommendation

Utilice consultas parametrizadas (sentencias preparadas) en todos los accesos a
la base de datos y valide la entrada con una lista de permitidos. Emplee cuentas
de base de datos con privilegios mínimos.
''',
  'reflected-xss': '''
---
title: Cross-site scripting (XSS) reflejado
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

La entrada del usuario se refleja en la respuesta sin una codificación de salida
adecuada, por lo que un atacante puede inyectar secuencias de comandos que se
ejecutan en el navegador de la víctima.

## Confirmation (reproduction)

Introduzca una carga útil en el parámetro afectado y observe cómo se ejecuta en
la página renderizada.

## Possible impact

Secuestro de sesión, robo de credenciales y acciones realizadas en nombre de la
víctima dentro de la aplicación.

## Recommendation

Codificación de salida según el contexto de todos los datos controlados por el
usuario, una Content Security Policy estricta y el escapado automático del
framework.
''',
  'weak-password-policy': '''
---
title: Política de contraseñas débil
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

La aplicación acepta contraseñas débiles (cortas, comunes o sin requisitos de
complejidad), lo que facilita adivinar las cuentas.

## Confirmation (reproduction)

Registre o cambie una contraseña por un valor corto y común y observe que se
acepta.

## Possible impact

Mayor probabilidad de apropiación de cuentas mediante ataques de fuerza bruta o
de relleno de credenciales.

## Recommendation

Exija una longitud mínima, contraste con listas de contraseñas filtradas y admita
la autenticación multifactor.
''',
};
