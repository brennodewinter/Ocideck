// De invulpagina van een formulier (FORM_INTAKE.md §8): de titel, wat de auteur
// erbij schreef, de notice, en elk veld met zijn eigen controle — als één
// scrollende pagina, zonder editor-chrome.
//
// De pagina houdt de [FormFill] bij en schrijft elke wijziging als een nieuwe
// brontekst terug via [onChanged]; het document blijft zo de waarheid en de
// ongedaan-maken-geschiedenis van het tabblad werkt gewoon mee. Er wordt *nooit*
// door de rijke-tekstlaag geschreven: die herschrijft de lege regels om een blok
// en zou de sjabloontekst van het formulier veranderen (FILE_FORMAT §14.14). Alleen
// de bytes van een antwoordzone veranderen.

import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/form_issue_localization.dart';
import '../markdown_editor/markdown_editor_theme.dart' show DocumentStyleScope;
import '../reader/document_markdown_view.dart';
import 'form_field_card.dart';
import 'form_text_helpers.dart';

class FormFillView extends StatefulWidget {
  const FormFillView({
    super.key,
    required this.body,
    required this.onChanged,
    this.onShowSource,
    this.onAddImages,
  });

  /// De tekst van het document (zonder front matter).
  final String body;

  /// De nieuwe tekst na een antwoord, met het veld dat veranderde. De aanroeper
  /// schrijft hem in het document.
  final void Function(String body, String fieldId) onChanged;

  /// Naar de bron, voor een formulier dat niet ingevuld kan worden.
  final VoidCallback? onShowSource;

  /// Zie [FormAnswerEditor.onAddImages]; krijgt het id van het veld.
  final Future<List<FormImageRef>> Function(String fieldId)? onAddImages;

  @override
  State<FormFillView> createState() => _FormFillViewState();
}

class _FormFillViewState extends State<FormFillView> {
  FormFill? _fill;
  FormProblem? _unavailable;

  /// De tekst waarvan de huidige [_fill] is gemaakt, om te zien of een nieuwe
  /// `body` van buitenaf komt (ongedaan maken) of de echo is van een eigen antwoord.
  String _loaded = '';

  final Set<String> _touched = {};
  final Map<String, GlobalKey> _keys = {};
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load(widget.body);
  }

  @override
  void didUpdateWidget(FormFillView old) {
    super.didUpdateWidget(old);
    if (widget.body != _loaded) _load(widget.body);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _load(String body) {
    _loaded = body;
    switch (FormFill.open(body, imageFacts: _fill?.imageFacts ?? const {})) {
      case FormFillReady(:final fill):
        _fill = fill;
        _unavailable = null;
      case FormFillUnavailable(:final problem):
        _fill = null;
        _unavailable = problem;
    }
  }

  FormFillStep _commit(String fieldId, FormAnswerValue value) {
    final step = _fill!.setAnswer(fieldId, value);
    if (step is FormFillChanged) {
      setState(() {
        _fill = step.fill;
        _loaded = step.fill.text;
        _touched.add(fieldId);
      });
      widget.onChanged(step.fill.text, fieldId);
    } else {
      setState(() => _touched.add(fieldId));
    }
    return step;
  }

  GlobalKey _keyOf(String fieldId) =>
      _keys.putIfAbsent(fieldId, () => GlobalKey());

  void _jumpTo(String fieldId) {
    setState(() => _touched.add(fieldId));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _keys[fieldId]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    });
  }

  Widget _markdown(BuildContext context, String markdown) =>
      DocumentMarkdownView(
        markdown,
        maxTextWidth: null,
        themeProfile: DocumentStyleScope.maybeOf(context),
        chartTheme: DocumentStyleScope.maybeOf(context),
      );

  @override
  Widget build(BuildContext context) {
    final fill = _fill;
    if (fill == null) {
      return _Unavailable(
        problem: _unavailable!,
        onShowSource: widget.onShowSource,
      );
    }
    final theme = Theme.of(context);
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    fill.title,
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(height: 12),
                _Summary(fill: fill, onJump: _jumpTo),
                const SizedBox(height: 8),
                for (final item in fill.items) _item(context, fill, item),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, FormFill fill, FormItem item) {
    switch (item) {
      case FormTextItem(:final markdown):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _markdown(context, markdown),
        );
      case FormNoticeItem(:final markdown):
        return _NoticeCard(child: _markdown(context, markdown));
      case FormHeadingItem():
        return _SectionHeading(heading: item, open: fill.openIn(item));
      case FormFieldItem(:final fieldId):
        return FormFieldCard(
          key: _keyOf(fieldId),
          fill: fill,
          fieldId: fieldId,
          showRequired: _touched.contains(fieldId),
          onCommit: _commit,
          onAddImages: widget.onAddImages == null
              ? null
              : () => widget.onAddImages!(fieldId),
        );
    }
  }
}

/// Bovenaan: hoeveel er nog openstaat, elk met een sprong naar het veld.
class _Summary extends StatelessWidget {
  const _Summary({required this.fill, required this.onJump});

  final FormFill fill;
  final ValueChanged<String> onJump;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    if (fill.openCount == 0) {
      return Row(
        children: [
          Icon(Icons.check_circle_outline, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.d('Alles is ingevuld.'))),
        ],
      );
    }
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n
                  .d('Nog {n} te doen voordat je kunt versturen:')
                  .replaceAll('{n}', '${fill.openCount}'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Wrap(
              spacing: 4,
              children: [
                for (final id in fill.openFieldIds)
                  TextButton(
                    onPressed: () => onJump(id),
                    child: Text(
                      formFieldTitle(
                        fill.text
                            .substring(
                              fill.fieldOf(id).label.start,
                              fill.fieldOf(id).label.end,
                            )
                            .trim(),
                        id,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.heading, required this.open});

  final FormHeadingItem heading;
  final int open;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final style = switch (heading.level) {
      1 => theme.textTheme.headlineSmall,
      2 => theme.textTheme.titleLarge,
      _ => theme.textTheme.titleMedium,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(heading.title, style: style),
            ),
          ),
          if (heading.fieldIds.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  open == 0
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  open == 0
                      ? l10n.d('klaar')
                      : l10n.d('{n} open').replaceAll('{n}', '$open'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.4),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Wat er staat als het document geen formulier is dat ingevuld kan worden: een
/// kapot formulier (de auteur moet het herstellen) of een van een nieuwere versie.
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.problem, required this.onShowSource});

  final FormProblem problem;
  final VoidCallback? onShowSource;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.d('Dit formulier kan niet worden ingevuld.'),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(formIssueMessage(l10n, problem)),
              if (onShowSource != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onShowSource,
                  child: Text(l10n.d('Naar de bron')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
