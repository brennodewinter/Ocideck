import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/cve_hit.dart';
import 'package:ocideck/services/cve_search_service.dart';
import 'package:ocideck/widgets/dialogs/cve_picker.dart';
import 'package:ocideck/models/local_cve_status.dart';
import 'package:ocideck/state/local_cve_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De belofte van de lokale database is niet "sneller" maar "stil": met de lijst
/// op je apparaat mag er geen zoekterm meer naar buiten. Deze test bewaakt
/// precies dat — inclusief het geval waarin lokaal niets gevonden wordt, want
/// juist dán is de verleiding om "even online te kijken" het grootst, en juist
/// dán zou dat de zoekterm lekken die je lokaal wilde houden.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Opent de picker met een lokale database die [localHits] teruggeeft, en met
  /// [service] als de online keten — die hoort ongemoeid te blijven.
  Future<void> openPicker(
    WidgetTester tester, {
    required List<CveHit> localHits,
    required CveSearchService service,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localCveAvailableProvider.overrideWithValue(true),
          localCveProvider.overrideWith(() => _FakeLocalCveNotifier(localHits)),
        ],
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => CvePicker.show(context, service: service),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('with a local database, searching never touches the network', (
    tester,
  ) async {
    final online = _SpyService();

    await openPicker(
      tester,
      localHits: const [CveHit(id: 'CVE-2021-44228', description: 'Log4Shell')],
      service: online,
    );

    await tester.enterText(find.byType(TextField).first, 'log4j');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.textContaining('CVE-2021-44228'), findsWidgets);
    expect(
      online.queries,
      isEmpty,
      reason: 'de online keten is geraadpleegd terwijl de lijst lokaal lag',
    );
  });

  testWidgets('a local miss does not fall back online and leak the term', (
    tester,
  ) async {
    final online = _SpyService();

    await openPicker(tester, localHits: const [], service: online);

    await tester.enterText(find.byType(TextField).first, 'iets-geheims');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      online.queries,
      isEmpty,
      reason:
          'een lokale misser mag de zoekterm niet alsnog naar buiten sturen',
    );
  });
}

/// Onthoudt of hij geraadpleegd is. Een echte netwerkbeweging is in een test
/// niet te zien; wél of we hem überhaupt gevraagd hebben — en dat is precies de
/// vraag: is de zoekterm het apparaat uit gegaan?
class _SpyService extends CveSearchService {
  _SpyService() : super(const []);

  final queries = <String>[];

  @override
  Future<CveSearchResult> search(String query) async {
    queries.add(query);
    return const CveSearchResult.ok([]);
  }
}

class _FakeLocalCveNotifier extends LocalCveNotifier {
  _FakeLocalCveNotifier(this._hits);
  final List<CveHit> _hits;

  @override
  LocalCveState build() => LocalCveState(
    loading: false,
    stats: const LocalCveStats(
      release: 'cve_2026',
      builtOn: '2026-07-14',
      records: 312456,
      bytes: 280 * 1024 * 1024,
    ),
  );

  @override
  Future<List<CveHit>> search(String query) async => _hits;
}
