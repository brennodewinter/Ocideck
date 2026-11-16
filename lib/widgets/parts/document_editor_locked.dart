// Part of the document_editor_screen library — see ../document_editor_screen.dart.
//
// Het scherm van een document met `ocideck_read_only: true` — de document-
// tegenhanger van `_PlayOnlyScreen` bij presentaties (#2912). De inhoud blijft
// leesbaar, maar er is geen bewerkingsoppervlak, werkbalk, zoekbalk of
// sneltoets die de bron kan aanraken: de vergrendeling is een routekaart, geen
// grijze knop. Losgeknipt om het bewerkscherm onder zijn regelplafond te
// houden.
part of '../document_editor_screen.dart';

/// Bouwt de alleen-lezenweergave van het huidige document.
///
/// Rendert dezelfde documentstroom als de lezer — stijl, TLP-kop, afbeeldingen
/// via [DocumentImageScope] — maar zonder énige bewerkingshaak. De enige weg
/// terug naar bewerken is de sleutel uit het bestand halen, net als bij
/// `ocideck_play_only`.
Widget _documentReadOnlyView(BuildContext context, WidgetRef ref) {
  final theme = Theme.of(context);
  final l10n = context.l10n;
  final settings = ref.watch(settingsProvider);
  final document = ref.watch(documentProvider.select((s) => s.document));
  if (document == null) return const SizedBox.shrink();
  final style = resolveDocumentStyleProfile(settings, document.styleName);
  final tlp = _documentTlp(ref);
  return Scaffold(
    body: Column(
      children: [
        // De melding draagt de vergrendeling uit zodat niemand een kapotte
        // werkbalk zoekt — dezelfde rol als het slotje op `_PlayOnlyScreen`.
        Material(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.d('Dit document is alleen-lezen (vergrendeld)'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: theme.colorScheme.outlineVariant,
        ),
        Expanded(
          child: DocumentImageScope(
            projectPath: _documentProjectPath(ref),
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: _styledDocumentBody(
                  style,
                  DocumentMarkdownView(
                    document.body,
                    maxTextWidth: 720,
                    themeProfile: style,
                    chartTheme: style,
                  ),
                  tlp: tlp,
                  fields: document.fields,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
