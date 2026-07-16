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

/// De meegeleverde finding-sjablonen in het Iers (ga).
const Map<String, String> findingTemplatesGa = {
  'sql-injection': '''
---
title: Instealladh SQL
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Cuirtear ionchur an úsáideora isteach in iarratas SQL gan paraiméadrú cuí, rud a
ligeann d'ionsaitheoir loighic an iarratais a athrú.

## Confirmation (reproduction)

Cuir luach ceaptha isteach sa pharaiméadar lena mbaineann agus tabhair faoi deara
go dtugann an feidhmchlár sonraí ar ais lasmuigh den tacar torthaí atá beartaithe.

## Possible impact

Is féidir le hionsaitheoir sonraí sa bhunachar a léamh, a athrú nó a scriosadh
agus, ag brath ar chumraíocht an bhunachair, tuilleadh rochtana a fháil ar an
óstach.

## Recommendation

Bain úsáid as iarratais pharaiméadraithe (ráitis ullmhaithe) do gach rochtain ar an
mbunachar agus bailíochtaigh an t-ionchur i gcoinne liosta ceadaithe. Úsáid cuntais
bhunachair leis na cearta is lú.
''',
  'reflected-xss': '''
---
title: Cross-site scripting (XSS) frithchaite
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Frithchaitear ionchur an úsáideora sa fhreagra gan ionchódú aschuir cuí, agus mar
sin is féidir le hionsaitheoir script a instealladh a ritheann i mbrabhsálaí an
íospartaigh.

## Confirmation (reproduction)

Cuir pálasta ar fáil sa pharaiméadar lena mbaineann agus breathnaigh air á rith sa
leathanach rindreáilte.

## Possible impact

Fuadach seisiúin, goid dintiúr agus gníomhartha a dhéantar thar ceann an
íospartaigh laistigh den fheidhmchlár.

## Recommendation

Ionchódú aschuir atá comhthéacs-eolach do gach sonra atá faoi smacht an úsáideora,
Content Security Policy dian, agus éalú uathoibríoch an chreata.
''',
  'weak-password-policy': '''
---
title: Polasaí pasfhocal lag
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Glacann an feidhmchlár le pasfhocail laga (gearr, coitianta nó gan riachtanais
chastachta), rud a fhágann gur fusa buille faoi thuairim a thabhairt faoi chuntais.

## Confirmation (reproduction)

Cláraigh nó athraigh pasfhocal go luach gearr, coitianta agus tabhair faoi deara go
nglactar leis.

## Possible impact

Dóchúlacht mhéadaithe go dtógfar cuntas ar láimh trí ionsaithe brute-force nó
credential stuffing.

## Recommendation

Cuir íosfhad i bhfeidhm, seiceáil i gcoinne liostaí pasfhocal sceite, agus tacaigh
le fíordheimhniú ilfhachtóra.
''',
};
