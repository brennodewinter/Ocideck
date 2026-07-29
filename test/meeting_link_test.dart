import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_failure.dart';
import 'package:ocideck/meetings/meeting_link.dart';
import 'package:ocideck/meetings/meeting_models.dart';

/// De resolver herkent lokaal, weigert hard en stuurt niets het netwerk op
/// (`COLLABORATION.md` §7.1.3, TEAMS_GUEST_CLIENT.md §12.1).
void main() {
  const providerId = MeetingProviderId('proef');

  /// Een kandidaat van drie regels: precies waarvoor [MeetingLinkCandidate]
  /// smaller is dan `MeetingProvider`.
  final candidate = _Candidate(
    id: providerId,
    hosts: {'meet.proef.invalid'},
    matcher: (uri) =>
        uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'j'
        ? MeetingLinkMatch(provider: providerId, invitation: uri)
        : null,
  );
  final resolver = MeetingLinkResolver([candidate]);

  MeetingFailureKind? rejectionOf(MeetingLinkResolution resolution) =>
      resolution is MeetingLinkRejected ? resolution.failure.kind : null;

  group('harde weigeringen', () {
    test('een lege of veel te lange link is ongeldig', () {
      expect(rejectionOf(resolver.resolve('')), MeetingFailureKind.invalidLink);
      expect(
        rejectionOf(resolver.resolve('   ')),
        MeetingFailureKind.invalidLink,
      );
      final tooLong =
          'https://meet.proef.invalid/j/${'a' * maxInvitationLength}';
      expect(
        rejectionOf(resolver.resolve(tooLong)),
        MeetingFailureKind.invalidLink,
      );
    });

    test('stuurtekens in de geplakte tekst wijzen de link af', () {
      expect(
        rejectionOf(resolver.resolve('https://meet.proef.invalid/j/x\u0000')),
        MeetingFailureKind.invalidLink,
      );
      expect(
        rejectionOf(resolver.resolve('https://meet.proef.invalid/\tj/x')),
        MeetingFailureKind.invalidLink,
      );
    });

    test('alleen https; http mag enkel als lokale ontwikkelopstelling', () {
      expect(
        rejectionOf(resolver.resolve('http://meet.proef.invalid/j/x')),
        MeetingFailureKind.invalidLink,
      );
      expect(
        rejectionOf(resolver.resolve('ftp://meet.proef.invalid/j/x')),
        MeetingFailureKind.invalidLink,
      );
      final dev = MeetingLinkResolver([candidate], allowLocalDevelopment: true);
      // localhost mag dan wél door het schema heen; herkennen doet hij niet,
      // want de host staat bij geen kandidaat.
      expect(
        dev.resolve('http://localhost/j/x'),
        isA<MeetingLinkUnrecognised>(),
      );
      // Maar een gewone host zonder TLS blijft ook daar geweigerd.
      expect(
        rejectionOf(dev.resolve('http://meet.proef.invalid/j/x')),
        MeetingFailureKind.invalidLink,
      );
    });

    test('inloggegevens in de URL zijn een vermomming, geen invoer', () {
      expect(
        rejectionOf(
          resolver.resolve('https://meet.proef.invalid@aanvaller.example/j/x'),
        ),
        MeetingFailureKind.invalidLink,
      );
    });

    test('een ingebakken instellingsparameter wijst de link af', () {
      for (final name in forbiddenInvitationParameters) {
        expect(
          rejectionOf(
            resolver.resolve('https://meet.proef.invalid/j/x?$name=evil'),
          ),
          MeetingFailureKind.invalidLink,
          reason: 'parameter $name hoort de link af te wijzen',
        );
      }
      // Ook met hoofdletters: de naamvergelijking is niet te omzeilen.
      expect(
        rejectionOf(
          resolver.resolve('https://meet.proef.invalid/j/x?BROKER=evil'),
        ),
        MeetingFailureKind.invalidLink,
      );
    });
  });

  group('opschonen', () {
    test('fragment en volgparameters gaan eraf, de rest blijft letterlijk', () {
      final result = resolver.resolve(
        'https://meet.proef.invalid/j/x?utm_source=mail&zaak=19%3Aopaak&fbclid=1#frag',
      );
      final match = (result as MeetingLinkRecognised).match;
      expect(
        match.invitation.toString(),
        'https://meet.proef.invalid/j/x?zaak=19%3Aopaak',
      );
    });

    test('een ondoorzichtig pad wordt niet opnieuw gecodeerd', () {
      final result = resolver.resolve(
        'https://meet.proef.invalid/j/19%3ameeting_abc%40thread?p=1%2B1',
      );
      final match = (result as MeetingLinkRecognised).match;
      // De escapes blijven staan (niets wordt gedecodeerd); alleen de
      // hex-hoofdletters zijn genormaliseerd, en dat is per RFC 3986
      // betekenisloos.
      expect(
        match.invitation.toString(),
        'https://meet.proef.invalid/j/19%3Ameeting_abc%40thread?p=1%2B1',
      );
    });

    test('displayOrigin toont alleen de herkomst, nooit het pad', () {
      final result = resolver.resolve('https://meet.proef.invalid/j/geheim');
      final match = (result as MeetingLinkRecognised).match;
      expect(match.displayOrigin, 'https://meet.proef.invalid');
      expect(match.displayOrigin, isNot(contains('geheim')));
    });
  });

  group('kiezen op hostnaam', () {
    test('subdomeinen van een vertrouwde host horen erbij', () {
      expect(
        resolver.resolve('https://west.meet.proef.invalid/j/x'),
        isA<MeetingLinkRecognised>(),
      );
    });

    test('achtervoegselveilig: een look-alike host valt erbuiten', () {
      // Eindigt op `.example`, hoe hard hij ook op de echte host lijkt.
      final result = resolver.resolve(
        'https://meet.proef.invalid.aanvaller.example/j/x',
      );
      expect(result, isA<MeetingLinkUnrecognised>());
      // En plakken zonder puntgrens telt ook niet.
      expect(
        resolver.resolve('https://xmeet.proef.invalid.example/j/x'),
        isA<MeetingLinkUnrecognised>(),
      );
    });

    test(
      'een onbekende host geeft eerlijk onbekend, met alleen de herkomst',
      () {
        final result = resolver.resolve('https://vreemd.example/pad/geheim');
        final unrecognised = result as MeetingLinkUnrecognised;
        expect(unrecognised.origin, 'https://vreemd.example');
        expect(unrecognised.origin, isNot(contains('geheim')));
      },
    );

    test('bekende host maar onbekend pad is een eigen uitleg', () {
      final result = resolver.resolve('https://meet.proef.invalid/gewoon');
      expect(rejectionOf(result), MeetingFailureKind.unsupportedMeetingType);
      expect((result as MeetingLinkRejected).failure.provider, providerId);
    });

    test('bij twee kandidaten wint de langste passende host', () {
      const specifiekId = MeetingProviderId('specifiek');
      final specifiek = _Candidate(
        id: specifiekId,
        hosts: {'west.meet.proef.invalid'},
        matcher: (uri) =>
            MeetingLinkMatch(provider: specifiekId, invitation: uri),
      );
      final twee = MeetingLinkResolver([candidate, specifiek]);
      final result = twee.resolve('https://west.meet.proef.invalid/j/x');
      final match = (result as MeetingLinkRecognised).match;
      expect(match.provider, specifiekId);
    });
  });
}

class _Candidate implements MeetingLinkCandidate {
  _Candidate({required this.id, required this.hosts, required this.matcher});

  @override
  final MeetingProviderId id;

  final Set<String> hosts;
  final MeetingLinkMatch? Function(Uri) matcher;

  @override
  Set<String> get trustedHosts => hosts;

  @override
  MeetingLinkMatch? match(Uri invitation) => matcher(invitation);
}
