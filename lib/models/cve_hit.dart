/// One CVE returned by an online lookup source (see
/// `services/cve_search_service.dart`): the id plus a short description and CVSS
/// score/severity for context. Only the **id** is attached to a finding (the
/// finding's own CVSS 4.0 vector is never overwritten — a CVE gives a v3.x
/// score); the description/score just help the tester confirm the right CVE.
class CveHit {
  const CveHit({
    required this.id,
    this.description = '',
    this.cvssScore,
    this.cvssSeverity = '',
    this.published = '',
  });

  /// The canonical CVE id, e.g. `CVE-2021-44228`.
  final String id;

  /// A short English description of the vulnerability.
  final String description;

  /// The CVE's CVSS base score (v3.x), or null when unknown.
  final double? cvssScore;

  /// The CVE's CVSS severity band (e.g. `CRITICAL`), or empty when unknown.
  final String cvssSeverity;

  /// The published date (ISO string), or empty when unknown.
  final String published;

  /// The canonical NVD detail page for this CVE.
  String get url => 'https://nvd.nist.gov/vuln/detail/$id';
}
