// Part of the document_editor_screen library — see ../document_editor_screen.dart.
//
// De invulstand van een formulierdocument (FORM_INTAKE.md §8). Een formulier is
// een gewoon document; deze stand toont het als pagina met invoervelden en
// schrijft elk antwoord terug als een nieuwe brontekst, zodat opslaan, ongedaan
// maken en de andere standen ongewijzigd werken. Eigen part omdat het hoofdbestand
// op zijn regelplafond zit.
part of '../document_editor_screen.dart';

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
      child: FormFillView(
        body: source,
        onChanged: _onFillChanged,
        onShowSource: () => _changeViewMode(_DocViewMode.source),
        images: formImageSupportFor(
          projectPath: _documentProjectPath(ref),
          dialogTitle: context.l10n.d('Kies een afbeelding'),
        ),
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
