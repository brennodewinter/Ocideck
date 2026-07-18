import '../services/cvss/cvss4.dart';

/// Whether — and with what outcome — a finding was **retested** (hertest,
/// PENTEST_MIAUW §4.13). The [token] is the stable English word written to the
/// finding's Markdown (language-independent, like the section anchors);
/// [dutchLabel] is the Dutch source shown in the UI (localise with `l10n.d(...)`).
enum RetestStatus {
  notRetested('', 'Niet hertest'),
  resolved('Resolved', 'Opgelost'),
  notResolved('NotResolved', 'Nog aanwezig'),
  partiallyResolved('PartiallyResolved', 'Deels opgelost');

  const RetestStatus(this.token, this.dutchLabel);

  final String token;
  final String dutchLabel;

  /// Whether a retest outcome is recorded (so it shows a badge and counts as
  /// retested); [notRetested] is the "not yet retested" default.
  bool get isRetested => this != notRetested;

  /// Whether the finding was confirmed resolved after retest.
  bool get isResolved => this == resolved;

  /// Parse the on-disk token; anything unrecognised (incl. empty) is
  /// [notRetested].
  static RetestStatus fromToken(String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return notRetested;
    for (final s in values) {
      if (s != notRetested && s.token.toLowerCase() == v) return s;
    }
    return notRetested;
  }
}

/// The structured content of a `finding` slide's **header card**
/// (PENTEST_MIAUW §3.1), parsed from and rendered to plain, human-readable
/// Markdown. Storage stays Markdown-close (the philosophy of the caption /
/// cockpit / question specs): every field is inline and re-parseable, so a
/// finding on disk reads like a report page, not a machine block.
///
/// Invariants (§3.1):
/// - **Severity/score are derived** from [cvssVector] via the [Cvss4] engine —
///   never stored. [toMarkdown] recomputes the `9.3 (Critical)` prefix on save.
/// - The vector string, CWE id and CVE ids are **parsed back** from the inline
///   text; there is no duplicated machine block.
/// - Section markers (`## Description`, …) are stable English anchors — content,
///   not localised UI — so the round-trip is language-independent.
///
/// The finding id and role that link a group's slides are *not* here — they are
/// slide-level fields ([Slide.findingId] / [Slide.findingRole]) because they ride
/// on the header **and** its detail/evidence slides.
class FindingSpec {
  const FindingSpec({
    this.heading = '',
    this.scopeObject = '',
    this.cvssVector = '',
    this.cweId,
    this.cweName = '',
    this.cveIds = const [],
    this.description = '',
    this.confirmation = '',
    this.impact = '',
    this.recommendation = '',
    this.retest = RetestStatus.notRetested,
    this.retestNote = '',
    this.testId = '',
  });

  /// The `# ` heading text, e.g. `F-03 · SQL injection in the login form`. The
  /// `F-03` prefix is authored/maintained by auto-numbering (§10.1,
  /// `DeckNotifierAuto.autoRenumberFindings`); this spec treats the whole line
  /// as opaque text.
  final String heading;

  /// The scope object the finding concerns, e.g. `https://app.example/login`.
  /// Rendered inside backticks; stored without them.
  final String scopeObject;

  /// The CVSS v4.0 vector string (`CVSS:4.0/AV:N/…`). Empty = no score. The
  /// score and severity band shown to the reader are derived from this, never
  /// stored (§3.1).
  final String cvssVector;

  /// The CWE weakness id (e.g. `89` for CWE-89), or null when unset.
  final int? cweId;

  /// The CWE name shown after the id; optional (coverage is uneven, §6).
  final String cweName;

  /// Zero or more CVE ids (e.g. `CVE-2024-1234`), rendered as NVD links.
  final List<String> cveIds;

  final String description;
  final String confirmation;
  final String impact;
  final String recommendation;

  /// Whether the finding was retested and the outcome (hertest, §4.13).
  final RetestStatus retest;

  /// Optional free-text note on the retest (e.g. date, patch reference).
  final String retestNote;

  /// The checklist **test** this finding evidences (feedback #8), e.g.
  /// `WSTG-ATHN-07`. Empty = not linked. Picked from the checklist(s) that cover
  /// the finding's scope object; setting it marks the matching checklist row as
  /// an anomaly linked to this finding. Rendered inside backticks; stored without.
  final String testId;

  /// The parsed CVSS vector, or null when [cvssVector] is empty/invalid.
  Cvss4? get cvss =>
      cvssVector.isEmpty ? null : Cvss4.tryParseVector(cvssVector);

  /// The derived severity band, or null when there is no valid vector.
  Cvss4Severity? get severity => cvss?.severity;

  /// The canonical MITRE URL for [cweId] (§6: always link to the canonical
  /// definition even when the local dataset lacks the name).
  String? get cweUrl => cweId == null
      ? null
      : 'https://cwe.mitre.org/data/definitions/$cweId.html';

  /// The canonical NVD URL for a CVE id.
  static String cveUrl(String cve) => 'https://nvd.nist.gov/vuln/detail/$cve';

  static final _reHeading = RegExp(r'^#\s+(.*)$');
  static final _reField = RegExp(r'^\*\*([^*]+):\*\*\s*(.*)$');
  static final _reSection = RegExp(r'^##\s+(.*)$');
  static final _reBacktick = RegExp(r'`([^`]*)`');
  static final _reCwe = RegExp(r'CWE-(\d+)');
  static final _reCweName = RegExp(r'—\s*([^\]]+?)\s*\]');
  static final _reCve = RegExp(r'CVE-\d{4}-\d+');
  static final _reVector = RegExp(r'CVSS:4\.0/[A-Za-z0-9:/]+');

  /// The English section anchors, mapped so [parse] can route each `## …` block
  /// to the right field. These are the exact strings [toMarkdown] emits.
  static const sectionDescription = 'Description';
  static const sectionConfirmation = 'Confirmation (reproduction)';
  static const sectionImpact = 'Possible impact';
  static const sectionRecommendation = 'Recommendation';

  /// Anchor → its Dutch source string, so a rendering surface can show the
  /// heading in the **report's** language (`Deck.language`, MIAUW EIS 2.3) while
  /// the anchor written to disk stays English and the round-trip stays
  /// language-independent (PENTEST_MIAUW §12.3).
  ///
  /// Resolve with `AppLocalizations.sourceFor(deck.language, …)`, never
  /// `l10n.d(…)`: `d()` follows the *interface* language, and a Dutch tester
  /// writing for an international client produces an English report from a Dutch
  /// UI. An unrecorded language resolves through the `en` fallback back to the
  /// anchor itself — which is why every English translation here must stay
  /// identical to its anchor (guarded by `test/finding_section_language_test.dart`).
  static const sectionSources = {
    sectionDescription: 'Beschrijving',
    sectionConfirmation: 'Bevestiging (reproductie)',
    sectionImpact: 'Mogelijke impact',
    sectionRecommendation: 'Aanbeveling',
  };

  /// Parse a finding header body (the Markdown after the `_class` sidecar). The
  /// parse is deliberately lenient: hand-written findings that stray from the
  /// canonical layout still yield whatever fields are recognisable, and the
  /// unrecognised remainder is dropped only from the structured *view* — the raw
  /// Markdown remains the source of truth on disk.
  factory FindingSpec.parse(String markdown) {
    var heading = '';
    var scopeObject = '';
    var cvssVector = '';
    int? cweId;
    var cweName = '';
    final cveIds = <String>[];
    var retest = RetestStatus.notRetested;
    var retestNote = '';
    var testId = '';
    final sections = <String, StringBuffer>{};
    String? current; // the section title currently being accumulated

    for (final raw in markdown.split('\n')) {
      final line = raw.trimRight();
      final section = _reSection.firstMatch(line);
      if (section != null) {
        current = section.group(1)!.trim();
        sections.putIfAbsent(current, () => StringBuffer());
        continue;
      }
      if (current != null) {
        final buf = sections[current]!;
        if (buf.isNotEmpty) buf.write('\n');
        buf.write(raw);
        continue;
      }
      if (heading.isEmpty) {
        final h = _reHeading.firstMatch(line);
        if (h != null) {
          heading = h.group(1)!.trim();
          continue;
        }
      }
      final field = _reField.firstMatch(line);
      if (field == null) continue;
      final key = field.group(1)!.trim().toLowerCase();
      final value = field.group(2)!.trim();
      switch (key) {
        case 'scope object':
          scopeObject = _reBacktick.firstMatch(value)?.group(1) ?? value;
        case 'cvss 4.0':
          cvssVector = _reVector.firstMatch(value)?.group(0) ?? '';
        case 'cwe':
          cweId = int.tryParse(_reCwe.firstMatch(value)?.group(1) ?? '');
          cweName = _reCweName.firstMatch(value)?.group(1)?.trim() ?? '';
        case 'cve':
          // A CVE id appears twice per link (once in the `[label]`, once in the
          // `(url)`); keep the first occurrence of each in author order.
          for (final match in _reCve.allMatches(value)) {
            final id = match.group(0)!;
            if (!cveIds.contains(id)) cveIds.add(id);
          }
        case 'retest':
          // `<Token>` or `<Token> — <note>`.
          final dash = value.indexOf('—');
          final statusText = (dash >= 0 ? value.substring(0, dash) : value)
              .trim();
          retest = RetestStatus.fromToken(statusText);
          if (dash >= 0) retestNote = value.substring(dash + 1).trim();
        case 'test':
          testId = _reBacktick.firstMatch(value)?.group(1) ?? value;
      }
    }

    String body(String title) => (sections[title]?.toString() ?? '').trim();
    return FindingSpec(
      heading: heading,
      scopeObject: scopeObject,
      cvssVector: cvssVector,
      cweId: cweId,
      cweName: cweName,
      cveIds: cveIds,
      retest: retest,
      retestNote: retestNote,
      testId: testId,
      description: body(sectionDescription),
      confirmation: body(sectionConfirmation),
      impact: body(sectionImpact),
      recommendation: body(sectionRecommendation),
    );
  }

  /// Render the canonical §3.1 Markdown. Only the fields that carry content emit
  /// a line; the four sections are always emitted so the header reads as a
  /// complete template. The CVSS line's score/severity are recomputed here so
  /// they can never drift from the vector.
  String toMarkdown() {
    final buf = StringBuffer();
    if (heading.isNotEmpty) {
      buf.writeln('# $heading');
      buf.writeln();
    }
    final metaLines = <String>[];
    if (scopeObject.isNotEmpty) {
      metaLines.add('**Scope object:** `$scopeObject`');
    }
    if (cvssVector.isNotEmpty) metaLines.add('**CVSS 4.0:** ${_cvssText()}');
    if (cweId != null) metaLines.add('**CWE:** ${_cweLink()}');
    if (cveIds.isNotEmpty) {
      final links = cveIds.map((c) => '[$c](${cveUrl(c)})').join(', ');
      metaLines.add('**CVE:** $links');
    }
    if (testId.isNotEmpty) metaLines.add('**Test:** `$testId`');
    if (retest.isRetested) {
      final note = retestNote.trim();
      metaLines.add(
        '**Retest:** ${retest.token}${note.isEmpty ? '' : ' — $note'}',
      );
    }
    if (metaLines.isNotEmpty) {
      for (final line in metaLines) {
        buf.writeln(line);
      }
      buf.writeln();
    }
    _writeSection(buf, sectionDescription, description);
    _writeSection(buf, sectionConfirmation, confirmation);
    _writeSection(buf, sectionImpact, impact);
    _writeSection(buf, sectionRecommendation, recommendation);
    return buf.toString().trimRight();
  }

  String _cvssText() {
    final parsed = cvss;
    if (parsed == null) return '`$cvssVector`';
    final score = parsed.score.toStringAsFixed(1);
    return '$score (${parsed.severity.label}) · `${parsed.vector}`';
  }

  String _cweLink() {
    final label = cweName.isEmpty ? 'CWE-$cweId' : 'CWE-$cweId — $cweName';
    return '[$label]($cweUrl)';
  }

  void _writeSection(StringBuffer buf, String title, String text) {
    buf.writeln('## $title');
    if (text.trim().isNotEmpty) {
      buf.writeln();
      buf.writeln(text.trim());
    }
    buf.writeln();
  }

  FindingSpec copyWith({
    String? heading,
    String? scopeObject,
    String? cvssVector,
    int? cweId,
    bool clearCwe = false,
    String? cweName,
    List<String>? cveIds,
    String? description,
    String? confirmation,
    String? impact,
    String? recommendation,
    RetestStatus? retest,
    String? retestNote,
    String? testId,
  }) {
    return FindingSpec(
      heading: heading ?? this.heading,
      scopeObject: scopeObject ?? this.scopeObject,
      cvssVector: cvssVector ?? this.cvssVector,
      cweId: clearCwe ? null : (cweId ?? this.cweId),
      cweName: cweName ?? this.cweName,
      cveIds: cveIds ?? this.cveIds,
      description: description ?? this.description,
      confirmation: confirmation ?? this.confirmation,
      impact: impact ?? this.impact,
      recommendation: recommendation ?? this.recommendation,
      retest: retest ?? this.retest,
      retestNote: retestNote ?? this.retestNote,
      testId: testId ?? this.testId,
    );
  }
}
