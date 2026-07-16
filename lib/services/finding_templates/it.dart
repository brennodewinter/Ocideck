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

/// De meegeleverde finding-sjablonen in het Italiaans (it).
const Map<String, String> findingTemplatesIt = {
  'sql-injection': '''
---
title: SQL injection
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

L'input dell'utente viene inserito in una query SQL senza un'adeguata
parametrizzazione, consentendo a un attaccante di alterare la logica della query.

## Confirmation (reproduction)

Inviare un valore manipolato nel parametro interessato e verificare che
l'applicazione restituisca dati al di fuori dell'insieme di risultati previsto.

## Possible impact

Un attaccante può leggere, modificare o eliminare dati nel database e, a seconda
della configurazione, ottenere un accesso più ampio all'host.

## Recommendation

Utilizzare query parametrizzate (prepared statement) per ogni accesso al database
e validare l'input con una lista di elementi consentiti. Impiegare account di
database con privilegi minimi.
''',
  'reflected-xss': '''
---
title: Cross-site scripting (XSS) riflesso
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

L'input dell'utente viene riflesso nella risposta senza un'adeguata codifica in
uscita, per cui un attaccante può iniettare script eseguiti nel browser della
vittima.

## Confirmation (reproduction)

Fornire un payload nel parametro interessato e osservarne l'esecuzione nella
pagina renderizzata.

## Possible impact

Dirottamento della sessione, furto di credenziali e azioni compiute per conto
della vittima all'interno dell'applicazione.

## Recommendation

Codifica in uscita sensibile al contesto di tutti i dati controllati dall'utente,
una Content Security Policy rigorosa e l'escaping automatico del framework.
''',
  'weak-password-policy': '''
---
title: Politica delle password debole
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

L'applicazione accetta password deboli (brevi, comuni o prive di requisiti di
complessità), rendendo gli account più facili da indovinare.

## Confirmation (reproduction)

Registrare o modificare una password con un valore breve e comune e verificare
che venga accettata.

## Possible impact

Maggiore probabilità di appropriazione degli account tramite attacchi di forza
bruta o di credential stuffing.

## Recommendation

Imporre una lunghezza minima, verificare rispetto a elenchi di password violate e
supportare l'autenticazione a più fattori.
''',
};
