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

/// De meegeleverde finding-sjablonen in het Turks (tr).
const Map<String, String> findingTemplatesTr = {
  'sql-injection': '''
---
title: SQL enjeksiyonu
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Kullanıcı girdisi, gerektiği gibi parametreleştirilmeden bir SQL sorgusuna
alınıyor; bu da saldırganın sorgunun mantığını değiştirmesine olanak tanıyor.

## Confirmation (reproduction)

İlgili parametreye özel hazırlanmış bir değer gönderin ve uygulamanın
amaçlanan sonuç kümesinin dışındaki verileri döndürdüğünü gözlemleyin.

## Possible impact

Saldırgan veritabanındaki verileri okuyabilir, değiştirebilir veya silebilir ve
veritabanı yapılandırmasına bağlı olarak sunucuya daha ileri erişim elde
edebilir.

## Recommendation

Tüm veritabanı erişimi için parametreli sorgular (prepared statement) kullanın
ve girdiyi izin listesine göre doğrulayın. Veritabanı hesaplarını en az yetki
ilkesiyle çalıştırın.
''',
  'reflected-xss': '''
---
title: Yansıtılmış siteler arası betik çalıştırma (XSS)
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Kullanıcı girdisi, gerektiği gibi çıktı kodlaması yapılmadan yanıta
yansıtılıyor; bu da saldırganın kurbanın tarayıcısında çalışan betik enjekte
etmesine olanak tanıyor.

## Confirmation (reproduction)

İlgili parametreye bir yük (payload) girin ve bunun işlenmiş sayfada
çalıştırıldığını gözlemleyin.

## Possible impact

Oturumun ele geçirilmesi, oturum açma bilgilerinin çalınması ve uygulama
içinde kurban adına gerçekleştirilen işlemler.

## Recommendation

Kullanıcı denetimindeki tüm verilerde bağlama duyarlı çıktı kodlaması, katı bir
Content Security Policy ve çerçevenin otomatik kaçış (escaping) desteği.
''',
  'weak-password-policy': '''
---
title: Zayıf parola politikası
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Uygulama zayıf parolaları (kısa, yaygın veya karmaşıklık koşulu olmayan) kabul
ediyor; bu da hesapların tahmin yoluyla ele geçirilmesini kolaylaştırıyor.

## Confirmation (reproduction)

Kısa ve yaygın bir parola ile kayıt olun veya parolanızı bu değerle
değiştirin ve kabul edildiğini gözlemleyin.

## Possible impact

Kaba kuvvet veya kimlik bilgisi doldurma saldırılarıyla hesap ele geçirilmesi
olasılığının artması.

## Recommendation

En az uzunluk koşulunu zorunlu kılın, sızmış parola listelerine karşı denetim
yapın ve çok faktörlü kimlik doğrulamayı destekleyin.
''',
};
