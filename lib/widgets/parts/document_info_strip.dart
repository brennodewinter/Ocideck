// Part of the document-editor library — see ../document_editor_screen.dart.
//
// De strook onder het schrijfvlak: woorden, koppen, tabellen, afbeeldingen en
// de paginamaat. Vroeger zweefde dat linksonder over de laatste regels heen.
// De strook neemt nu een eigen rij, boven de TLP-voet wanneer die er is, zodat
// de tekst er niet meer onderdoor schuift (#2397).
part of '../document_editor_screen.dart';

/// Schrijfpaneel met de informatiestrook eronder, buiten de scroll.
Widget _editorAboveInfoStrip(
  BuildContext context,
  WidgetRef ref,
  ThemeData theme,
  Widget editor,
  String source,
) => Column(
  children: [
    Expanded(child: editor),
    _documentInfoStripFor(context, ref, theme, source),
  ],
);

Widget _documentInfoStripFor(
  BuildContext context,
  WidgetRef ref,
  ThemeData theme,
  String source,
) {
  final frontMatter = _pageSetupSource(ref);
  final setup = effectiveDocumentPageSetup(
    ref.watch(settingsProvider),
    frontMatter,
  );
  return _documentInfoStrip(
    context,
    theme,
    source,
    trailing: _documentPageIndicator(
      context,
      theme,
      pageSize: setup.size!,
      margins: setup.margins!,
      fromDocument: documentCarriesPageSetup(frontMatter),
      onTap: () => unawaited(
        _choosePageSetupScope(
          context,
          ref,
          pageSize: setup.size!,
          margins: setup.margins!,
        ),
      ),
    ),
  );
}

Widget _documentInfoStrip(
  BuildContext context,
  ThemeData theme,
  String source, {
  Widget? trailing,
}) {
  final l10n = context.l10n;
  final stats = computeDocumentStats(source);
  return Material(
    key: const Key('document-info-strip'),
    color: theme.colorScheme.surfaceContainerLow,
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _statChip(
                    theme,
                    Icons.text_fields,
                    stats.words,
                    l10n.d('woorden'),
                  ),
                  _statChip(
                    theme,
                    Icons.menu_book_outlined,
                    stats.chapters,
                    l10n.d('hoofdstukken'),
                  ),
                  _statChip(
                    theme,
                    Icons.subject,
                    stats.sections,
                    l10n.d('paragrafen'),
                  ),
                  _statChip(
                    theme,
                    Icons.table_chart_outlined,
                    stats.tables,
                    l10n.d('tabellen'),
                  ),
                  _statChip(
                    theme,
                    Icons.image_outlined,
                    stats.images,
                    l10n.d('afbeeldingen'),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    ),
  );
}

Widget _statChip(ThemeData theme, IconData icon, int count, String label) =>
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          '$count $label',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    );
