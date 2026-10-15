import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ociserve_badge_readiness.dart';
import 'package:ocideck/models/ociserve_evidence_item.dart';
import 'package:ocideck/models/ociserve_models.dart';
import 'support/ociserve_fake_gateway.dart';
import 'package:ocideck/models/ociserve_portfolio_import.dart';
import 'package:ocideck/models/ociserve_theme.dart';
import 'package:ocideck/services/ociserve/ociserve_gateway.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';
import 'package:ocideck/state/ociserve_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De dunne doorgeeflagen van de deelnemersketen (#2422–#2429) in de
/// provider: ze controleren het lidmaatschap, halen één toegangstoken op en
/// geven door aan de gateway. Het gedrag van de routes zelf staat in de
/// gateway-tests; dit toetst wat de provider eromheen doet — wie mag, welke
/// argumenten meegaan, en wat er na een mislukking blijft staan.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeOciServeApi api;
  late ProviderContainer container;
  late OciServeNotifier notifier;

  Future<void> signIn() async {
    await notifier.saveSettings(ociserveTestSettings);
    await notifier.login();
    expect(container.read(ociServeProvider).authenticated, isTrue);
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    api = newOciServeApi();
    container = ProviderContainer(overrides: ociserveTestOverrides(api));
    addTearDown(container.dispose);
    notifier = container.read(ociServeProvider.notifier);
  });

  group('uitnodigingen (#2425)', () {
    test(
      'preview is publiek: geen aanmelding nodig, alleen het serveradres',
      () async {
        api.handlers[#invitationRegistrationPreview] = (_) async =>
            'a@b.example';
        await notifier.saveSettings(ociserveTestSettings);
        final email = await notifier.previewInvitation(
          invitationId: 'inv',
          secret: 's3cret',
        );
        expect(email, 'a@b.example');
        expect(api.arg(#invitationRegistrationPreview, #invitationId), 'inv');
        expect(api.arg(#invitationRegistrationPreview, #secret), 's3cret');
      },
    );

    test(
      'registreren geeft het wachtwoord en de sleutel door, niets anders',
      () async {
        api.handlers[#invitationRegister] = (_) async =>
            const OciServeInvitationResult(
              organizationId: 'org',
              role: 'member',
            );
        await notifier.saveSettings(ociserveTestSettings);
        final result = await notifier.registerInvitation(
          invitationId: 'inv',
          secret: 's3cret',
          displayName: 'Sam',
          password: 'pw',
          idempotencyKey: 'key-1',
        );
        expect(result.organizationId, 'org');
        expect(api.arg(#invitationRegister, #idempotencyKey), 'key-1');
        expect(api.arg(#invitationRegister, #password), 'pw');
      },
    );

    test(
      'accepteren gebruikt het token en ververst daarna het account',
      () async {
        var meCalls = 0;
        api.handlers[#me] = (_) async {
          meCalls++;
          return meCalls == 1
              ? ociserveTestAccount
              : const OciServeAccount(
                  id: 'user',
                  memberships: [
                    OciServeMembership(organizationId: 'org'),
                    OciServeMembership(organizationId: 'org-2'),
                  ],
                );
        };
        api.handlers[#invitationAccept] = (_) async =>
            const OciServeInvitationResult(
              organizationId: 'org-2',
              role: 'member',
            );
        await signIn();
        await notifier.acceptInvitation(
          invitationId: 'inv',
          secret: 's3cret',
          idempotencyKey: 'key-2',
        );
        expect(api.arg(#invitationAccept, #accessToken), 'access');
        expect(
          container
              .read(ociServeProvider)
              .memberships
              .map((m) => m.organizationId),
          ['org', 'org-2'],
          reason: 'de nieuwe organisatie moet direct in het lidmaatschap staan',
        );
      },
    );
  });

  group('portefeuille (#2423)', () {
    test(
      'een publieke link wordt gelezen zonder aanmelding en leest items',
      () async {
        api.handlers[#fetchPortfolioDocument] = (_) async => <String, Object?>{
          'credentialSubject': <String, Object?>{
            'achievement': <String, Object?>{},
          },
        };
        await notifier.saveSettings(ociserveTestSettings);
        final items = await notifier.fetchPortfolioCredentials(
          Uri.parse('https://issuer.example/c/1'),
        );
        expect(api.calls, contains(#fetchPortfolioDocument));
        expect(items, isA<List<PortfolioImportItemInput>>());
      },
    );

    test(
      'een import aanmaken en teruglezen vraagt lidmaatschap en token',
      () async {
        api.handlers[#createPortfolioImport] = (_) async => 'imp-1';
        api.handlers[#portfolioImport] = (_) async =>
            const OciServePortfolioImport(
              importId: 'imp-1',
              status: 'ready',
              items: [],
            );
        await signIn();
        final id = await notifier.createPortfolioImport(
          organizationId: 'org',
          participantId: 'p',
          items: const [],
          idempotencyKey: 'k',
        );
        expect(id, 'imp-1');
        final read = await notifier.portfolioImport(
          organizationId: 'org',
          participantId: 'p',
          importId: id,
        );
        expect(read.status, 'ready');
      },
    );

    test(
      'een organisatie waar je geen lid van bent wordt geweigerd vóór de call',
      () async {
        await signIn();
        await expectLater(
          notifier.createPortfolioImport(
            organizationId: 'vreemd',
            participantId: 'p',
            items: const [],
            idempotencyKey: 'k',
          ),
          throwsA(isA<OciServeException>()),
        );
        expect(api.calls, isNot(contains(#createPortfolioImport)));
      },
    );

    test('delen kiest de nieuwste gepubliceerde versie van de soort', () async {
      api.handlers[#evidenceTypeVersions] = (_) async => const [
        OciServeEvidenceTypeVersion(id: 'v1', version: 1),
        OciServeEvidenceTypeVersion(id: 'v3', version: 3),
        OciServeEvidenceTypeVersion(id: 'v2', version: 2),
      ];
      api.handlers[#selectPortfolioItems] = (_) async => ['e1'];
      await signIn();
      final ids = await notifier.sharePortfolioItems(
        organizationId: 'org',
        participantId: 'p',
        importId: 'imp',
        selectedItemIds: const ['i1'],
        evidenceTypeId: 'type',
        idempotencyKey: 'k',
      );
      expect(ids, ['e1']);
      expect(api.arg(#selectPortfolioItems, #evidenceTypeVersionId), 'v3');
    });

    test(
      'delen zonder gepubliceerde versie faalt met een duidelijke code',
      () async {
        api.handlers[#evidenceTypeVersions] = (_) async =>
            const <OciServeEvidenceTypeVersion>[];
        await signIn();
        await expectLater(
          notifier.sharePortfolioItems(
            organizationId: 'org',
            participantId: 'p',
            importId: 'imp',
            selectedItemIds: const ['i1'],
            evidenceTypeId: 'type',
            idempotencyKey: 'k',
          ),
          throwsA(
            isA<OciServeException>().having(
              (e) => e.code,
              'code',
              'evidence_type_not_published',
            ),
          ),
        );
        expect(api.calls, isNot(contains(#selectPortfolioItems)));
      },
    );

    test('een bewijsstuk intrekken geeft het bijgewerkte stuk terug', () async {
      final item = OciServeEvidenceItem(
        id: 'e1',
        evidenceTypeId: 't',
        status: OciServeEvidenceContentStatus.ingetrokken,
        createdAt: DateTime.utc(2026, 10, 1),
      );
      api.handlers[#withdrawEvidenceItem] = (_) async => item;
      await signIn();
      final back = await notifier.withdrawEvidenceItem(
        organizationId: 'org',
        participantId: 'p',
        evidenceItemId: 'e1',
      );
      expect(back.id, 'e1');
      expect(
        api.arg(#withdrawEvidenceItem, #idempotencyKey),
        isA<String>().having((s) => s.isNotEmpty, 'niet leeg', isTrue),
      );
    });
  });

  group('thema’s (#2429)', () {
    const theme = OciServeTheme(
      id: 't1',
      name: 'Huisstijl',
      definition: {'a': 1},
      isBuiltin: false,
    );

    test('alle pagina’s worden gelezen, begrensd op vijf', () async {
      var page = 0;
      api.handlers[#themes] = (_) async {
        page++;
        return (themes: [theme], nextCursor: 'meer');
      };
      await signIn();
      final all = await notifier.organizationThemes('org');
      expect(page, 5, reason: 'een eindeloze cursor mag niet eindeloos laden');
      expect(all, hasLength(5));
      expect(() => all.add(theme), throwsUnsupportedError);
    });

    test('stopt zodra er geen volgende pagina is', () async {
      api.handlers[#themes] = (_) async => (themes: [theme], nextCursor: null);
      await signIn();
      expect(await notifier.organizationThemes('org'), hasLength(1));
      expect(api.calls.where((c) => c == #themes), hasLength(1));
    });

    test('één thema komt met zijn ETag', () async {
      api.handlers[#theme] = (_) async => (theme: theme, etag: '"v7"');
      await signIn();
      final r = await notifier.organizationTheme(
        organizationId: 'org',
        themeId: 't1',
      );
      expect(r.etag, '"v7"');
    });

    test('delen stuurt een idempotentiesleutel mee', () async {
      api.handlers[#createTheme] = (_) async => theme;
      await signIn();
      final made = await notifier.shareTheme(
        organizationId: 'org',
        name: 'Huisstijl',
        definition: const {'a': 1},
      );
      expect(made.id, 't1');
      expect(api.arg(#createTheme, #idempotencyKey), isA<String>());
    });

    test(
      'bijwerken geeft If-Match door, verwijderen alleen het thema',
      () async {
        api.handlers[#updateTheme] = (_) async => (theme: theme, etag: '"v8"');
        api.handlers[#deleteTheme] = (_) async => null;
        await signIn();
        final r = await notifier.updateOrganizationTheme(
          organizationId: 'org',
          themeId: 't1',
          name: 'Nieuw',
          definition: const {'b': 2},
          ifMatch: '*',
        );
        expect(r.etag, '"v8"');
        expect(api.arg(#updateTheme, #ifMatch), '*');
        await notifier.deleteOrganizationTheme(
          organizationId: 'org',
          themeId: 't1',
        );
        expect(api.arg(#deleteTheme, #themeId), 't1');
      },
    );

    test('een vreemde organisatie raakt de gateway niet', () async {
      await signIn();
      await expectLater(
        notifier.organizationThemes('vreemd'),
        throwsA(isA<OciServeException>()),
      );
      expect(api.calls, isNot(contains(#themes)));
    });
  });

  group('vaardigheden en badge-leesmodel (#2422)', () {
    OciServeBadgeReadiness readiness(String skill) => OciServeBadgeReadiness(
      skillId: skill,
      skillTitle: 'Titel $skill',
      requirements: const [],
      ready: true,
    );

    test('het leesmodel van één badge gaat rechtstreeks door', () async {
      api.handlers[#badgeReadiness] = (i) async =>
          readiness(i.namedArguments[#skillId] as String);
      await signIn();
      final r = await notifier.badgeReadiness(
        organizationId: 'org',
        participantId: 'p',
        skillId: 's1',
      );
      expect(r.skillId, 's1');
    });

    test(
      'zonder versies is er niets te vragen en de gateway blijft stil',
      () async {
        await signIn();
        final r = await notifier.badgeReadinessByVersion(
          organizationId: 'org',
          participantId: 'p',
          skillVersionIds: const {},
        );
        expect(r, isEmpty);
        expect(api.calls, isNot(contains(#organizationSkills)));
      },
    );

    test(
      'vertaalt skill_version_id naar het leesmodel van zijn vaardigheid',
      () async {
        api.handlers[#organizationSkills] = (_) async => const [
          OciServeSkill(id: 's1', title: 'Een'),
          OciServeSkill(id: 's2', title: 'Twee'),
        ];
        api.handlers[#skillVersions] = (i) async =>
            i.namedArguments[#skillId] == 's1'
            ? const [OciServeSkillVersion(id: 'v1')]
            : const [OciServeSkillVersion(id: 'v2')];
        api.handlers[#badgeReadiness] = (i) async =>
            readiness(i.namedArguments[#skillId] as String);
        await signIn();
        final r = await notifier.badgeReadinessByVersion(
          organizationId: 'org',
          participantId: 'p',
          skillVersionIds: const {'v1', 'v2', 'onbekend'},
        );
        expect(r.keys, {
          'v1',
          'v2',
        }, reason: 'een onbekende versie levert niets op');
        expect(r['v2']!.skillId, 's2');
      },
    );

    test(
      'een onleesbare versielijst of badge neemt de rest niet mee',
      () async {
        api.handlers[#organizationSkills] = (_) async => const [
          OciServeSkill(id: 's1', title: 'Een'),
          OciServeSkill(id: 's2', title: 'Twee'),
        ];
        api.handlers[#skillVersions] = (i) async {
          if (i.namedArguments[#skillId] == 's1') {
            throw const OciServeException('kapot', statusCode: 500);
          }
          return const [OciServeSkillVersion(id: 'v2')];
        };
        api.handlers[#badgeReadiness] = (_) async =>
            throw const OciServeException('kapot', statusCode: 500);
        await signIn();
        final r = await notifier.badgeReadinessByVersion(
          organizationId: 'org',
          participantId: 'p',
          skillVersionIds: const {'v1', 'v2'},
        );
        expect(
          r,
          isEmpty,
          reason: 'geen leesmodel is eerlijker dan een verzonnen',
        );
      },
    );
  });

  group('account (#2428)', () {
    test('een interactieve aanmelding wordt één keer geregistreerd', () async {
      await signIn();
      expect(api.calls.where((c) => c == #reportOciDeckLogin), hasLength(1));
    });

    test(
      'een mislukte aanmeldregistratie vertraagt de aanmelding niet',
      () async {
        api.handlers[#reportOciDeckLogin] = (_) async =>
            throw const OciServeException('audit', statusCode: 503);
        await signIn();
        expect(container.read(ociServeProvider).authenticated, isTrue);
      },
    );

    test('een profielfoto vervangen ververst het account', () async {
      var meCalls = 0;
      api.handlers[#me] = (_) async {
        meCalls++;
        return ociserveTestAccount;
      };
      api.handlers[#replaceAccountAvatar] = (_) async => 'hash-1';
      api.handlers[#removeAccountAvatar] = (_) async => null;
      await signIn();
      final before = meCalls;
      await notifier.replaceAccountAvatar(
        Uint8List.fromList([1, 2, 3]),
        'image/png',
      );
      expect(api.arg(#replaceAccountAvatar, #contentType), 'image/png');
      expect(meCalls, before + 1);
      await notifier.removeAccountAvatar();
      expect(api.calls, contains(#removeAccountAvatar));
      expect(meCalls, before + 2);
    });
  });

  group('agenda-abonnement (#2427)', () {
    test('de feed-URL wordt nooit bewaard, alleen de verloopdatum', () async {
      final expires = DateTime.utc(2027, 1, 1);
      api.handlers[#issueCalendarSubscription] = (_) async => (
        feedUrl: Uri.parse('https://learn.example/feed/geheim'),
        expiresAt: expires,
      );
      await signIn();
      expect(await notifier.calendarSubscriptionExpiry('org'), isNull);
      final r = await notifier.issueCalendarSubscription('org');
      expect(r.feedUrl.path, '/feed/geheim');
      expect(await notifier.calendarSubscriptionExpiry('org'), expires);

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getKeys().map((k) => prefs.get(k).toString());
      expect(
        stored.any((v) => v.contains('geheim')),
        isFalse,
        reason: 'kwijt is kwijt: de URL staat nergens op schijf',
      );
    });

    test(
      'intrekken wist de verloopdatum, ook als de server 404 zegt',
      () async {
        api.handlers[#issueCalendarSubscription] = (_) async => (
          feedUrl: Uri.parse('https://learn.example/feed/x'),
          expiresAt: DateTime.utc(2027, 1, 1),
        );
        api.handlers[#revokeCalendarSubscription] = (_) async =>
            throw const OciServeException('weg', statusCode: 404);
        await signIn();
        await notifier.issueCalendarSubscription('org');
        await notifier.revokeCalendarSubscription('org');
        expect(await notifier.calendarSubscriptionExpiry('org'), isNull);
      },
    );

    test(
      'een andere serverfout bij intrekken blijft een fout en laat de datum staan',
      () async {
        api.handlers[#issueCalendarSubscription] = (_) async => (
          feedUrl: Uri.parse('https://learn.example/feed/x'),
          expiresAt: DateTime.utc(2027, 1, 1),
        );
        api.handlers[#revokeCalendarSubscription] = (_) async =>
            throw const OciServeException('stuk', statusCode: 500);
        await signIn();
        await notifier.issueCalendarSubscription('org');
        await expectLater(
          notifier.revokeCalendarSubscription('org'),
          throwsA(isA<OciServeException>()),
        );
        expect(await notifier.calendarSubscriptionExpiry('org'), isNotNull);
      },
    );
  });
}
