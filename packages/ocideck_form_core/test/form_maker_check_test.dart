import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

const String published = '''<!-- form id=kook version=1 -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->

<!-- field id=mail type=text pattern=email -->
**E-mail**
<!-- answer -->
<!-- /field id=mail -->

<!-- field id=ander type=text pattern=email -->
**Tweede adres**
<!-- answer -->
<!-- /field id=ander -->

<!-- field id=site type=text pattern=url -->
**Site**
<!-- answer -->
<!-- /field id=site -->

<!-- field id=vrij type=text -->
**Vrij**
<!-- answer -->
<!-- /field id=vrij -->
''';

FormSpec get spec => (parseForm(published) as ParsedForm).spec;

FormAnswers answers(Map<String, String> zones) {
  var text = published;
  zones.forEach((id, zone) {
    text = text.replaceFirstMapped(
      RegExp(
        '(<!-- field id=$id [^>]*-->(?:(?!<!-- field)[\\s\\S])*?)<!-- answer -->\n[\\s\\S]*?<!-- /field id=$id -->',
      ),
      (m) => '${m[1]}<!-- answer -->\n$zone\n<!-- /field id=$id -->',
    );
  });
  return extractAnswers(spec, text);
}

void main() {
  group('makerAddressOf', () {
    test('is het adres in het eerste e-mailveld dat is ingevuld', () {
      expect(
        makerAddressOf(spec, answers({'mail': 'sari@example.nl'})),
        'sari@example.nl',
      );
    });

    test('slaat een leeg veld over en neemt het volgende', () {
      expect(
        makerAddressOf(spec, answers({'ander': 'joe@example.nl'})),
        'joe@example.nl',
      );
    });

    test('kiest het eerste van twee ingevulde velden', () {
      expect(
        makerAddressOf(
          spec,
          answers({'mail': 'sari@example.nl', 'ander': 'joe@example.nl'}),
        ),
        'sari@example.nl',
      );
    });

    test('slaat een antwoord over dat geen adres is', () {
      expect(
        makerAddressOf(
          spec,
          answers({'mail': 'geen adres', 'ander': 'joe@example.nl'}),
        ),
        'joe@example.nl',
      );
    });

    test('laat spaties om het adres weg', () {
      expect(
        makerAddressOf(spec, answers({'mail': '  sari@example.nl  '})),
        'sari@example.nl',
      );
    });

    test('kijkt niet naar een tekstveld zonder e-mailpatroon', () {
      expect(
        makerAddressOf(
          spec,
          answers({'vrij': 'sari@example.nl', 'site': 'https://example.nl'}),
        ),
        isNull,
      );
    });

    test('is er geen als niets is ingevuld', () {
      expect(makerAddressOf(spec, answers({})), isNull);
    });
  });

  group('isMailableAddress', () {
    test('neemt een gewoon adres aan', () {
      expect(isMailableAddress('sari@example.nl'), isTrue);
    });

    test('weigert wat het e-mailpatroon al weigert', () {
      expect(isMailableAddress('sari'), isFalse);
      expect(isMailableAddress('sari@example'), isFalse);
      expect(isMailableAddress('sa ri@example.nl'), isFalse);
      expect(isMailableAddress('a@b.nl,c@d.nl'), isFalse);
    });

    test('weigert een stuurteken dat het patroon doorlaat', () {
      expect(isMailableAddress('sa\u0000ri@example.nl'), isFalse);
      expect(isMailableAddress('sa\u007fri@example.nl'), isFalse);
      expect(isMailableAddress('sa\u001fri@example.nl'), isFalse);
    });

    test('neemt een adres met een letter buiten ASCII aan', () {
      expect(isMailableAddress('zoë@example.nl'), isTrue);
    });

    test('neemt het eerste teken boven de grens aan', () {
      expect(isMailableAddress('sa!ri@example.nl'), isTrue);
    });
  });

  group('makerCheckMailLink', () {
    String link({
      String address = 'sari@example.nl',
      String subject = 'Onderwerp',
      String body = 'Tekst',
    }) => makerCheckMailLink(address: address, subject: subject, body: body);

    test('is een mailto met adres, onderwerp en tekst', () {
      expect(
        link(),
        'mailto:sari%40example.nl?subject=Onderwerp&body=Tekst'.replaceFirst(
          '%40',
          '@',
        ),
      );
    });

    test('schrijft een spatie als %20, nooit als plus', () {
      final text = link(subject: 'Jouw bijdrage', body: 'Is dit goed?');
      expect(text, contains('subject=Jouw%20bijdrage'));
      expect(text, contains('body=Is%20dit%20goed%3F'));
      expect(text, isNot(contains('+')));
    });

    test('laat in de tekst een & of ? de link niet verbreken', () {
      final uri = Uri.parse(link(body: 'a&b=c?d#e%f'));
      expect(uri.queryParameters['body'], 'a&b=c?d#e%f');
      expect(uri.queryParameters.keys, unorderedEquals(['subject', 'body']));
    });

    test('kan een regelovergang en niet-ASCII aan', () {
      final uri = Uri.parse(link(subject: 'Zoë', body: 'Eén\nTwee'));
      expect(uri.queryParameters['subject'], 'Zoë');
      expect(uri.queryParameters['body'], 'Eén\nTwee');
    });

    test('een ? in het adres voegt geen kop toe', () {
      final text = link(address: 'x?bcc=boos@example.nl');
      final uri = Uri.parse(text);
      expect(uri.queryParameters.keys, unorderedEquals(['subject', 'body']));
      expect(Uri.decodeComponent(uri.path), 'x?bcc=boos@example.nl');
    });

    test('een & # of % in het adres blijft in het adres', () {
      final uri = Uri.parse(link(address: 'a&b#c%d@example.nl'));
      expect(uri.queryParameters.keys, unorderedEquals(['subject', 'body']));
      expect(Uri.decodeComponent(uri.path), 'a&b#c%d@example.nl');
      expect(uri.fragment, isEmpty);
    });

    test('een & of ? in de domeinnaam blijft in het adres', () {
      final uri = Uri.parse(link(address: 'a@exa?mple.nl'));
      expect(uri.queryParameters.keys, unorderedEquals(['subject', 'body']));
      expect(Uri.decodeComponent(uri.path), 'a@exa?mple.nl');
    });

    test('weigert een adres dat geen adres is', () {
      expect(() => link(address: 'geen adres'), throwsArgumentError);
      expect(() => link(address: 'a\u0000@example.nl'), throwsArgumentError);
    });
  });
}
