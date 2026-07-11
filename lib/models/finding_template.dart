import 'finding_spec.dart';

/// A reusable **finding template** (PENTEST_MIAUW §17): a finding stored as a
/// plain Markdown file with structured YAML front matter, so it is git-friendly,
/// diffable, importable, and survives tool abandonment. A tester pulls a
/// template into an engagement and specialises it (§10.6 upgraded to a
/// first-class, shareable library).
///
/// On disk:
/// ```markdown
/// ---
/// title: SQL injection
/// severity: Critical
/// cvss_vector: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N
/// cvss_version: 4.0
/// cwe: CWE-89 — Improper Neutralization of SQL
/// references:
///   - https://owasp.org/www-community/attacks/SQL_Injection
/// ---
/// ## Description
/// …
/// ## Confirmation (reproduction)
/// …
/// ## Possible impact
/// …
/// ## Recommendation
/// …
/// ```
///
/// The body reuses a finding's [FindingSpec] section layout, so a template
/// instantiates straight into a `finding` slide via [toFindingSpec].
class FindingTemplate {
  const FindingTemplate({
    this.id = '',
    this.title = '',
    this.severity = '',
    this.cvssVector = '',
    this.cvssVersion = '4.0',
    this.cweId,
    this.cweName = '',
    this.references = const [],
    this.description = '',
    this.confirmation = '',
    this.impact = '',
    this.recommendation = '',
  });

  /// A stable slug used to identify the template in the library.
  final String id;
  final String title;

  /// A human severity label (informational only — a finding's real severity is
  /// derived from its CVSS vector, never from this).
  final String severity;

  final String cvssVector;

  /// The CVSS version the vector uses. v4.0 only for new findings (§14); the
  /// field is kept so imported v3.1 templates still round-trip their metadata.
  final String cvssVersion;

  final int? cweId;
  final String cweName;
  final List<String> references;

  final String description;
  final String confirmation;
  final String impact;
  final String recommendation;

  static final _reCwe = RegExp(r'CWE-(\d+)');
  static final _reCweName = RegExp(r'—\s*(.+)$');

  /// Parse a template file (front matter + Markdown body). Front matter is read
  /// with the same simple line-by-line `key: value` scan the deck parser uses
  /// (no full YAML), plus a `- item` list for `references`. The body is parsed
  /// with [FindingSpec.parse] so the section layout stays shared with findings.
  factory FindingTemplate.parse(String content, {String id = ''}) {
    var title = '';
    var severity = '';
    var cvssVector = '';
    var cvssVersion = '4.0';
    int? cweId;
    var cweName = '';
    final references = <String>[];
    var body = content;

    if (content.startsWith('---\n')) {
      final end = content.indexOf('\n---\n', 4);
      if (end != -1) {
        final front = content.substring(4, end);
        body = content.substring(end + 5);
        var inReferences = false;
        for (final raw in front.split('\n')) {
          final line = raw.trimRight();
          final listItem = line.trimLeft();
          if (inReferences && listItem.startsWith('- ')) {
            references.add(listItem.substring(2).trim());
            continue;
          }
          inReferences = false;
          final colon = line.indexOf(':');
          if (colon <= 0) continue;
          final key = line.substring(0, colon).trim();
          final value = line.substring(colon + 1).trim();
          switch (key) {
            case 'title':
              title = value;
            case 'severity':
              severity = value;
            case 'cvss_vector':
              cvssVector = value;
            case 'cvss_version':
              cvssVersion = value.isEmpty ? '4.0' : value;
            case 'cwe':
              cweId = int.tryParse(_reCwe.firstMatch(value)?.group(1) ?? '');
              cweName = _reCweName.firstMatch(value)?.group(1)?.trim() ?? '';
            case 'references':
              inReferences = true;
              if (value.isNotEmpty) references.add(value);
          }
        }
      }
    }

    final spec = FindingSpec.parse(body);
    return FindingTemplate(
      id: id,
      title: title,
      severity: severity,
      cvssVector: cvssVector,
      cvssVersion: cvssVersion,
      cweId: cweId,
      cweName: cweName,
      references: references,
      description: spec.description,
      confirmation: spec.confirmation,
      impact: spec.impact,
      recommendation: spec.recommendation,
    );
  }

  /// A finding built from this template: the title becomes the heading, the
  /// CVSS/CWE metadata and the sections carry over; the scope object and CVE ids
  /// stay empty for the tester to fill per engagement.
  FindingSpec toFindingSpec() => FindingSpec(
    heading: title,
    cvssVector: cvssVector,
    cweId: cweId,
    cweName: cweName,
    description: description,
    confirmation: confirmation,
    impact: impact,
    recommendation: recommendation,
  );

  /// Serialise back to the on-disk template form (front matter + body), so a
  /// template stays diffable and exportable.
  String toMarkdown() {
    final buf = StringBuffer('---\n');
    if (title.isNotEmpty) buf.writeln('title: $title');
    if (severity.isNotEmpty) buf.writeln('severity: $severity');
    if (cvssVector.isNotEmpty) buf.writeln('cvss_vector: $cvssVector');
    buf.writeln('cvss_version: $cvssVersion');
    if (cweId != null) {
      final name = cweName.isEmpty ? '' : ' — $cweName';
      buf.writeln('cwe: CWE-$cweId$name');
    }
    if (references.isNotEmpty) {
      buf.writeln('references:');
      for (final ref in references) {
        buf.writeln('  - $ref');
      }
    }
    buf.writeln('---');
    // Reuse the finding section layout for the body (headingless).
    buf.write(
      FindingSpec(
        description: description,
        confirmation: confirmation,
        impact: impact,
        recommendation: recommendation,
      ).toMarkdown(),
    );
    return buf.toString();
  }

  /// Free-text haystack for the library search (title, CWE, severity).
  String get searchText => [
    title,
    severity,
    if (cweId != null) 'CWE-$cweId',
    cweName,
  ].join(' ').toLowerCase();
}
