import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/dialogs/choice_picker.dart';
import 'package:ocideck/widgets/dialogs/export_dialog.dart';
import 'package:ocideck/widgets/dialogs/package_encrypt_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Het gegroepeerde …-menu (issue #2359): één "Exporteren…" en één
/// "Importeren…" als hoofdacties, met de formaat- en bronkeuze als tweede
/// stap in een [ChoicePicker]. De losse pakket-, URL- en importregels hoorden
/// daar te verdwijnen — zonder dat een afhandelroute verandert.
///
/// Wat hier bewezen wordt: de twee ingangen staan er precies één keer, de
/// keuzelijsten tonen álles wat beschikbaar is (inclusief de module-gate voor
/// presentatie-import), en PDF en `.ocideck` lopen naar hun eigen bestaande
/// afhandeling — het exportdialoog respectievelijk het wachtwoorddialoog van
/// de pakketroute.
void main() {
  late _RecordingFileService fileService;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    fileService = _RecordingFileService();
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  });

  Finder appBarIcon(IconData icon) =>
      find.descendant(of: find.byType(AppBar), matching: find.byIcon(icon));

  /// Tekst die in een menu-regel staat — bewust binnen [PopupMenuItem] gezocht:
  /// dezelfde tekst mag elders (statusbalk, palet) voorkomen.
  Finder menuText(String text) => find.descendant(
    of: find.byWidgetPredicate((w) => w is PopupMenuItem),
    matching: find.text(text),
  );

  /// Tekst binnen het keuzevenster (een [AlertDialog] met [ListTile]-rijen).
  Finder pickerText(String text) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

  /// Pompt de app met een geladen deck en opent het ⋮-overloopmenu.
  Future<void> openMenu(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [fileServiceProvider.overrideWithValue(fileService)],
        child: const OciDeckApp(),
      ),
    );
    await tester.pumpAndSettle();
    ProviderScope.containerOf(tester.element(find.byType(AppShell)))
        .read(tabsProvider)
        .current!
        .deckNotifier
        .loadDeck(
          Deck(
            title: 'Testrapport',
            slides: [
              Slide.create(SlideType.title).copyWith(title: 'Testrapport'),
            ],
          ),
        );
    await tester.pumpAndSettle();

    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();
  }

  Future<void> openPicker(WidgetTester tester, String menuLabel) async {
    await tester.tap(menuText(menuLabel));
    await tester.pumpAndSettle();
  }

  testWidgets('het ⋮-menu toont precies één import- en één exportingang', (
    tester,
  ) async {
    await openMenu(tester);

    expect(menuText('Exporteren…'), findsOneWidget);
    expect(menuText('Importeren…'), findsOneWidget);

    // De losse regels die dit menu langer maakten dan nodig zijn weg; ze
    // leven voort als keuzes in de tweede stap.
    expect(menuText('Pakket exporteren…'), findsNothing);
    expect(menuText('Pakket importeren…'), findsNothing);
    expect(menuText('Importeren via URL…'), findsNothing);
    expect(menuText('Presentaties importeren…'), findsNothing);
  });

  testWidgets('de formaatkeuze toont alle zes doelen', (tester) async {
    await openMenu(tester);
    await openPicker(tester, 'Exporteren…');

    expect(find.byType(ChoicePicker<ExportTarget>), findsOneWidget);
    expect(pickerText('PDF (plaatje per dia)'), findsOneWidget);
    expect(pickerText('PowerPoint'), findsOneWidget);
    expect(pickerText('OpenDocument-presentatie'), findsOneWidget);
    expect(pickerText('HTML-bestand (werkt offline)'), findsOneWidget);
    expect(pickerText('LaTeX-bron'), findsOneWidget);
    expect(pickerText('OciDeck-pakket (.ocideck)'), findsOneWidget);
  });

  testWidgets('een documentformaat opent het bestaande exportdialoog', (
    tester,
  ) async {
    await openMenu(tester);
    await openPicker(tester, 'Exporteren…');
    await tester.tap(pickerText('PDF (plaatje per dia)'));
    await tester.pumpAndSettle();

    expect(
      find.byType(ExportDialog),
      findsOneWidget,
      reason: 'PDF hoort in de document-exportroute uit te komen',
    );
    // De keuze komt zichtbaar mee: de PDF-knop is de hoofdactie, de rest
    // blijft wisselbaar.
    expect(
      find.widgetWithText(FilledButton, 'PDF (plaatje per dia)'),
      findsOneWidget,
      reason: 'de gekozen keuze hoort als hoofdactie terug in het dialoog',
    );
    expect(find.widgetWithText(OutlinedButton, 'PowerPoint'), findsOneWidget);
  });

  testWidgets('het pakket gaat naar zijn eigen route met encryptie-dialoog', (
    tester,
  ) async {
    await openMenu(tester);
    await openPicker(tester, 'Exporteren…');
    await tester.tap(pickerText('OciDeck-pakket (.ocideck)'));
    await tester.pumpAndSettle();

    expect(
      find.byType(PackageEncryptDialog),
      findsOneWidget,
      reason:
          '.ocideck hoort in de pakketroute uit te komen, niet in het '
          'document-exportdialoog',
    );
    expect(find.byType(ExportDialog), findsNothing);
  });

  testWidgets('de bronkiezer toont pakket en URL, en volgt de modulepoort', (
    tester,
  ) async {
    await openMenu(tester);
    await openPicker(tester, 'Importeren…');

    expect(find.byType(ChoicePicker<String>), findsOneWidget);
    expect(pickerText('Pakket importeren…'), findsOneWidget);
    expect(pickerText('Importeren via URL…'), findsOneWidget);
    // Module "Importeren" staat uit: de presentatie-import hoort dan weg te
    // zijn, niet grijs (zelfde regel als in het oude menu).
    expect(pickerText('Presentaties importeren…'), findsNothing);
  });

  testWidgets('met de module aan verschijnt de presentatie-import', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'importModuleEnabled': true,
    });
    await openMenu(tester);
    await openPicker(tester, 'Importeren…');

    expect(pickerText('Presentaties importeren…'), findsOneWidget);
  });

  testWidgets('pakket-import roept de bestaande pakket-route aan', (
    tester,
  ) async {
    await openMenu(tester);
    await openPicker(tester, 'Importeren…');
    await tester.tap(pickerText('Pakket importeren…'));
    await tester.pumpAndSettle();

    expect(
      fileService.packagePicks,
      1,
      reason: 'de pakket-keuze moet bij de bestaande importroute uitkomen',
    );
  });

  testWidgets('URL-import opent het bestaande invoervenster', (tester) async {
    await openMenu(tester);
    await openPicker(tester, 'Importeren…');
    await tester.tap(pickerText('Importeren via URL…'));
    await tester.pumpAndSettle();

    expect(find.text('Importeren via URL'), findsOneWidget);
  });
}

/// Een [FileService] die registreert dat de pakketkiezer gevraagd werd —
/// onder `flutter test` is er geen systeemkiezer om iets uit te kiezen, dus
/// het bewijs dat de importroute liep is de aanroep zelf.
class _RecordingFileService extends FileService {
  _RecordingFileService()
    : super(MarkdownService(), ImageService(), () => const ThemeProfile());

  var packagePicks = 0;

  @override
  Future<String?> pickPackageFile({String? initialDirectory}) async {
    packagePicks++;
    return null;
  }
}
