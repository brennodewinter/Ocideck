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

/// De meegeleverde finding-sjablonen in het Hongaars (hu).
const Map<String, String> findingTemplatesHu = {
  'sql-injection': '''
---
title: SQL-injektálás
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

A felhasználói bemenet megfelelő paraméterezés nélkül kerül be az SQL-lekérdezésbe,
így a támadó módosíthatja a lekérdezés logikáját.

## Confirmation (reproduction)

Küldjön preparált értéket az érintett paraméterben, és állapítsa meg, hogy az
alkalmazás a szándékolt eredményhalmazon kívüli adatokat ad vissza.

## Possible impact

A támadó olvashat, módosíthat vagy törölhet adatokat az adatbázisban, és az
adatbázis beállításaitól függően további hozzáférést szerezhet a kiszolgálóhoz.

## Recommendation

Használjon paraméterezett lekérdezéseket (prepared statement) minden
adatbázis-hozzáféréshez, és ellenőrizze a bemenetet engedélyezési lista alapján.
Alkalmazzon minimális jogosultságú adatbázis-fiókokat.
''',
  'reflected-xss': '''
---
title: Visszatükrözött cross-site scripting (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

A felhasználói bemenet megfelelő kimeneti kódolás nélkül tükröződik a válaszban,
így a támadó olyan szkriptet szúrhat be, amely az áldozat böngészőjében fut le.

## Confirmation (reproduction)

Adjon meg payloadot az érintett paraméterben, és figyelje meg a lefutását a
megjelenített oldalon.

## Possible impact

Munkamenet-eltérítés, hitelesítő adatok ellopása és az áldozat nevében végzett
műveletek az alkalmazáson belül.

## Recommendation

Kontextusfüggő kimeneti kódolás minden felhasználó által vezérelt adatra, szigorú
Content Security Policy és a keretrendszer automatikus escapelése.
''',
  'weak-password-policy': '''
---
title: Gyenge jelszóházirend
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Az alkalmazás gyenge jelszavakat fogad el (rövid, gyakori vagy összetettségi
követelmények nélküli), ezáltal a fiókok könnyebben kitalálhatók.

## Confirmation (reproduction)

Regisztráljon vagy módosítson jelszót rövid, gyakori értékre, és állapítsa meg,
hogy elfogadásra kerül.

## Possible impact

Nagyobb a fiókátvétel valószínűsége nyers erővel vagy credential stuffing
támadásokkal.

## Recommendation

Írjon elő minimális hosszt, ellenőrizzen kiszivárgott jelszavak listái ellen, és
támogassa a többtényezős hitelesítést.
''',
};
