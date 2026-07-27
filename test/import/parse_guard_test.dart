import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/models/conversion_issue.dart';
import 'package:ocideck/services/import/pipeline/parse_guard.dart';

/// De foutgrens die #877 legt: één onderdeel dat struikelt wordt genoteerd en
/// overgeslagen, de rest gaat door, en de fout lekt geen broninhoud naar het
/// log of de notitie.
void main() {
  test('geeft de body-waarde ongewijzigd terug bij succes', () {
    final issues = <ConversionIssue>[];
    final value = guardParse<int>(
      sink: issues,
      slideIndex: 0,
      component: IssueComponent.chart,
      feature: 'Grafiek',
      description: 'kon niet worden gelezen en is overgeslagen',
      logOp: 'test',
      body: () => 42,
    );
    expect(value, 42);
    expect(issues, isEmpty, reason: 'een geslaagde parse noteert niets');
  });

  test(
    'noteert bij een worp één issue met onderdeel + oorzaak en valt terug',
    () {
      final issues = <ConversionIssue>[];
      final value = guardParse<int>(
        sink: issues,
        slideIndex: 3,
        component: IssueComponent.chart,
        feature: 'Grafiek',
        description: 'kon niet worden gelezen en is overgeslagen',
        logOp: 'test',
        body: () => throw const FormatException('kapot'),
        fallback: -1,
        log: (_, _) {},
      );
      expect(value, -1, reason: 'de fallback laat de aanroeper doorgaan');
      expect(issues, hasLength(1));
      final issue = issues.single;
      expect(issue.slideIndex, 3);
      expect(issue.component, IssueComponent.chart);
      expect(issue.cause, IssueCause.malformedXml);
      expect(issue.feature, 'Grafiek');
    },
  );

  test('guardParseVoid isoleert een worp en laat de aanroeper doorgaan', () {
    // De grens die de Keynote-`reconstruct()`-lus en het PPTX-tekstvak gebruiken:
    // een worp in één onderdeel wordt genoteerd, de lus draait door.
    final issues = <ConversionIssue>[];
    final done = <int>[];
    for (var i = 0; i < 3; i++) {
      guardParseVoid(
        sink: issues,
        slideIndex: i,
        component: IssueComponent.slide,
        feature: 'Dia-inhoud',
        description: 'kon niet worden gelezen en is overgeslagen',
        logOp: 'test dia $i',
        body: () {
          if (i == 1) throw StateError('kapotte dia');
          done.add(i);
        },
      );
    }
    expect(done, [0, 2], reason: 'dia 1 struikelt, 0 en 2 gaan gewoon door');
    expect(issues, hasLength(1));
    expect(issues.single.slideIndex, 1);
    expect(issues.single.component, IssueComponent.slide);
    expect(issues.single.cause, IssueCause.unexpected);
  });

  test(
    'classifyParseCause: FormatException → malformedXml, rest → unexpected',
    () {
      expect(
        classifyParseCause(const FormatException('x')),
        IssueCause.malformedXml,
      );
      expect(classifyParseCause(StateError('x')), IssueCause.unexpected);
      expect(classifyParseCause(ArgumentError('x')), IssueCause.unexpected);
    },
  );

  test('het log krijgt alleen het fouttype en géén broninhoud (#877)', () {
    final issues = <ConversionIssue>[];
    final captured = <(String, Object)>[];
    // Een fout waarvan de tekst doet alsof er bijzondere persoonsgegevens uit de
    // bron in staan — precies wat níét in het log mag belanden.
    const secret = 'BSN 123456782 van Jansen';
    guardParse<int>(
      sink: issues,
      slideIndex: 1,
      component: IssueComponent.slide,
      feature: 'Dia-inhoud',
      description: 'kon niet worden gelezen en is overgeslagen',
      logOp: 'PptxImporter: dia 2',
      body: () => throw const FormatException(secret),
      log: (op, error) => captured.add((op, error)),
    );

    expect(captured, hasLength(1));
    final (op, error) = captured.single;
    // Doorgegeven wordt het *type* (een `Type`), niet het foutobject zelf.
    expect(error, isA<Type>());
    expect(error, FormatException);
    // De opgebouwde melding draagt categorieën, geen broninhoud.
    expect(op, isNot(contains('BSN')));
    expect(op, isNot(contains('123456782')));
    expect(op, isNot(contains('Jansen')));
    expect(op, contains('slide'));
    expect(op, contains('malformedXml'));

    // En de genoteerde issue draagt evenmin broninhoud: vaste strings, lege args.
    expect(issues.single.args, isEmpty);
    expect(issues.single.feature, 'Dia-inhoud');
  });
}
