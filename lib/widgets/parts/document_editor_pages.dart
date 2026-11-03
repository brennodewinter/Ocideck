part of '../document_editor_screen.dart';

/// Pagina-modus: het document op echte vellen, met de paginamaat, de marges en
/// een eventuele drukkersafloop. Hier zie je wat er op welke bladzijde belandt
/// — de vraag die een tekstverwerker beantwoordt en een doorlopende rol niet.
/// Lezen en nakijken, niet typen: bewerken doe je in de visuele of de bron-stand.
///
/// Top-level en niet op de staat: hij heeft alleen de instellingen, de tekst en
/// de stijl nodig, en het bewerkscherm zit op zijn klasseplafond.
Widget _documentPagesLayout(
  BuildContext context,
  WidgetRef ref,
  ThemeData theme,
  String source, {
  required ThemeProfile? style,
  required String? projectPath,
  required TlpLevel tlp,
  required Map<String, String> fields,
  required FindReplaceSession findSession,
  required int searchRevealSignal,
}) {
  final settings = ref.watch(settingsProvider);
  // Draagt het document zelf een paginaopmaak, dan wint die van de instelling —
  // zie [effectiveDocumentPageSetup].
  final setup = effectiveDocumentPageSetup(settings, _pageSetupSource(ref));
  // Is de geometry-frontmatter ongeldig (negatief, NaN, of marges die samen
  // breder zijn dan het vel), dan is die genegeerd en gelden de instellingen.
  // Dat hoort de gebruiker te weten — niet stíl vervangen (#1681).
  final invalidReason = documentPageSetupInvalidReason(_pageSetupSource(ref));
  return Container(
    color: theme.colorScheme.surfaceContainerHighest,
    child: Column(
      children: [
        if (invalidReason != null)
          MaterialBanner(
            content: Text(
              context.l10n.d(
                'De paginaopmaak in dit document bevat ongeldige waarden en is genegeerd. De instellingen worden gebruikt.',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            leading: Icon(
              Icons.warning_amber_rounded,
              color: theme.colorScheme.error,
            ),
            actions: const [SizedBox.shrink()],
          ),
        Expanded(
          child: PagedDocumentView(
            markdown: source,
            searchQuery: findSession.visible ? findSession.query : '',
            searchMatchIndex: findSession.matchIndex,
            searchCaseSensitive: findSession.caseSensitive,
            searchRevealSignal: searchRevealSignal,
            pageSize: setup.size!,
            margins: setup.margins!,
            profile: style,
            tlp: tlp,
            fields: fields,
            projectPath: projectPath,
            chapterPageBreak: settings.documentChapterPageBreak,
            // Waar de noten komen staat in het document zelf; zie
            // [documentFootnotePlacement].
            footnotePlacement: documentFootnotePlacement(_pageSetupSource(ref)),
            // Hier is de zoom meetkundig: het vel wordt groter of kleiner
            // getekend, de indeling erop blijft die van het papier. Precies
            // waarom je in deze stand inzoomt — om beter te zien wat er staat,
            // niet om iets anders te laten breken.
            scale: settings.documentEditorZoom,
          ),
        ),
        _documentInfoStripFor(context, ref, theme, source),
      ],
    ),
  );
}
