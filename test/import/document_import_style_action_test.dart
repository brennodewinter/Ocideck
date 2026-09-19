// De stijlvraag na een documentimport (#2119), van bestand tot tabblad.
//
// De dialoog is de plek waar de keuze optioneel is: alleen tekst, een nieuw
// profiel, of het profiel dat deze huisstijl al is. Wat hier bewaakt wordt is
// dat élke route eindigt waar hij hoort — met of zonder `theme:` in het
// document, met of zonder nieuw profiel — en dat een document zonder
// huisstijl de vraag nooit krijgt.

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/import/imported_document_profile.dart';
import 'package:ocideck/services/import/models/source_document_style.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/utils/document_front_matter.dart';
import 'package:ocideck/widgets/dialogs/import_document_style_dialog.dart';
import 'package:ocideck/widgets/shell/document_import_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/docx_fixture.dart';
import 'helpers/docx_styled_fixture.dart';

String? _openDocumentSource(ProviderContainer container) {
  final content = container.read(tabsProvider).current?.content;
  return content is DocumentTabContent
      ? content.documentNotifier.currentState.document?.source
      : null;
}

void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
    // De echte schrijver vraagt de app-supportmap aan het platform, en dat
    // antwoord komt onder de fake-async-klok nooit; hier landt het logo in
    // de webopslag, met een herkenbaar pad.
    debugImportedDocumentLogoWriter = (bytes, {required profileName}) async =>
        WebAssetStore.put(bytes, name: '$profileName.png');
  });
  tearDown(() => debugImportedDocumentLogoWriter = null);

  Future<(ProviderContainer, BuildContext)> pump(WidgetTester tester) async {
    late BuildContext ctx;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ScaffoldMessenger(
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  ctx = context;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      ),
    );
    return (container, ctx);
  }

  /// Start de import en pompt tot de dialoog staat; de teruggegeven future
  /// is de import zelf, die pas afrondt als de dialoog gesloten is.
  Future<Future<void>> startImport(
    WidgetTester tester,
    BuildContext ctx,
    Uint8List bytes,
  ) async {
    final done = importDocument(
      ctx,
      fileOverride: (bytes: bytes, name: 'beleid.docx'),
    );
    await tester.pump();
    await tester.pump();
    return Future<Future<void>>.value(done);
  }

  testWidgets('een document zonder huisstijl krijgt de vraag niet', (
    tester,
  ) async {
    final (container, ctx) = await pump(tester);
    await importDocument(
      ctx,
      fileOverride: (bytes: docxFixture(), name: 'kaal.docx'),
    );
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(_openDocumentSource(container), contains('# Titel'));
    expect(documentStyleName(_openDocumentSource(container)!), isNull);
    container.dispose();
  });

  testWidgets('de dialoog toont letters, kleuren, logo en verliezen', (
    tester,
  ) async {
    final (container, ctx) = await pump(tester);
    final done = await startImport(
      tester,
      ctx,
      docxStyledFixture(defaultFooterLogo: fixtureLogoPng()),
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Aptos Light'), findsOneWidget);
    expect(find.textContaining('Calibri'), findsWidgets);
    expect(find.textContaining('#00464F'), findsWidgets);
    expect(find.textContaining('rechtsonder'), findsOneWidget);
    expect(find.textContaining('Information security policy'), findsOneWidget);
    expect(find.textContaining('Kopniveau 2'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('import-document-style-name')),
          )
          .controller!
          .text,
      'Stijl van Beleid',
    );
    await tester.tap(find.byKey(const Key('import-document-style-text-only')));
    await done;
    await tester.pump();
    container.dispose();
  });

  testWidgets('"Alleen tekst" opent het document zonder stijl', (tester) async {
    final (container, ctx) = await pump(tester);
    final before = container.read(settingsProvider).themeProfiles.length;
    final done = await startImport(tester, ctx, docxStyledFixture());
    await tester.tap(find.byKey(const Key('import-document-style-text-only')));
    await done;
    await tester.pump();

    final source = _openDocumentSource(container)!;
    expect(source, contains('# Beleid'));
    expect(documentStyleName(source), isNull);
    expect(container.read(settingsProvider).themeProfiles.length, before);
    container.dispose();
  });

  testWidgets('"Stijl overnemen" bewaart een profiel en zet theme:', (
    tester,
  ) async {
    final (container, ctx) = await pump(tester);
    final done = await startImport(
      tester,
      ctx,
      docxStyledFixture(defaultFooterLogo: fixtureLogoPng()),
    );
    await tester.enterText(
      find.byKey(const Key('import-document-style-name')),
      'NEO NL',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-document-style-new')));
    await done;
    await tester.pump();

    final source = _openDocumentSource(container)!;
    expect(documentStyleName(source), 'NEO NL');
    final profile = container
        .read(settingsProvider)
        .themeProfiles
        .singleWhere((p) => p.name == 'NEO NL');
    expect(profile.fontFamily, 'Calibri');
    expect(profile.preferredFontFamily, 'Aptos Light');
    expect(profile.preferredDocumentHeadingFontFamily, 'Aptos');
    expect(profile.documentHeadingColor, '#00464F');
    expect(profile.accentColor, '#00464F');
    expect(profile.textColor, '#000000');
    expect(profile.documentFooterText, 'Information security policy');
    expect(profile.documentShowPageNumbers, isTrue);
    expect(profile.documentLogoPosition, 'bottom-right');
    expect(profile.documentLogoSize, 34);
    // Onder `flutter test` is er geen app-supportmap, dus het logo landt in
    // de webopslag — maar het landt, en het profiel wijst ernaar.
    final logoPath = profile.effectiveDocumentLogoPath!;
    expect(WebAssetStore.isMemPath(logoPath), isTrue);
    expect(WebAssetStore.bytesFor(logoPath), fixtureLogoPng());
    container.dispose();
  });

  testWidgets('het logo-vinkje uit laat het logo weg', (tester) async {
    final (container, ctx) = await pump(tester);
    final done = await startImport(
      tester,
      ctx,
      docxStyledFixture(defaultFooterLogo: fixtureLogoPng()),
    );
    await tester.ensureVisible(
      find.byKey(const Key('import-document-style-logo')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-document-style-logo')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-document-style-new')));
    await done;
    await tester.pump();

    final profile = container
        .read(settingsProvider)
        .themeProfiles
        .singleWhere((p) => p.name == 'Stijl van Beleid');
    expect(profile.documentLogoPath, '');
    expect(profile.preferredFontFamily, 'Aptos Light');
    container.dispose();
  });

  testWidgets('een bestaand profiel wordt herkend en hergebruikt', (
    tester,
  ) async {
    final (container, ctx) = await pump(tester);
    // Het profiel dat een eerdere import van hetzelfde sjabloon maakte.
    final logo = fixtureLogoPng();
    final logoPath = WebAssetStore.put(logo, name: 'logo.png');
    final existing = buildImportedDocumentProfile(
      style: const SourceDocumentStyle(
        bodyFontFamily: 'Aptos Light',
        headingFontFamily: 'Aptos',
        textColor: '#000000',
        headingColor: '#00464F',
        accentColor: '#00464F',
        footerText: 'Information security policy',
        showPageNumbers: true,
      ),
      base: container.read(settingsProvider).themeProfile,
      name: 'Huisstijl NEO',
      logoPath: logoPath,
      logo: DocumentLogoCandidate(
        bytes: logo,
        ext: 'png',
        sha256: 'x',
        edge: DocumentLogoEdge.bottom,
        side: DocumentLogoSide.right,
        widthMm: 9,
        origin: DocumentLogoOrigin.footer,
      ),
    );
    await addThemeProfileWithoutSelection(
      container.read(settingsProvider.notifier),
      existing,
    );
    final before = container.read(settingsProvider).themeProfiles.length;

    final done = await startImport(
      tester,
      ctx,
      docxStyledFixture(defaultFooterLogo: logo),
    );
    expect(find.textContaining('Huisstijl NEO'), findsOneWidget);
    await tester.tap(find.byKey(const Key('import-document-style-existing')));
    await done;
    await tester.pump();

    expect(documentStyleName(_openDocumentSource(container)!), 'Huisstijl NEO');
    expect(container.read(settingsProvider).themeProfiles.length, before);
    container.dispose();
  });

  testWidgets('een ander logo is geen bestaand profiel', (tester) async {
    final (container, ctx) = await pump(tester);
    final other = buildImportedDocumentProfile(
      style: const SourceDocumentStyle(
        bodyFontFamily: 'Aptos Light',
        headingFontFamily: 'Aptos',
        textColor: '#000000',
        headingColor: '#00464F',
        accentColor: '#00464F',
        footerText: 'Information security policy',
        showPageNumbers: true,
      ),
      base: container.read(settingsProvider).themeProfile,
      name: 'Ander logo',
      logoPath: WebAssetStore.put(fixtureLogoPng(seed: 7), name: 'ander.png'),
      logo: DocumentLogoCandidate(
        bytes: fixtureLogoPng(seed: 7),
        ext: 'png',
        sha256: 'y',
        edge: DocumentLogoEdge.bottom,
        side: DocumentLogoSide.right,
        widthMm: 9,
        origin: DocumentLogoOrigin.footer,
      ),
    );
    await addThemeProfileWithoutSelection(
      container.read(settingsProvider.notifier),
      other,
    );
    final done = await startImport(
      tester,
      ctx,
      docxStyledFixture(defaultFooterLogo: fixtureLogoPng()),
    );
    expect(
      find.byKey(const Key('import-document-style-existing')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('import-document-style-text-only')));
    await done;
    await tester.pump();
    container.dispose();
  });

  testWidgets('beelden in de tekst komen mee; de stijlvraag staat er los van', (
    tester,
  ) async {
    final (container, ctx) = await pump(tester);
    final done = await startImport(
      tester,
      ctx,
      docxStyledFixture(bodyRepeatedLogo: fixtureLogoPng(), bodyRepeatCount: 1),
    );
    await tester.tap(find.byKey(const Key('import-document-style-text-only')));
    await done;
    await tester.pump();
    // #2128 neemt de afbeelding mee als `mem:`-verwijzing; de melding blijft
    // dan de gewone succesmelding, zonder "niet overgenomen".
    expect(_openDocumentSource(container), contains('](mem:'));
    expect(find.textContaining('niet overgenomen'), findsNothing);
    expect(find.textContaining('geïmporteerd'), findsOneWidget);
    container.dispose();
  });

  test('de keuze-objecten dragen hun stand', () {
    const only = ImportDocumentStyleChoice.textOnly();
    expect(only.disposition, ImportDocumentStyleDisposition.textOnly);
    const fresh = ImportDocumentStyleChoice.newStyle(
      styleName: 'X',
      includeLogo: true,
    );
    expect(fresh.styleName, 'X');
    expect(fresh.includeLogo, isTrue);
  });
}
