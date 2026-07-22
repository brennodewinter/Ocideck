// `web/.well-known/security.txt` — de standaardroute (RFC 9116) waarlangs een
// onderzoeker een meldadres zoekt.
//
// Waarom hier een poort op staat: dit bestand veroudert stilletijd. Het heeft
// een verplichte vervaldatum, en een vervallen security.txt is erger dan geen —
// hij leest als "hier is niemand thuis", precies op het moment dat iemand iets
// te melden heeft. Niemand komt hier uit zichzelf langs.
//
// En het meldadres staat nu op vier plekken (SECURITY.md, COMPLIANCE.md,
// security-insights.yml, hier). Dat is er één te veel om met de hand gelijk te
// houden.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final file = File('web/.well-known/security.txt');
  final raw = file.readAsStringSync();

  /// De waarde van een RFC 9116-veld, of null.
  String? field(String name) {
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#') || !trimmed.contains(':')) continue;
      final key = trimmed.substring(0, trimmed.indexOf(':')).trim();
      if (key.toLowerCase() != name.toLowerCase()) continue;
      return trimmed.substring(trimmed.indexOf(':') + 1).trim();
    }
    return null;
  }

  test('hij reist mee met de webbuild', () {
    // Alles onder web/ wordt naar build/web/ gekopieerd, dus dit bestand
    // beantwoordt de standaardroute op élke plek waar deze build gehost wordt.
    expect(file.existsSync(), isTrue);
    expect(file.path, endsWith('.well-known/security.txt'));
  });

  test('de verplichte velden staan erin', () {
    // Contact en Expires zijn verplicht onder RFC 9116. Zonder Expires is het
    // bestand formeel ongeldig.
    expect(field('Contact'), isNotNull);
    expect(field('Expires'), isNotNull);
  });

  test('het meldadres is hetzelfde als in SECURITY.md', () {
    final contact = field('Contact')!;
    expect(contact, startsWith('mailto:'));
    final address = contact.substring('mailto:'.length);

    expect(
      File('SECURITY.md').readAsStringSync(),
      contains(address),
      reason:
          'security.txt stuurt een onderzoeker naar $address en SECURITY.md '
          'noemt dat adres niet. Wie de standaardroute volgt, komt dan ergens '
          'anders uit dan waar de repo hem heen stuurt — en dat is precies de '
          'bocht waar een tijdkritische melding blijft liggen (#597).',
    );
  });

  test('hij is niet vervallen, en niet verder dan een jaar vooruit', () {
    final expires = DateTime.parse(field('Expires')!);
    final now = DateTime.now().toUtc();

    expect(
      expires.isAfter(now),
      isTrue,
      reason:
          'security.txt is vervallen op $expires. Een vervallen bestand leest '
          'als "hier is niemand thuis". Zet er een nieuwe datum in (onder een '
          'jaar vooruit) en controleer meteen of het adres nog klopt.',
    );
    expect(
      expires.difference(now).inDays,
      lessThanOrEqualTo(366),
      reason:
          'RFC 9116 wil een Expires binnen een jaar. Verder vooruit zetten is '
          'de controle uitstellen, niet oplossen.',
    );
  });

  test('de policy wijst naar een document dat bestaat', () {
    // Geen netwerkaanroep: alleen dat hij naar ons eigen SECURITY.md wijst en
    // niet naar een pad dat we ooit hernoemd hebben.
    final policy = field('Policy');
    expect(policy, isNotNull);
    expect(policy, endsWith('SECURITY.md'));
    expect(File('SECURITY.md').existsSync(), isTrue);
  });
}
