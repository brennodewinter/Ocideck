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

/// De meegeleverde finding-sjablonen in het Portugees (pt).
const Map<String, String> findingTemplatesPt = {
  'sql-injection': '''
---
title: Injeção de SQL
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Os dados introduzidos pelo utilizador são incorporados numa consulta SQL sem a
parametrização adequada, permitindo que um atacante altere a lógica da consulta.

## Confirmation (reproduction)

Submeta um valor manipulado no parâmetro afetado e verifique que a aplicação
devolve dados fora do conjunto de resultados previsto.

## Possible impact

Um atacante pode ler, alterar ou eliminar dados na base de dados e, consoante a
configuração desta, obter acesso adicional ao host.

## Recommendation

Utilize consultas parametrizadas (prepared statements) em todos os acessos à base
de dados e valide a entrada com uma lista de permitidos. Utilize contas de base de
dados com privilégios mínimos.
''',
  'reflected-xss': '''
---
title: Cross-site scripting (XSS) refletido
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Os dados introduzidos pelo utilizador são refletidos na resposta sem a
codificação de saída adequada, pelo que um atacante pode injetar script executado
no navegador da vítima.

## Confirmation (reproduction)

Forneça um payload no parâmetro afetado e observe a sua execução na página
renderizada.

## Possible impact

Sequestro de sessão, roubo de credenciais e ações realizadas em nome da vítima
dentro da aplicação.

## Recommendation

Codificação de saída sensível ao contexto de todos os dados controlados pelo
utilizador, uma Content Security Policy estrita e escape automático do framework.
''',
  'weak-password-policy': '''
---
title: Política de palavras-passe fraca
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

A aplicação aceita palavras-passe fracas (curtas, comuns ou sem requisitos de
complexidade), tornando as contas mais fáceis de adivinhar.

## Confirmation (reproduction)

Registe ou altere uma palavra-passe para um valor curto e comum e verifique que é
aceite.

## Possible impact

Maior probabilidade de apropriação de contas através de ataques de força bruta ou
de preenchimento de credenciais.

## Recommendation

Imponha um comprimento mínimo, verifique face a listas de palavras-passe expostas
e suporte a autenticação multifator.
''',
};
