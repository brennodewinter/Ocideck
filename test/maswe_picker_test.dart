import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/maswe_weakness.dart';
import 'package:ocideck/services/maswe_catalog.dart';
import 'package:ocideck/widgets/dialogs/maswe_picker.dart';

/// De MASWE-kiezer, tegenhanger van [CwePicker] voor mobiel. De ordening is
/// hier geen opsmuk: driekwart van MASWE is bij de bron nog een concept, en een
/// tester die daar blind uit kiest belandt op een lege uitlegpagina zonder te
/// begrijpen waarom. Uitgeschreven zwakheden horen dus bovenaan te staan en de
/// rest hoort gemarkeerd te zijn.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  /// Opent de kiezer en houdt vast wat hij teruggaf.
  Future<List<MasweWeakness?>> open(WidgetTester tester) async {
    final gekozen = <MasweWeakness?>[];
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async =>
                  gekozen.add(await MaswePicker.show(context)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(MaswePicker), findsOneWidget);
    return gekozen;
  }

  Future<void> zoek(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pump();
  }

  /// De titels in de lijst, in de volgorde waarin ze staan.
  List<String> zichtbareTitels(WidgetTester tester) => tester
      .widgetList<ListTile>(find.byType(ListTile))
      .map((t) => (t.title! as Text).data!)
      .toList();

  testWidgets('zonder zoekterm staat de hele lijst er, concepten onderaan', (
    tester,
  ) async {
    await open(tester);

    final catalogus = MasweCatalog.instance.weaknesses;
    expect(
      catalogus.where((w) => !w.isPlaceholder),
      isNotEmpty,
      reason: 'zonder uitgeschreven zwakheid zegt de ordening niets',
    );
    expect(catalogus.where((w) => w.isPlaceholder), isNotEmpty);

    // De eerste zichtbare regel hoort een uitgeschreven zwakheid te zijn.
    final eerste = zichtbareTitels(tester).first;
    final eersteId = eerste.split(' — ').first;
    expect(
      catalogus.firstWhere((w) => w.id == eersteId).isPlaceholder,
      isFalse,
      reason: 'een concept mag niet bovenaan de lijst staan',
    );
  });

  testWidgets('een concept draagt zichtbaar dat de uitleg nog ontbreekt', (
    tester,
  ) async {
    await open(tester);
    final concept = MasweCatalog.instance.weaknesses.firstWhere(
      (w) => w.isPlaceholder,
    );

    await zoek(tester, concept.id);

    expect(find.textContaining('${concept.id} — '), findsOneWidget);
    expect(
      find.textContaining('uitleg nog niet geschreven'),
      findsOneWidget,
      reason: 'wie dit kiest moet weten dat de uitlegpagina leeg is',
    );
  });

  testWidgets('een uitgeschreven zwakheid draagt die markering niet', (
    tester,
  ) async {
    await open(tester);
    final echt = MasweCatalog.instance.weaknesses.firstWhere(
      (w) => !w.isPlaceholder,
    );

    await zoek(tester, echt.id);

    expect(find.textContaining('${echt.id} — '), findsOneWidget);
    expect(find.textContaining('uitleg nog niet geschreven'), findsNothing);
  });

  testWidgets('zoeken werkt op id, titel én categorie', (tester) async {
    await open(tester);
    final w = MasweCatalog.instance.weaknesses.firstWhere(
      (w) => w.title.trim().isNotEmpty && w.category.trim().isNotEmpty,
    );

    await zoek(tester, w.id.toLowerCase());
    expect(zichtbareTitels(tester), contains('${w.id} — ${w.title}'));

    // Op categorie: alles wat overblijft hoort in die categorie te zitten.
    await zoek(tester, w.category.toLowerCase());
    final ids = zichtbareTitels(tester).map((t) => t.split(' — ').first);
    expect(ids, isNotEmpty);
    for (final id in ids) {
      final gevonden = MasweCatalog.instance.weaknesses.firstWhere(
        (x) => x.id == id,
      );
      final q = w.category.toLowerCase();
      expect(
        gevonden.id.toLowerCase().contains(q) ||
            gevonden.title.toLowerCase().contains(q) ||
            gevonden.category.toLowerCase().contains(q),
        isTrue,
        reason: '$id hoort niet bij zoekterm "${w.category}"',
      );
    }
  });

  testWidgets('een zoekterm zonder treffer zegt dat, en toont geen lijst', (
    tester,
  ) async {
    await open(tester);

    await zoek(tester, 'ditbestaatnietxyzzy');

    expect(find.text('Geen zwakheid gevonden'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('een tik op een regel geeft die zwakheid terug', (tester) async {
    final gekozen = await open(tester);
    final w = MasweCatalog.instance.weaknesses.firstWhere(
      (w) => !w.isPlaceholder,
    );

    await zoek(tester, w.id);
    await tester.tap(find.text('${w.id} — ${w.title}'));
    await tester.pumpAndSettle();

    expect(gekozen.single?.id, w.id);
    expect(find.byType(MaswePicker), findsNothing);
  });

  testWidgets('annuleren geeft niets terug', (tester) async {
    final gekozen = await open(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
    await tester.pumpAndSettle();

    expect(gekozen, [null]);
  });
}
