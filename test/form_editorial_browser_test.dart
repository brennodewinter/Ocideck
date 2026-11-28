@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/ociserve_intake.dart';
import 'package:ocideck/services/form/form_intake_snapshot.dart';
import 'package:ocideck/services/form/form_intake_context.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';
import 'package:ocideck/services/ociserve/ociserve_intake_respondent.dart';
import 'package:ocideck/widgets/forms/form_intake_invitation_dialog.dart';

import 'support/pump_until.dart';

const _markdown = '''<!-- form id=recept version=1 lang=nl -->
# Recept
<!-- field id=gerecht type=text required -->
**Gerecht**
<!-- answer -->
<!-- /field id=gerecht -->
''';

final _filled = _markdown.replaceFirst(
  '<!-- answer -->',
  '<!-- answer -->\nNasi goreng',
);

IntakeFormSnapshot _snapshot({String markdown = _markdown}) =>
    buildIntakeSnapshot(
      markdown: markdown,
      title: 'Kookboek',
      purposes: ['recept'],
      privacyText: 'Een jaar bewaren.',
      retentionDraftDays: 30,
      retentionSubmittedDays: 365,
      correctionAllowed: true,
    );

class _EditorialTransport implements OciServeHttpTransport {
  final routes = <String>[];

  @override
  Future<OciServeHttpResponse> send({
    required String method,
    required Uri url,
    required bool trustedInternal,
    Map<String, String> headers = const {},
    List<int>? body,
    int maxResponseBytes = 0,
    Duration timeout = Duration.zero,
  }) async {
    expect(url.origin, 'https://serve.example.nl');
    routes.add('$method ${url.path}');
    switch (url.path) {
      case '/api/v1/intake/forms/ref':
        expect(headers['authorization'], isNull);
        return _json(
          {
            'form_ref': 'ref',
            'version': 2,
            'accepting': true,
            'operational_status': 'open',
            'snapshot': _snapshot(
              markdown: _markdown.replaceFirst('version=1', 'version=2'),
            ).toJson(),
          },
          headers: {'x-ociserve-editorial': 'true', 'etag': '"${'a' * 64}"'},
        );
      case '/api/v1/intake/challenges':
        expect(jsonDecode(utf8.decode(body!)), {
          'purpose': 'history',
          'form_ref': 'ref',
          'email': 'auteur@example.nl',
        });
        return _json({
          'challenge_id': 'challenge',
          'expires_in': 600,
          'resend_after': 0,
        }, status: 202);
      case '/api/v1/intake/challenges/challenge/verify':
        expect(jsonDecode(utf8.decode(body!)), {'code': '258469'});
        return _json({
          'grant': 'mailbox-proof',
          'expires_in': 600,
          'purpose': 'history',
          'locator': '',
          'form_ref': 'ref',
        });
      case '/api/v1/intake/own':
        expect(headers['authorization'], 'Bearer mailbox-proof');
        return _json({
          'items': [
            {
              'submission_id': 'one',
              'title': 'Recept dat opnieuw kan',
              'revision': 1,
              'editorial_status': 'rejected',
              'submitted_at': '2026-11-26T12:00:00Z',
              'reason_for_submitter': 'Voeg de bereiding toe.',
            },
            {
              'submission_id': 'two',
              'title': 'Recept dat online staat',
              'revision': 2,
              'editorial_status': 'published',
              'submitted_at': '2026-11-27T13:00:00Z',
              'public_article_url': 'https://public.example.nl/recept/indo',
            },
            {
              'submission_id': 'three',
              'title': 'Recept in behandeling',
              'revision': 1,
              'editorial_status': 'submitted',
              'submitted_at': '2026-11-27T14:00:00Z',
            },
            {
              'submission_id': 'four',
              'title': 'Goedgekeurd recept',
              'revision': 1,
              'editorial_status': 'approved',
              'submitted_at': '2026-11-27T15:00:00Z',
            },
          ],
          'next_cursor': '',
        });
      case '/api/v1/intake/own/one':
        expect(headers['authorization'], 'Bearer mailbox-proof');
        return _json({
          'snapshot': _snapshot().toJson(),
          'revision': 1,
          'form_sha256': 'a' * 64,
        });
      case '/api/v1/intake/own/one/content':
        expect(headers['if-match'], '"1"');
        expect(headers['authorization'], 'Bearer mailbox-proof');
        final form = parseForm(_markdown) as ParsedForm;
        return OciServeHttpResponse(
          statusCode: 200,
          body: buildFormPackage(
            submission: _filled,
            template: _markdown,
            spec: form.spec,
            images: const {},
            submissionId: 'a' * 26,
            created: DateTime.utc(2026, 11, 27),
            clientRules: form.spec.rules,
          ),
          headers: {'content-type': 'application/octet-stream'},
        );
      case '/api/v1/intake/own/one/revision-grant':
        expect(headers['authorization'], 'Bearer mailbox-proof');
        expect(jsonDecode(utf8.decode(body!)), {'revision': 1});
        return _json({
          'grant': 'revision-proof',
          'expires_in': 600,
          'purpose': 'revise',
          'locator': 'existing',
          'form_ref': 'ref',
          'state': 'submitted',
        }, status: 201);
    }
    throw StateError('Onverwacht pad: ${url.path}');
  }
}

OciServeHttpResponse _json(
  Object value, {
  int status = 200,
  Map<String, String> headers = const {},
}) => OciServeHttpResponse(
  statusCode: status,
  body: Uint8List.fromList(utf8.encode(jsonEncode(value))),
  headers: headers,
);

void main() {
  testWidgets(
    'browserlink geeft na mailboxcode toegang tot de eigen revisies',
    (tester) async {
      final transport = _EditorialTransport();
      FormIntakeSession? editing;
      String? openedText;
      await tester.binding.setSurfaceSize(const Size(1050, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('nl'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: FormIntakeInvitationDialog(
              clientFor: (origin) =>
                  IntakeRespondentClient(baseUrl: origin, transport: transport),
              onOpenPath: (_) async {},
              onOpenText: (text, session) {
                editing = session;
                openedText = text;
              },
              initialLink: 'https://serve.example.nl/api/v1/intake/forms/ref',
            ),
          ),
        ),
      );
      await pumpUntil(
        tester,
        () => find.text('Mijn inzendingen').evaluate().isNotEmpty,
      );
      expect(find.text('Recept dat opnieuw kan'), findsNothing);
      await tester.tap(find.text('Mijn inzendingen'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Je e-mailadres'),
        'auteur@example.nl',
      );
      await tester.tap(find.text('Code aanvragen'));
      await pumpUntil(
        tester,
        () => find.text('Code controleren').evaluate().isNotEmpty,
      );
      expect(find.text('Recept dat opnieuw kan'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Code uit de e-mail'),
        '258469',
      );
      await tester.tap(find.text('Code controleren'));
      await pumpUntil(
        tester,
        () => find.text('Gepubliceerd').evaluate().isNotEmpty,
      );
      expect(find.text('Kookboek'), findsOneWidget);
      expect(find.text('Bestemming: https://serve.example.nl'), findsOneWidget);
      expect(find.textContaining('Ontvangen '), findsNWidgets(4));
      for (final status in [
        'Ingediend',
        'Goedgekeurd',
        'Gepubliceerd',
        'Geweigerd',
      ]) {
        expect(find.text(status), findsOneWidget);
      }
      expect(find.text('Voeg de bereiding toe.'), findsOneWidget);
      expect(find.text('Wijziging indienen'), findsNWidgets(3));
      expect(
        find.descendant(
          of: find.widgetWithText(Card, 'Recept dat online staat'),
          matching: find.text('Wijziging indienen'),
        ),
        findsNothing,
      );
      expect(
        find.text('https://public.example.nl/recept/indo'),
        findsOneWidget,
      );
      final reviseRejected = find.descendant(
        of: find.widgetWithText(Card, 'Recept dat opnieuw kan'),
        matching: find.text('Wijziging indienen'),
      );
      await tester.ensureVisible(reviseRejected);
      await tester.tap(reviseRejected);
      await pumpUntil(tester, () => editing != null);
      expect(openedText, _filled);
      expect(editing!.publishedMarkdown, _markdown);
      expect(editing!.context.revision, 1);
      expect(editing!.context.locator, 'existing');
      expect(editing!.revisionGrant?.token, 'revision-proof');
      expect(transport.routes, [
        'GET /api/v1/intake/forms/ref',
        'POST /api/v1/intake/challenges',
        'POST /api/v1/intake/challenges/challenge/verify',
        'GET /api/v1/intake/own',
        'GET /api/v1/intake/own/one',
        'GET /api/v1/intake/own/one/content',
        'POST /api/v1/intake/own/one/revision-grant',
      ]);
    },
  );
}
