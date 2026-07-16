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

/// De meegeleverde finding-sjablonen in het Oekraïens (uk).
const Map<String, String> findingTemplatesUk = {
  'sql-injection': '''
---
title: SQL-ін'єкція
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Введені користувачем дані включаються до SQL-запиту без належної параметризації,
що дає змогу зловмиснику змінити логіку запиту.

## Confirmation (reproduction)

Надішліть підготовлене значення в уражений параметр і переконайтеся, що застосунок
повертає дані поза межами передбаченого набору результатів.

## Possible impact

Зловмисник може читати, змінювати або видаляти дані в базі та, залежно від її
налаштувань, отримати подальший доступ до хоста.

## Recommendation

Використовуйте параметризовані запити (prepared statements) для всього доступу до
бази та перевіряйте введення за списком дозволених значень. Застосовуйте облікові
записи бази з мінімальними правами.
''',
  'reflected-xss': '''
---
title: Відображений cross-site scripting (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Введені користувачем дані відображаються у відповіді без належного кодування
виводу, тож зловмисник може впровадити скрипт, який виконується у браузері
жертви.

## Confirmation (reproduction)

Подайте корисне навантаження в уражений параметр і простежте його виконання на
відтвореній сторінці.

## Possible impact

Викрадення сесії, крадіжка облікових даних і дії, виконані від імені жертви в
застосунку.

## Recommendation

Кодування виводу з урахуванням контексту для всіх даних, керованих користувачем,
сувора Content Security Policy та автоматичне екранування у фреймворку.
''',
  'weak-password-policy': '''
---
title: Слабка політика паролів
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Застосунок приймає слабкі паролі (короткі, поширені або без вимог до складності),
через що облікові записи легше вгадати.

## Confirmation (reproduction)

Зареєструйте або змініть пароль на коротке, поширене значення і переконайтеся, що
воно приймається.

## Possible impact

Підвищена ймовірність захоплення облікового запису через атаки перебором або
credential stuffing.

## Recommendation

Вимагайте мінімальну довжину, перевіряйте за списками скомпрометованих паролів і
підтримуйте багатофакторну автентифікацію.
''',
};
