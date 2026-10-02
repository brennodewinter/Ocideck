// Part of the document_editor_screen library — see ../document_editor_screen.dart.
//
// De invulstand van een formulierdocument (FORM_INTAKE.md §8). Een formulier is
// een gewoon document; deze stand toont het als pagina met invoervelden en
// schrijft elk antwoord terug als een nieuwe brontekst, zodat opslaan, ongedaan
// maken en de andere standen ongewijzigd werken. Eigen part omdat het hoofdbestand
// op zijn regelplafond zit.
part of '../document_editor_screen.dart';

/// De invulpagina met wat ze van het document nodig heeft: de map voor foto's, de
/// front matter en de kiezers voor het opslaan van de inzending. Een losse functie en
/// geen methode: de staat zit tegen zijn regelplafond.
FormFillView _formFillView(
  BuildContext context,
  WidgetRef ref, {
  required String body,
  required void Function(String body, String fieldId) onChanged,
  required VoidCallback onShowSource,
}) {
  final l10n = context.l10n;
  final projectPath = _documentProjectPath(ref);
  return FormFillView(
    body: body,
    onChanged: onChanged,
    onShowSource: onShowSource,
    images: formImageSupportFor(
      projectPath: projectPath,
      dialogTitle: l10n.d('Kies een afbeelding'),
    ),
    export: formExportSupportFor(
      projectPath: projectPath,
      frontMatter: ref.read(documentProvider).document?.frontMatter ?? '',
      pickTitle: l10n.d('Kies het formulier zoals je het kreeg'),
      saveTitle: l10n.d('Inzending opslaan'),
    ),
  );
}

extension _DocumentEditorForm on _DocumentEditorScreenState {
  /// De invulpagina, in de stijl van het document.
  Widget _fillLayout(
    String source, {
    required TlpLevel tlp,
    required Map<String, String> fields,
  }) => _styledDocumentSurface(
    _styleProfile,
    DocumentStyleScope(
      profile: _styleProfile,
      child: _formFillView(
        context,
        ref,
        body: source,
        onChanged: _onFillChanged,
        onShowSource: () => _changeViewMode(_DocViewMode.source),
      ),
    ),
    tlp: tlp,
    fields: fields,
  );

  /// Een antwoord is een nieuwe brontekst. Eén ongedaan-maken-stap per veld: wie
  /// in een veld typt wil dat met één keer ongedaan maken terugdraaien, niet
  /// teken voor teken. `visualEdit: false`: de tekst komt niet door de rijke-
  /// tekstlaag, dus de basislijn van de visuele stand blijft ongemoeid.
  void _onFillChanged(String body, String fieldId) {
    final doc = ref.read(documentProvider).document;
    if (doc == null) return;
    ref
        .read(documentProvider.notifier)
        .edit(doc.frontMatter + body, coalesceKey: 'fill:$fieldId');
  }
}
