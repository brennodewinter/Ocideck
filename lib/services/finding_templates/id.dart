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

/// De meegeleverde finding-sjablonen in het Indonesisch (id).
const Map<String, String> findingTemplatesId = {
  'sql-injection': '''
---
title: Injeksi SQL
severity: Critical
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-89 — Improper Neutralization of Special Elements used in an SQL Command
references:
  - https://owasp.org/www-community/attacks/SQL_Injection
  - https://cwe.mitre.org/data/definitions/89.html
---

## Description

Masukan pengguna disisipkan ke dalam kueri SQL tanpa parameterisasi yang benar,
sehingga penyerang dapat mengubah logika kueri.

## Confirmation (reproduction)

Kirimkan nilai yang dirancang khusus pada parameter terkait dan amati bahwa
aplikasi mengembalikan data di luar himpunan hasil yang dimaksudkan.

## Possible impact

Penyerang dapat membaca, mengubah, atau menghapus data dalam basis data dan,
tergantung konfigurasinya, memperoleh akses lebih lanjut ke host.

## Recommendation

Gunakan kueri berparameter (prepared statements) untuk semua akses basis data dan
validasi masukan terhadap daftar yang diizinkan. Gunakan akun basis data dengan
hak istimewa minimal.
''',
  'reflected-xss': '''
---
title: Cross-site scripting (XSS) terpantul
severity: High
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-79 — Improper Neutralization of Input During Web Page Generation
references:
  - https://owasp.org/www-community/attacks/xss/
  - https://cwe.mitre.org/data/definitions/79.html
---

## Description

Masukan pengguna dipantulkan dalam respons tanpa pengodean keluaran yang benar,
sehingga penyerang dapat menyuntikkan skrip yang berjalan di peramban korban.

## Confirmation (reproduction)

Berikan payload pada parameter terkait dan amati eksekusinya di halaman yang
dirender.

## Possible impact

Pembajakan sesi, pencurian kredensial, dan tindakan yang dilakukan atas nama korban
di dalam aplikasi.

## Recommendation

Pengodean keluaran sesuai konteks untuk semua data yang dikendalikan pengguna,
Content Security Policy yang ketat, dan escaping otomatis oleh kerangka kerja.
''',
  'weak-password-policy': '''
---
title: Kebijakan kata sandi lemah
severity: Medium
cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N
cvss_version: 4.0
cwe: CWE-521 — Weak Password Requirements
references:
  - https://cwe.mitre.org/data/definitions/521.html
---

## Description

Aplikasi menerima kata sandi lemah (pendek, umum, atau tanpa persyaratan
kompleksitas), sehingga akun lebih mudah ditebak.

## Confirmation (reproduction)

Daftarkan atau ubah kata sandi menjadi nilai pendek dan umum lalu amati bahwa nilai
itu diterima.

## Possible impact

Meningkatnya kemungkinan pengambilalihan akun melalui serangan brute force atau
credential stuffing.

## Recommendation

Terapkan panjang minimum, periksa terhadap daftar kata sandi yang bocor, dan
dukung autentikasi multifaktor.
''',
};
