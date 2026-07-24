import '../models/conversion_issue.dart';

/// Vertaalt één bronstring naar de taal van de gebruiker.
///
/// De servicelaag kent `AppLocalizations` niet en hoort dat ook niet te doen —
/// er is hier geen `BuildContext`. De UI geeft `l10n.d` mee; wie de import
/// zonder interface draait (een test, een toekomstige opdrachtregel) krijgt
/// [identityTranslator] en houdt de Nederlandse bronstrings.
typedef ImportTextTranslator = String Function(String dutchSource);

/// De standaardnaad: geeft de bronstring onveranderd terug.
String identityTranslator(String dutchSource) => dutchSource;

/// Builds the "not converted" note slides that guarantee losslessness.
///
/// For every source slide with [ConversionIssue]s, the pipeline emits a
/// free-Markdown slide right after it that lists what was not converted and,
/// where relevant, what part was salvaged. So a reader always knows what was
/// dropped — nothing disappears silently.
///
/// ## Waarom hier vertaald wordt en niet bij het tonen
///
/// Deze tekst is **inhoud**: hij wordt in het `.md` van de gebruiker
/// geschreven en blijft daar staan. Een notitiedia die in het Nederlands is
/// opgeslagen blijft Nederlands, ook nadat de gebruiker de app op Grieks zet,
/// en hij reist zo mee naar elk ander Marp-gereedschap (#806). Vertalen op
/// weergavemoment kan dus niet — het moet gebeuren op het moment dat het
/// document ontstaat, en dat is hier.
class UnconvertedTracker {
  /// Build the free-Markdown body for a note slide covering [issues] from
  /// source slide number [sourceSlideNumber] (1-based, user-facing).
  ///
  /// The body is plain Markdown (no front matter, no `_class`) so the writer
  /// can wrap it in a free-Markdown slide.
  static String buildNoteBody(
    int sourceSlideNumber,
    List<ConversionIssue> issues, {
    String? heading,
    ImportTextTranslator translate = identityTranslator,
  }) {
    final title = _fill(translate('Niet overgenomen van slide {n}'), {
      'n': '$sourceSlideNumber',
    });
    final lines = <String>[
      heading ?? '# $title',
      '',
      for (final issue in issues) _formatIssue(issue, translate),
    ];
    return lines.join('\n');
  }

  /// Build the free-Markdown body for a deck-wide note slide covering
  /// [issues] that are not attributable to a single source slide (e.g. a
  /// whole format whose internals the import cannot parse yet). Appended once at
  /// the end of the deck by the writer.
  static String buildDeckNoteBody(
    List<ConversionIssue> issues, {
    ImportTextTranslator translate = identityTranslator,
  }) {
    final lines = <String>[
      '# ${translate('Niet overgenomen van dit document')}',
      '',
      for (final issue in issues) _formatIssue(issue, translate),
    ];
    return lines.join('\n');
  }

  /// Whether [issues] contain any non-salvaged loss worth noting.
  static bool hasLoss(List<ConversionIssue> issues) =>
      issues.any((i) => !i.isSalvaged) || issues.isNotEmpty;

  static String _formatIssue(
    ConversionIssue issue,
    ImportTextTranslator translate,
  ) {
    final feature = _escMarkdown(_fill(translate(issue.feature), issue.args));
    final description = _escMarkdown(
      _fill(translate(issue.description), issue.args),
    );
    final base = '- $feature: $description';
    if (issue.isSalvaged) {
      final salvaged = _escMarkdown(
        _fill(translate(issue.salvagedAs!), issue.args),
      );
      return '$base (${translate('deels overgenomen')}: $salvaged)';
    }
    return base;
  }

  /// Vervang `{naam}`-plaatshouders door hun waarde uit [args].
  ///
  /// Ná het vertalen, zodat de vertaling zelf bepaalt waar de waarde in de zin
  /// landt. Een plaatshouder zonder waarde blijft staan in plaats van te
  /// verdwijnen: dan is in het document te zien dát er iets misging, en dat is
  /// beter dan een zin die stilzwijgend een gat heeft.
  static String _fill(String template, Map<String, String> args) {
    var out = template;
    args.forEach((key, value) => out = out.replaceAll('{$key}', value));
    return out;
  }

  /// Escape HTML and Markdown metacharacters in user-facing issue text.
  ///
  /// `&`, `<` and `>` are turned into HTML entities so a `<!--` or `-->`
  /// inside an issue cannot break the surrounding note slide. Markdown
  /// metacharacters are backslash-escaped and line breaks are collapsed to
  /// spaces so the bullet list stays intact.
  static String _escMarkdown(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\\', '\\\\')
        .replaceAll('*', '\\*')
        .replaceAll('_', '\\_')
        .replaceAll('~', '\\~')
        .replaceAll('|', '\\|')
        .replaceAll('[', '\\[')
        .replaceAll(']', '\\]')
        .replaceAll('\n', ' ');
  }
}
