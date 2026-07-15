import 'dart:convert';
import 'dart:typed_data';

import '../models/deck.dart';
import '../models/eis_entry.dart';
import '../models/findings_summary_spec.dart';
import 'cvss/cvss4.dart';
import 'evidence_hash_service.dart';
import 'management_summary.dart';
import 'miauw_compliance_analyzer.dart';
import 'rfc3161_timestamp.dart';

/// The audit-dossier index (PENTEST_MIAUW §10.11): a deterministic Markdown
/// document that travels **inside** the one-click audit package next to the
/// sealed report and its evidence. It restates the report identity, the seal +
/// integrity facts, the management summary, the MIAUW compliance overview and
/// the evidence hash table, so an auditor holding only the package can see, at a
/// glance, what was delivered and how to verify it. Pure and network-free; the
/// caller supplies [evidenceHashes] because reading image bytes is IO.

/// Dutch severity-band labels for the summary (FIRST bands; `none` reads as
/// *Informatief*, matching the module's severity tokens).
String _severityLabel(Cvss4Severity s) => switch (s) {
  Cvss4Severity.critical => 'Kritiek',
  Cvss4Severity.high => 'Hoog',
  Cvss4Severity.medium => 'Middel',
  Cvss4Severity.low => 'Laag',
  Cvss4Severity.none => 'Informatief',
};

/// Builds the audit-dossier index Markdown for [deck]. [evidenceHashes] is keyed
/// by a file label (typically the evidence slide's image path) and rendered with
/// [evidenceHashTable]; [analyzer] is injectable for tests and defaults to the
/// bundled MIAUW catalog.
String buildAuditDossier(
  Deck deck, {
  Map<String, EvidenceHashes> evidenceHashes = const {},
  MiauwComplianceAnalyzer analyzer = const MiauwComplianceAnalyzer(),
}) {
  final summary = deckManagementSummary(deck);
  final compliance = analyzer.analyze(deck);
  final sealed = deck.finalized && deck.sealHash.trim().isNotEmpty;
  final b = StringBuffer();

  b.writeln('# Auditdossier — ${deck.title}');
  b.writeln();
  b.writeln(
    '> Automatisch samengesteld door OciDeck (MIAUW §10.11). Dit dossier '
    'bundelt het verzegelde rapport, het bewijsmateriaal en de hashtabellen '
    'in één versleutelbaar pakket.',
  );
  b.writeln();

  void meta(String key, String value) {
    if (value.trim().isNotEmpty) b.writeln('- **$key:** ${value.trim()}');
  }

  b.writeln('## Rapport');
  b.writeln();
  meta('Titel', deck.title);
  meta('Auteur', deck.author);
  meta('Organisatie', deck.organization);
  meta('Versie', deck.version);
  meta('Datum', deck.date);
  meta('TLP', deck.tlp.label);
  b.writeln();

  b.writeln('## Integriteit en verzegeling');
  b.writeln();
  b.writeln('- **Gefinaliseerd:** ${sealed ? 'ja' : 'nee'}');
  if (sealed) {
    meta('Zegel-algoritme', deck.sealAlgo);
    meta('Zegel-hash', deck.sealHash);
    meta('Verzegeld op', deck.sealAt);
    // The imprint is checked against the seal hash, but the token's CMS
    // signature and TSA certificate chain are deliberately NOT verified in-app
    // (see rfc3161_timestamp.dart, §8-A3). So genTime is the token's *claim*,
    // never assert external time-anchoring here — that would overstate what was
    // checked, exactly the badge the seal dialog refuses to show.
    final tsToken = _decodeTimestampToken(deck.sealTimestampToken);
    final tsParsed = tsToken == null ? null : parseTimeStampToken(tsToken);
    final tsMatches =
        tsToken != null && timeStampMatchesHash(tsToken, deck.sealHash);
    if (deck.sealTimestampToken.trim().isEmpty) {
      b.writeln('- **RFC 3161-tijdstempel:** afwezig');
    } else if (tsParsed == null || !tsMatches) {
      b.writeln(
        '- **RFC 3161-tijdstempel:** aanwezig, maar de imprint komt niet '
        'overeen met de zegel-hash — niet bruikbaar als tijdsbewijs',
      );
    } else {
      b.writeln(
        '- **RFC 3161-tijdstempel:** aanwezig; imprint komt overeen '
        '(TSA-handtekening niet in-app geverifieerd)',
      );
      meta('Getijdstempeld op (claim)', tsParsed.genTime.toIso8601String());
    }
    b.writeln();
    b.writeln(
      'Controleer de integriteit door de ${deck.sealAlgo}-hash van de '
      'gekanoniseerde rapportinhoud te herberekenen en te vergelijken met de '
      'zegel-hash hierboven. Een RFC 3161-token bindt die hash aan een '
      'tijdstip, maar OciDeck verifieert de TSA-handtekening en '
      'certificaatketen niet in-app; het getoonde tijdstip is dus een claim '
      'van het token, geen geverifieerd feit. Voor onweerlegbare '
      'tijdsverankering moet het token tegen de TSA worden geverifieerd.',
    );
  } else {
    b.writeln();
    b.writeln(
      '> Let op: dit rapport is nog niet gefinaliseerd en verzegeld — het '
      'dossier is dan geen bewijs van onveranderlijkheid.',
    );
  }
  b.writeln();

  b.writeln('## Managementsamenvatting');
  b.writeln();
  b.writeln('- **Bevindingen totaal:** ${summary.findingCount}');
  for (final band in FindingsSummarySpec.order) {
    b.writeln(
      '  - ${_severityLabel(band)}: ${summary.severities.countOf(band)}',
    );
  }
  b.writeln(
    '- **Scope-objecten getoetst:** '
    '${summary.scopeTestedCount}/${summary.scopeObjectCount}',
  );
  if (summary.standards.isNotEmpty) {
    b.writeln('- **Gebruikte standaarden:** ${summary.standards.join(', ')}');
  }
  b.writeln();

  b.writeln(
    '## MIAUW-naleving (${compliance.total} van $kMiauwFullSchemaSize EIS '
    'beoordeeld)',
  );
  b.writeln();
  if (compliance.total < kMiauwFullSchemaSize) {
    b.writeln(
      '> Let op: dit overzicht toetst een gecureerd deel '
      '(${compliance.total}) van het volledige MIAUW-schema van '
      '$kMiauwFullSchemaSize EIS. De overige '
      '${kMiauwFullSchemaSize - compliance.total} eisen zijn in deze versie '
      'niet beoordeeld — een all-green telling hieronder betekent dus niet '
      'dat het rapport volledig MIAUW-conform is.',
    );
    b.writeln();
  }
  b.writeln('- **Voldaan:** ${compliance.metCount}');
  if (compliance.confirmedCount > 0) {
    b.writeln(
      '  - waarvan handmatig bevestigd (niet uit inhoud afgeleid): '
      '${compliance.confirmedCount}',
    );
  }
  b.writeln('- **Openstaand:** ${compliance.openCount}');
  b.writeln('- **Uitgesloten:** ${compliance.waivedCount}');
  b.writeln();

  b.writeln('## Bewijs-hashes');
  b.writeln();
  final table = evidenceHashTable(evidenceHashes);
  b.writeln(table.isEmpty ? '_Geen bewijsmateriaal met hashes._' : table);
  b.writeln();

  return b.toString();
}

/// Decode the base64url-encoded RFC 3161 token as stored on the deck (see
/// [Deck.sealTimestampToken]); null when empty or malformed.
Uint8List? _decodeTimestampToken(String base64Token) {
  final trimmed = base64Token.trim();
  if (trimmed.isEmpty) return null;
  try {
    return base64Url.decode(trimmed);
  } on FormatException {
    return null;
  }
}
