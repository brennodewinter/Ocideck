// Part of the settings_provider library — see ../settings_provider.dart.
// De documentmodus-stijl (standaardstijl + afdwingen) en de gedeelde
// nullable-string-persist eronder; alle imports leven in het hoofdbestand.
part of '../settings_provider.dart';

/// Schrijf óf wis een nullable string-pref: bij een waarde [prefs.setString],
/// bij `null` [prefs.remove]. Gedeeld door de export-gate-plafonds en de
/// standaard documentstijl — allemaal "kies een sleutel, of zet uit". De
/// [key] is meteen het foutlabel; die is beschrijvend genoeg.
Future<void> _persistNullableString(
  SettingsNotifier notifier,
  String key,
  String? value,
) => notifier._persist(key, (prefs) async {
  if (value == null) {
    await prefs.remove(key);
  } else {
    await prefs.setString(key, value);
  }
});

/// Documentmodus: stel de standaard documentstijl in (een stijlprofielnaam),
/// of `null` voor geen (platte tekst). Puur weergave/export — het raakt geen
/// enkel `.md`-bestand.
Future<void> _applyDocumentDefaultStyle(
  SettingsNotifier notifier,
  String? styleName,
) {
  notifier.currentState = styleName == null
      ? notifier.currentState.copyWith(clearDocumentDefaultStyle: true)
      : notifier.currentState.copyWith(documentDefaultStyle: styleName);
  return _persistNullableString(notifier, 'documentDefaultStyle', styleName);
}

/// Documentmodus: dwing de standaard documentstijl af als huisstijl (negeer
/// per-document `theme:`), of laat elk document zijn eigen stijl kiezen.
Future<void> _applyDocumentStyleEnforced(
  SettingsNotifier notifier,
  bool enforced,
) {
  notifier.currentState = notifier.currentState.copyWith(
    documentStyleEnforced: enforced,
  );
  return notifier._persist(
    'documentStyleEnforced',
    (prefs) => prefs.setBool('documentStyleEnforced', enforced),
  );
}

/// Documentmodus: laat elk hoofdstuk (H1) bij export/afdruk op een nieuwe pagina
/// beginnen, of niet. Puur een export-/afdrukkeuze; raakt geen `.md`-bestand.
Future<void> _applyDocumentChapterPageBreak(
  SettingsNotifier notifier,
  bool enabled,
) {
  notifier.currentState = notifier.currentState.copyWith(
    documentChapterPageBreak: enabled,
  );
  return notifier._persist(
    'documentChapterPageBreak',
    (prefs) => prefs.setBool('documentChapterPageBreak', enabled),
  );
}

/// Documentmodus: snijtekens rond het snijformaat in de LaTeX/PDF-export.
/// Alleen zinvol met een afloop; raakt geen `.md`-bestand.
Future<void> _applyDocumentCropMarks(SettingsNotifier notifier, bool enabled) {
  notifier.currentState = notifier.currentState.copyWith(
    documentCropMarks: enabled,
  );
  return notifier._persist(
    'documentCropMarks',
    (prefs) => prefs.setBool('documentCropMarks', enabled),
  );
}

/// Documentmodus: stel de maximale schrijfbreedte van de visuele editor in
/// (px), of `null` voor volledige breedte. Feature 2.
Future<void> _applyDocumentEditorMaxWidth(
  SettingsNotifier notifier,
  double? width,
) {
  notifier.currentState = width == null
      ? notifier.currentState.copyWith(clearDocumentEditorMaxWidth: true)
      : notifier.currentState.copyWith(documentEditorMaxWidth: width);
  // `null` (volledige breedte) wordt als 0 weggeschreven, niet als een
  // verwijderde sleutel: een ontbrekende sleutel is "nooit gekozen" en leest bij
  // het opstarten terug als de standaard 1100. Wie volledige breedte koos, kreeg
  // na een herstart stilzwijgend weer een smalle editor.
  return notifier._persist(
    'documentEditorMaxWidth',
    (prefs) => prefs.setDouble('documentEditorMaxWidth', width ?? 0),
  );
}

/// De opgeslagen schrijfbreedte terug: `0` betekent volledige breedte (zie
/// [_applyDocumentEditorMaxWidth]), een ontbrekende sleutel betekent "nog nooit
/// gekozen" en krijgt de standaard van 1100 px.
double? _readDocumentEditorMaxWidth(SharedPreferences prefs) =>
    switch (prefs.getDouble('documentEditorMaxWidth')) {
      null => 1100,
      <= 0 => null,
      final width => width,
    };

/// Documentmodus: op welke breedte de visuele editor schrijft.
///
/// Puur een kijkvoorkeur — er gaat geen byte naar het `.md`. Los van de
/// schakelaar voor de pagina-einden: die twee zaten aan elkaar vast, en
/// daardoor deed de breedte-instelling niets zolang de einden aanstonden.
Future<void> _applyDocumentEditorWidth(
  SettingsNotifier notifier,
  DocumentEditorWidth width,
) {
  notifier.currentState = notifier.currentState.copyWith(
    documentEditorWidth: width,
  );
  return notifier._persist(
    'documentEditorWidth',
    (prefs) => prefs.setString('documentEditorWidth', width.name),
  );
}

/// Ondergrens, bovengrens en stapgrootte voor de documentatielezer-schaal;
/// gedeeld met de knoppen in de lezer zodat clampen en stappen consistent zijn.
/// Top-level om dezelfde reden als de zoomgrenzen hieronder.
const double kDocReaderTextScaleMin = 0.8;
const double kDocReaderTextScaleMax = 1.8;
const double kDocReaderTextScaleStep = 0.1;

/// Ondergrens, bovengrens en stapgrootte van de documenteditor-zoom.
///
/// Top-level en niet op [SettingsNotifier]: die klasse zit op haar plafond, en
/// een grens is geen gedrag. De knoppen in de werkbalk lezen ze hier, zodat
/// clampen en stappen aan één kant vastliggen.
const double kDocumentEditorZoomMin = 0.5;
const double kDocumentEditorZoomMax = 2.5;
const double kDocumentEditorZoomStep = 0.1;

/// De tekstschaal van de documentatielezer, geklemd op zijn grenzen.
Future<void> _applyDocReaderTextScale(SettingsNotifier notifier, double scale) {
  final clamped = scale
      .clamp(kDocReaderTextScaleMin, kDocReaderTextScaleMax)
      .toDouble();
  if (clamped == notifier.currentState.docReaderTextScale) {
    return Future.value();
  }
  notifier.currentState = notifier.currentState.copyWith(
    docReaderTextScale: clamped,
  );
  return notifier._persist(
    'setDocReaderTextScale',
    (prefs) => prefs.setDouble('docReaderTextScale', clamped),
  );
}

/// Documentmodus: de zoomfactor van het schrijfvlak en de vellen.
Future<void> _applyDocumentEditorZoom(SettingsNotifier notifier, double zoom) {
  final clamped = zoom
      .clamp(kDocumentEditorZoomMin, kDocumentEditorZoomMax)
      .toDouble();
  if (clamped == notifier.currentState.documentEditorZoom) {
    return Future.value();
  }
  notifier.currentState = notifier.currentState.copyWith(
    documentEditorZoom: clamped,
  );
  return notifier._persist(
    'documentEditorZoom',
    (prefs) => prefs.setDouble('documentEditorZoom', clamped),
  );
}

/// Alle documentmodus-instellingen zoals ze op schijf staan, in één keer.
///
/// Het lezen hoort in dezelfde `part` als het schrijven: ze delen de sleutels
/// en de standaardwaarden, en zo blijft het lezen buiten het regelplafond van
/// [SettingsNotifier]. Spiegelt [_loadCockpitSettings] in het hoofdbestand.
({
  String? defaultStyle,
  bool styleEnforced,
  bool chapterPageBreak,
  bool cropMarks,
  double? editorMaxWidth,
  DocumentEditorWidth editorWidth,
  double editorZoom,
  PageSizeSpec pageSize,
  PageMargins pageMargins,
})
_readDocumentSettings(SharedPreferences prefs) => (
  defaultStyle: prefs.getString('documentDefaultStyle'),
  styleEnforced: prefs.getBool('documentStyleEnforced') ?? false,
  chapterPageBreak: prefs.getBool('documentChapterPageBreak') ?? false,
  cropMarks: prefs.getBool('documentCropMarks') ?? false,
  editorMaxWidth: _readDocumentEditorMaxWidth(prefs),
  editorWidth: DocumentEditorWidth.values.firstWhere(
    (value) => value.name == prefs.getString('documentEditorWidth'),
    // Niets gekozen → de breedte van het vel: dat is de stand waarin de
    // pagina-einden kloppen, en dus de stand waarin de editor het meeste zegt.
    orElse: () => DocumentEditorWidth.page,
  ),
  editorZoom: (prefs.getDouble('documentEditorZoom') ?? 1.0).clamp(
    kDocumentEditorZoomMin,
    kDocumentEditorZoomMax,
  ),
  pageSize:
      PageSizeSpec.fromId(prefs.getString('documentPageSize')) ??
      PageSizeSpec.a4,
  pageMargins:
      PageMargins.fromId(prefs.getString('documentPageMargins')) ??
      const PageMargins(),
);

/// Documentmodus: stel de paginamaat voor export in (ISO-216). Feature 3.
Future<void> _applyDocumentPageSize(
  SettingsNotifier notifier,
  PageSizeSpec spec,
) {
  notifier.currentState = notifier.currentState.copyWith(
    documentPageSize: spec,
  );
  return notifier._persist(
    'documentPageSize',
    (prefs) => prefs.setString('documentPageSize', spec.id),
  );
}

/// Documentmodus: stel de paginamarges voor export in. Feature 3.
Future<void> _applyDocumentPageMargins(
  SettingsNotifier notifier,
  PageMargins margins,
) {
  notifier.currentState = notifier.currentState.copyWith(
    documentPageMargins: margins,
  );
  return notifier._persist(
    'documentPageMargins',
    (prefs) => prefs.setString('documentPageMargins', margins.id),
  );
}
