import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/maswe_weakness.dart';
import 'package:ocideck/services/maswe_catalog.dart';
import 'package:ocideck/widgets/dialogs/maswe_picker.dart';

/// De MASWE-kiezer, tegenhanger van [CwePicker] voor mobiel. Sinds de herbouw
/// van MASWE zijn alle 78 zwakheden uitgeschreven; de lijst staat simpelweg op
/// id-volgorde en er is geen concept-markering meer.
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

  testWidgets('zonder zoekterm staat de hele lijst er, op id-volgorde', (
    tester,
  ) async {
    await open(tester);

    final catalogus = MasweCatalog.instance.weaknesses;
    expect(catalogus, isNotEmpty);

    final zichtbareIds = zichtbareTitels(
      tester,
    ).map((t) => t.split(' — ').first).toList();
    // De zichtbare regels horen op oplopend id te staan, koppend op de eerste.
    expect(zichtbareIds, orderedEquals([...zichtbareIds]..sort()));
    expect(zichtbareIds.first, catalogus.first.id);
  });

  testWidgets('een regel toont id, titel, categorie en CWE', (tester) async {
    await open(tester);
    final w = MasweCatalog.instance.weaknesses.firstWhere(
      (w) => w.cweIds.isNotEmpty,
    );

    await zoek(tester, w.id);

    expect(find.text('${w.id} — ${w.title}'), findsOneWidget);
    expect(find.textContaining(w.category), findsOneWidget);
    expect(find.textContaining('CWE-${w.cweIds.first}'), findsOneWidget);
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
    final w = MasweCatalog.instance.weaknesses.first;

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
