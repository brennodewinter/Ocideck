// De release-manifest `SHA256SUMS` wordt met minisign ondertekend, en de
// publieke sleutel `minisign.pub` staat in de repo-root zodat een ontvanger de
// handtekening kan verifiëren. Een handtekening is niets waard als niemand de
// bijbehorende publieke sleutel kan vinden — deze poort bewaakt daarom niet het
// tekenen zelf (dat is een lokale, handmatige stap), maar dat de publieke
// sleutel gepubliceerd én aangewezen blijft, en dat de gereedschapsketen die
// hem gebruikt niet stilletjes verdwijnt.
//
// Zonder deze poort zou een refactor die `minisign.pub` weghaalt, de verwijzing
// eruit sloopt of het teken-script hernoemt, groen door de bouw komen terwijl de
// verify-route voor elke download stilzwijgend kapot is.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final pub = File('minisign.pub');
  final script = File('scripts/sign_release.sh');
  final makefile = File('Makefile').readAsStringSync();
  final security = File('SECURITY.md').readAsStringSync();
  final releaseBody = File('.forgejo/release-body.md').readAsStringSync();

  // De verwachte publieke sleutel, gepind. Welgevormdheid alleen is niet genoeg:
  // een omgewisselde — even welgevormde — sleutel zou de héle verify-keten stil
  // op een andere wortel laten rusten. Deze constante is het vaste anker; ze
  // staat óók in SECURITY.md (sleutel-ID 9A467E62F323426D) en is via de
  // GitHub-spiegel en de git-historie onafhankelijk na te lopen. Verandert de
  // sleutel echt, dan is dat een bewuste rotatie en werk je deze regel bij.
  const verwachteSleutel =
      'RWRtQiPzYn5Gms/+PoSdQ2lFVHJBpovjvVenIJLYC5M2iqkKj+WC0rnD';
  const verwachteSleutelId = '9A467E62F323426D';

  test('de publieke sleutel staat in de repo-root en is de gepinde sleutel', () {
    expect(pub.existsSync(), isTrue,
        reason: 'minisign.pub hoort in de repo-root te staan.');
    final regels = pub
        .readAsStringSync()
        .split('\n')
        .where((r) => r.trim().isNotEmpty)
        .toList();
    // Een minisign-publieke-sleutel is twee regels: een `untrusted comment:`-
    // regel (met de sleutel-ID) en de base64-sleutel zelf.
    expect(regels.length, 2,
        reason: 'Een minisign-pubkey is een commentaarregel + de sleutelregel.');
    expect(regels.first.toLowerCase(), contains('untrusted comment'));
    expect(regels.first, contains(verwachteSleutelId));
    expect(regels[1].trim(), verwachteSleutel,
        reason: 'Een sleutelverwisseling moet de bouw laten falen, niet stil '
            'doorkomen — pas deze regel alleen aan bij een bewuste rotatie.');
  });

  test('de private sleutel is NIET in de repo terechtgekomen', () {
    // Het tegenovergestelde van de vorige toets: de publieke helft hoort erin,
    // de private helft nooit. `.gitignore` is het vangnet; dit is de meting.
    expect(File('minisign.key').existsSync(), isFalse);
    expect(File('ocideck-release.key').existsSync(), isFalse);
  });

  test('het teken-script bestaat en gebruikt minisign', () {
    expect(script.existsSync(), isTrue);
    final inhoud = script.readAsStringSync();
    expect(inhoud, contains('minisign -Sm'),
        reason: 'Het script hoort de manifest met minisign te tekenen.');
    expect(inhoud, contains('minisign -Vm'),
        reason: 'Het script hoort de handtekening na te verifiëren.');
  });

  test('make sign-release roept het script aan', () {
    expect(makefile, contains('sign-release:'));
    expect(makefile, contains('scripts/sign_release.sh'));
  });

  test('de publieke sleutel is aangewezen in SECURITY.md en de release-tekst',
      () {
    // De sleutel moet vindbaar zijn langs de kanalen waar een ontvanger kijkt.
    expect(security, contains('minisign.pub'));
    expect(releaseBody, contains('minisign.pub'));
    // En de verify-instructie zelf staat in de release-tekst, niet alleen de
    // sleutel.
    expect(releaseBody, contains('minisign -Vm SHA256SUMS'));
  });
}
