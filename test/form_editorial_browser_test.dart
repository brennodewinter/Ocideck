import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/form/form_intake_snapshot.dart';
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
            'version': 1,
            'accepting': true,
            'operational_status': 'open',
            'snapshot': buildIntakeSnapshot(
              markdown: _markdown,
              title: 'Kookboek',
              purposes: ['recept'],
              privacyText: 'Een jaar bewaren.',
              retentionDraftDays: 30,
              retentionSubmittedDays: 365,
              correctionAllowed: true,
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
              'reason_for_submitter': 'Voeg de bereiding toe.',
            },
            {
              'submission_id': 'two',
              'title': 'Recept dat online staat',
              'revision': 2,
              'editorial_status': 'published',
              'public_article_url': 'https://public.example.nl/recept/indo',
            },
          ],
          'next_cursor': '',
        });
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
              onOpenText: (_, _) {},
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
      expect(find.text('Geweigerd'), findsOneWidget);
      expect(find.text('Voeg de bereiding toe.'), findsOneWidget);
      expect(find.text('Wijziging indienen'), findsOneWidget);
      expect(
        find.text('https://public.example.nl/recept/indo'),
        findsOneWidget,
      );
      expect(transport.routes, [
        'GET /api/v1/intake/forms/ref',
        'POST /api/v1/intake/challenges',
        'POST /api/v1/intake/challenges/challenge/verify',
        'GET /api/v1/intake/own',
      ]);
    },
  );
}
