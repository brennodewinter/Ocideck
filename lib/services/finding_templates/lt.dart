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

/// De meegeleverde finding-sjablonen in het Litouws (lt).
const Map<String, String> findingTemplatesLt = {
  'sql-injection': '''
---
title: SQL injekcija
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Naudotojo įvestis įtraukiama į SQL užklausą be tinkamo parametrizavimo, todėl
užpuolikas gali pakeisti užklausos logiką.

## Confirmation (reproduction)

Pateikite suklastotą reikšmę paveiktame parametre ir nustatykite, kad programa
grąžina duomenis už numatytos rezultatų aibės ribų.

## Possible impact

Užpuolikas gali skaityti, keisti ar trinti duomenų bazės duomenis ir, priklausomai
nuo jos konfigūracijos, gauti platesnę prieigą prie serverio.

## Recommendation

Visai prieigai prie duomenų bazės naudokite parametrizuotas užklausas (parengtus
sakinius) ir tikrinkite įvestį pagal leidžiamųjų sąrašą. Naudokite duomenų bazės
paskyras su minimaliomis teisėmis.
''',
  'reflected-xss': '''
---
title: Atspindėtas cross-site scripting (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Naudotojo įvestis atspindima atsake be tinkamo išvesties kodavimo, todėl užpuolikas
gali įterpti scenarijų, vykdomą aukos naršyklėje.

## Confirmation (reproduction)

Pateikite naudingąjį krūvį paveiktame parametre ir stebėkite jo vykdymą
atvaizduotame puslapyje.

## Possible impact

Seanso užgrobimas, prisijungimo duomenų vagystė ir veiksmai, atlikti aukos vardu
programoje.

## Recommendation

Kontekstą atitinkantis išvesties kodavimas visiems naudotojo valdomiems duomenims,
griežta Content Security Policy ir automatinis karkaso kaitaliojimas.
''',
  'weak-password-policy': '''
---
title: Silpna slaptažodžių politika
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Programa priima silpnus slaptažodžius (trumpus, dažnus arba be sudėtingumo
reikalavimų), todėl paskyras lengviau atspėti.

## Confirmation (reproduction)

Užregistruokite arba pakeiskite slaptažodį į trumpą, dažną reikšmę ir nustatykite,
kad ji priimama.

## Possible impact

Didesnė paskyros perėmimo tikimybė dėl brutalios jėgos arba credential stuffing
atakų.

## Recommendation

Reikalaukite mažiausio ilgio, tikrinkite pagal nutekėjusių slaptažodžių sąrašus ir
palaikykite kelių veiksnių tapatybės nustatymą.
''',
};
