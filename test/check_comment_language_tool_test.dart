// De poort op de commentaartaalregel (tool/check_comment_language.dart) op een
// kleine fixture.
//
// Waarom dit bestand er is. Deze poort meldt vandaag "tien, net als de
// basislijn", en dat getal ziet er hetzelfde uit of hij nu goed meet of
// helemaal niets meer ziet. CONTRIBUTING waarschuwt bovendien expliciet dat een
// taalheuristiek die er 5% naast zit een slechtere poort is dan geen poort —
// dus de vraag is hier niet alleen "vindt hij het mengen" maar net zo hard
// "zwijgt hij waar hij hoort te zwijgen". Beide kanten staan hieronder.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_comment_language.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('comment_language'));
  tearDown(() => root.deleteSync(recursive: true));

  List<CommentBlock> blocksOf(String source) {
    final file = File('${root.path}/sample.dart')
      ..createSync()
      ..writeAsStringSync(source);
    return commentBlocks(file);
  }

  List<CommentBlock> mixedIn(String source) =>
      blocksOf(source).where((b) => b.isMixed).toList();

  group('slaat aan op', () {
    test('een Engelse alinea met een Nederlandse eronder', () {
      final mixed = mixedIn('''
// Refuses a loose file that is not a presentation, and tells the user why.
// Dat gebeurt hier en niet in de aanroeper, want daar is de reden al weg.
void f() {}
''');
      expect(mixed, hasLength(1));
    });

    test('één zin die in het Engels begint en in het Nederlands afloopt', () {
      // Het echte geval uit shell_actions.dart: "…instead of doing nothing
      // silently, en met de reden erbij als het openpad die kende."
      final mixed = mixedIn('''
// The file is refused instead of failing silently, en met de reden
// erbij als het openpad die kende.
void f() {}
''');
      expect(mixed, hasLength(1));
    });
  });

  group('zwijgt bij', () {
    test('een blok dat helemaal Nederlands is', () {
      expect(
        mixedIn('''
// Dit blok is helemaal Nederlands, dus hier hoort geen melding te staan,
// ook niet wanneer het over een `Widget` of een `HttpClient` gaat.
void f() {}
'''),
        isEmpty,
      );
    });

    test('een blok dat helemaal Engels is', () {
      expect(
        mixedIn('''
// This block is entirely English, and the gate should stay quiet because
// there is nothing here that switches language halfway through.
void f() {}
'''),
        isEmpty,
      );
    });

    test('een Nederlands blok dat een Engelse term citeert', () {
      // Dit is de valkuil die een naïeve teller de hele dag laat afgaan: een
      // geciteerde interfacetekst of een identifier is geen taalwissel.
      expect(
        mixedIn('''
// De knop heet "Save and close" en dat is een merknaam-achtige term uit
// de andere applicatie; hier wordt hij niet vertaald.
void f() {}
'''),
        isEmpty,
      );
    });

    test('dartdoc met een Engelse samenvatting en Nederlandse redenering', () {
      // Precies de vorm die CONTRIBUTING zélf voorschrijft voor nieuwe publieke
      // types in lib/models en lib/services. Zou de poort hier afgaan, dan
      // beboet hij de bijdragersgids en wordt hij uitgezet.
      expect(
        mixedIn('''
/// Parses a hex colour string. Returns null when invalid, so that callers
/// can skip the pair instead of throwing.
///
/// Dit is bewust de strenge variant: alleen zes tekens, en null bij twijfel,
/// want wie een kleur nodig heeft die er altijd is neemt de andere.
int f() => 0;
'''),
        isEmpty,
      );
    });
  });

  group('blokindeling', () {
    test('een lege regel breekt een blok in tweeën', () {
      // Anders zou een Engelse kopregel bovenaan een bestand samensmelten met
      // een losstaande Nederlandse notitie twintig regels lager.
      final blocks = blocksOf('''
// This is the first thought, and it ends here.

// Dit is een andere gedachte, en die staat hier los van.
void f() {}
''');
      expect(blocks, hasLength(2));
      expect(blocks.every((b) => !b.isMixed), isTrue);
    });

    test('dartdoc en gewoon commentaar smelten niet samen', () {
      final blocks = blocksOf('''
/// Returns the thing that the caller asked for, and nothing else.
// Dit staat er los onder en hoort niet bij de dartdoc erboven.
void f() {}
''');
      expect(blocks, hasLength(2));
      expect(blocks.first.isDoc, isTrue);
      expect(blocks.last.isDoc, isFalse);
    });
  });
}
