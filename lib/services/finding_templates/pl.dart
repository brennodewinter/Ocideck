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

/// De meegeleverde finding-sjablonen in het Pools (pl).
const Map<String, String> findingTemplatesPl = {
  'sql-injection': '''
---
title: Wstrzyknięcie SQL
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Dane wprowadzone przez użytkownika są włączane do zapytania SQL bez właściwej
parametryzacji, co pozwala atakującemu zmienić logikę zapytania.

## Confirmation (reproduction)

Prześlij spreparowaną wartość w danym parametrze i stwierdź, że aplikacja zwraca
dane spoza zamierzonego zbioru wyników.

## Possible impact

Atakujący może odczytywać, modyfikować lub usuwać dane w bazie, a w zależności od
konfiguracji bazy uzyskać szerszy dostęp do hosta.

## Recommendation

Stosuj zapytania parametryzowane (prepared statements) przy każdym dostępie do
bazy i waliduj dane wejściowe względem listy dozwolonych. Używaj kont bazy danych
o minimalnych uprawnieniach.
''',
  'reflected-xss': '''
---
title: Odbite cross-site scripting (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Dane wprowadzone przez użytkownika są odbijane w odpowiedzi bez właściwego
kodowania wyjścia, więc atakujący może wstrzyknąć skrypt uruchamiany w
przeglądarce ofiary.

## Confirmation (reproduction)

Podaj ładunek w danym parametrze i zaobserwuj jego wykonanie na wyrenderowanej
stronie.

## Possible impact

Przejęcie sesji, kradzież poświadczeń oraz działania wykonywane w imieniu ofiary
w aplikacji.

## Recommendation

Kodowanie wyjścia zależne od kontekstu dla wszystkich danych kontrolowanych przez
użytkownika, restrykcyjna Content Security Policy i automatyczne escapowanie we
frameworku.
''',
  'weak-password-policy': '''
---
title: Słaba polityka haseł
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Aplikacja akceptuje słabe hasła (krótkie, popularne lub bez wymogów złożoności),
przez co konta są łatwiejsze do odgadnięcia.

## Confirmation (reproduction)

Zarejestruj lub zmień hasło na krótką, popularną wartość i stwierdź, że zostaje
przyjęte.

## Possible impact

Zwiększone prawdopodobieństwo przejęcia konta w wyniku ataków siłowych lub
credential stuffing.

## Recommendation

Wymuś minimalną długość, weryfikuj względem list haseł z wycieków i obsługuj
uwierzytelnianie wieloskładnikowe.
''',
};
