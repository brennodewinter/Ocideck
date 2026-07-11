// Part of the markdown_service library — see markdown_service.dart.
// Split out for the file-size ratchet: the `finding` slide type's parse helpers
// (PENTEST_MIAUW §3.1). These are extension methods on MarkdownService, in the
// same library as the rest of the parser, so they share its library-private
// regexes/helpers and are called straight from `_parseBlock`.
part of 'markdown_service.dart';

extension _MarkdownFindingParse on MarkdownService {
  /// Pulls the per-slide attestation link comments out of [block]: the
  /// finding-group link (`ocideck_finding_id` / `ocideck_finding_role`) and the
  /// AI-assist markers (`ocideck_ai_assisted`, AI_ASSIST §16.3). Returns the
  /// block with them removed plus the decoded values (empty id /
  /// [FindingRole.header] / empty markers when absent). Handled here — like
  /// `_parseImageFocus` — so they are stripped before `_parseBlockDirectives`'s
  /// generic scan would treat them as presenter notes, without lengthening that
  /// method.
  ({
    String findingId,
    FindingRole findingRole,
    List<String> aiAssistedFields,
    String block,
  })
  _parseFindingLink(String block) {
    var findingId = '';
    var findingRole = FindingRole.header;
    var aiAssistedFields = const <String>[];
    final cleaned = block.replaceAllMapped(_reHtmlComment, (m) {
      final content = m.group(1)!.trim();
      if (content.startsWith('ocideck_finding_id:')) {
        findingId = content.substring('ocideck_finding_id:'.length).trim();
        return '';
      }
      if (content.startsWith('ocideck_finding_role:')) {
        final name = content.substring('ocideck_finding_role:'.length).trim();
        findingRole = FindingRole.values.firstWhere(
          (role) => role.name == name,
          orElse: () => FindingRole.header,
        );
        return '';
      }
      if (content.startsWith('ocideck_ai_assisted:')) {
        aiAssistedFields = content
            .substring('ocideck_ai_assisted:'.length)
            .split(',')
            .map((f) => f.trim())
            .where((f) => f.isNotEmpty)
            .toList();
        return '';
      }
      return m.group(0)!;
    });
    return (
      findingId: findingId,
      findingRole: findingRole,
      aiAssistedFields: aiAssistedFields,
      block: cleaned,
    );
  }

  /// A `finding` header slide (PENTEST_MIAUW §3.1). Its body is structured
  /// Markdown (bold field lines + `## sections`) kept verbatim in
  /// [Slide.customMarkdown]; the heading is lifted into the slide title so the
  /// outline and search keep working. Returns null when [cssClass] is not a
  /// finding. Detail/evidence slides in the same group are ordinary slide types
  /// (bullets, image) — they carry only the finding id + role and flow through
  /// the generic parser.
  Slide? _tryFindingSlide({
    required String cssClass,
    required String remaining,
    required String notes,
    required double advanceDuration,
    required bool skipped,
    required TlpLevel tlp,
    required String findingId,
    required FindingRole findingRole,
  }) {
    final tokens = cssClass.split(_reWhitespace);
    if (!tokens.contains('finding')) return null;
    final body = normalizeRichTextMarkdown(
      unescapeDeckMarkdownDashLines(remaining),
    );
    final effectiveClass = tokens
        .where(
          (c) =>
              c.isNotEmpty &&
              c != 'finding' &&
              c != 'logo-safe' &&
              c != 'no-logo' &&
              c != 'no-footer',
        )
        .join(' ');
    return Slide(
      id: _uuid.v4(),
      type: SlideType.finding,
      title: FindingSpec.parse(body).heading,
      customMarkdown: body,
      cssClass: effectiveClass,
      notes: notes,
      advanceDuration: advanceDuration,
      showLogo: !tokens.contains('no-logo'),
      showFooter: !tokens.contains('no-footer'),
      skipped: skipped,
      tlp: tlp,
      findingId: findingId,
      findingRole: findingRole,
    );
  }
}
