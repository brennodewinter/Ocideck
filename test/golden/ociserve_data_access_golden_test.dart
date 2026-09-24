@Tags(['golden'])
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/ociserve_models.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/dialogs/ociserve_data_access.dart';

const _surfaceKey = ValueKey('ociserve-data-access-golden-surface');

Future<void> _match(
  WidgetTester tester, {
  required String name,
  required bool dark,
  Locale locale = const Locale('nl'),
  TextScaler textScaler = TextScaler.noScaling,
  String? expandCategory,
}) async {
  const size = Size(920, 760);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final baseTheme = AppTheme.fromProfile(
    dark ? AppAppearanceProfile.dark : AppAppearanceProfile.basic,
  );
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        textTheme: baseTheme.textTheme.apply(fontFamily: 'Ahem'),
      ),
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(
          size: size,
          disableAnimations: true,
        ).copyWith(textScaler: textScaler),
        child: Scaffold(
          body: RepaintBoundary(
            key: _surfaceKey,
            child: ColoredBox(
              color: baseTheme.colorScheme.surface,
              child: OciServeDataAccess(
                organizationName: 'Voorbeeldorganisatie',
                data: OciServePrivacyData(
                  participantId: '00000000-0000-0000-0000-000000000001',
                  generatedAt: DateTime.utc(2026, 9, 9),
                  data: const {
                    'participant': {
                      'display_name': 'Voorbeeldcursist',
                      'created_at': '2026-01-01T09:00:00Z',
                    },
                    'lesson_progress': [
                      {'completed_at': '2026-02-03T12:00:00Z'},
                    ],
                    'participant_data_access_history_metadata': {
                      'available_from': '2026-09-01T08:30:00Z',
                      'earlier_history': 'not_available',
                    },
                    'participant_data_access_history': [
                      {
                        'time': '2026-09-09T10:15:00Z',
                        'retain_until': '2027-09-09T10:15:00Z',
                        'operation': 'viewed',
                        'data_category': 'learning_statistics',
                        'purpose': 'assessment_and_certification',
                        'actor_type': 'staff',
                        'actor_role': 'assessor',
                      },
                    ],
                    'future_category': [],
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  if (expandCategory != null) {
    final group = find.byKey(
      Key('data-group-${_dataGroupFor(expandCategory)}'),
    );
    await tester.ensureVisible(group);
    await tester.drag(
      find
          .descendant(
            of: find.byKey(const Key('ociserve-data-access')),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    await tester.tap(group);
    await tester.pumpAndSettle();
    final category = find.byKey(Key('data-category-$expandCategory'));
    await tester.ensureVisible(category);
    await tester.pumpAndSettle();
    await tester.tap(category);
    await tester.pumpAndSettle();
  }
  await expectLater(
    find.byKey(_surfaceKey),
    matchesGoldenFile('goldens/$name.png'),
  );
}

String _dataGroupFor(String key) => switch (key) {
  'participant' || 'accounts' || 'memberships' => 'profile',
  'enrollments' ||
  'lesson_progress' ||
  'playback_sessions' ||
  'participations' ||
  'session_bookings' ||
  'requirement_waivers' ||
  'voucher_redemptions' => 'learning',
  'attempts' || 'attempt_items' || 'answers' => 'assessment',
  'evidence_uploads' ||
  'qualifications' ||
  'qualification_events' ||
  'pe_awards' ||
  'pe_award_events' ||
  'certificates' => 'results',
  'privacy_requests' ||
  'access_audit_events' ||
  'participant_data_access_history' ||
  'participant_data_access_history_metadata' ||
  'retention_policies' ||
  'deletion_ledger' => 'privacy',
  _ => 'other',
};

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('gegevensinzage licht toont alle categorieën', (tester) async {
    await _match(tester, name: 'ociserve_data_access_light', dark: false);
  });

  testWidgets('gegevensinzage donker toont begrijpelijk auditspoor', (
    tester,
  ) async {
    await _match(
      tester,
      name: 'ociserve_data_access_dark',
      dark: true,
      expandCategory: 'participant_data_access_history',
    );
  });
}
