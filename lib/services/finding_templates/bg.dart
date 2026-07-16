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

/// De meegeleverde finding-sjablonen in het Bulgaars (bg).
const Map<String, String> findingTemplatesBg = {
  'sql-injection': '''
---
title: SQL инжекция
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Въведените от потребителя данни се включват в SQL заявка без подходяща
параметризация, което позволява на атакуващ да промени логиката на заявката.

## Confirmation (reproduction)

Изпратете подготвена стойност в засегнатия параметър и установете, че приложението
връща данни извън предвиденото множество резултати.

## Possible impact

Атакуващ може да чете, променя или изтрива данни в базата и в зависимост от
конфигурацията ѝ да получи по-нататъшен достъп до хоста.

## Recommendation

Използвайте параметризирани заявки (prepared statements) за всеки достъп до
базата и валидирайте входа спрямо списък с разрешени стойности. Използвайте
акаунти за база данни с минимални права.
''',
  'reflected-xss': '''
---
title: Отразен cross-site scripting (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Въведените от потребителя данни се отразяват в отговора без подходящо кодиране на
изхода, така че атакуващ може да инжектира скрипт, който се изпълнява в браузъра
на жертвата.

## Confirmation (reproduction)

Подайте полезен товар в засегнатия параметър и наблюдавайте изпълнението му в
изобразената страница.

## Possible impact

Отвличане на сесия, кражба на удостоверения и действия, извършени от името на
жертвата в приложението.

## Recommendation

Кодиране на изхода съобразно контекста за всички контролирани от потребителя
данни, строга Content Security Policy и автоматично екраниране от рамката.
''',
  'weak-password-policy': '''
---
title: Слаба политика за пароли
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Приложението приема слаби пароли (къси, често срещани или без изисквания за
сложност), което улеснява отгатването на акаунти.

## Confirmation (reproduction)

Регистрирайте или променете парола на къса, често срещана стойност и установете,
че тя се приема.

## Possible impact

Повишена вероятност за превземане на акаунт чрез атаки с груба сила или
credential stuffing.

## Recommendation

Наложете минимална дължина, проверявайте спрямо списъци с изтекли пароли и
поддържайте многофакторно удостоверяване.
''',
};
