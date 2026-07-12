import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/services/audit_dossier.dart';
import 'package:ocideck/services/evidence_hash_service.dart';
import 'package:ocideck/services/miauw_compliance_analyzer.dart';

/// The audit-dossier index (PENTEST_MIAUW §10.11) is a deterministic Markdown
/// restatement of the report identity, seal facts, summary, compliance overview
/// and evidence hashes that travels inside the audit package.
void main() {
  Deck sealedDeck({String tsr = ''}) => Deck(
    title: 'Pentest Acme',
    author: 'Jip Tester',
    organization: 'Acme BV',
    version: '1.0',
    date: '2026-07-12',
    finalized: true,
    sealHash: 'abc123def456',
    sealAlgo: 'sha-512',
    sealAt: '2026-07-12T10:00:00Z',
    sealTimestampToken: tsr,
  );

  group('buildAuditDossier', () {
    test('states the report identity', () {
      final md = buildAuditDossier(sealedDeck());
      expect(md, contains('# Auditdossier — Pentest Acme'));
      expect(md, contains('Jip Tester'));
      expect(md, contains('Acme BV'));
    });

    test('a sealed deck shows the seal facts', () {
      final md = buildAuditDossier(sealedDeck());
      expect(md, contains('Gefinaliseerd:** ja'));
      expect(md, contains('abc123def456'));
      expect(md, contains('sha-512'));
      expect(md, contains('RFC 3161-tijdstempel:** afwezig'));
    });

    test('an RFC 3161 token is reported as present', () {
      final md = buildAuditDossier(sealedDeck(tsr: 'TOKENBASE64URL'));
      expect(md, contains('RFC 3161-tijdstempel:** aanwezig'));
    });

    test('an unsealed deck warns instead of stating a seal', () {
      final md = buildAuditDossier(const Deck(title: 'Concept'));
      expect(md, contains('Gefinaliseerd:** nee'));
      expect(md, contains('nog niet gefinaliseerd'));
      expect(md, isNot(contains('Zegel-hash')));
    });

    test('includes the management summary and MIAUW compliance counts', () {
      final deck = sealedDeck();
      final md = buildAuditDossier(deck);
      expect(md, contains('## Managementsamenvatting'));
      expect(md, contains('Bevindingen totaal:** 0'));
      final total = const MiauwComplianceAnalyzer().analyze(deck).total;
      expect(md, contains('## MIAUW-naleving ($total EIS)'));
      expect(md, contains('Voldaan:'));
      expect(md, contains('Openstaand:'));
      expect(md, contains('Uitgesloten:'));
    });

    test('renders the evidence hash table when hashes are supplied', () {
      final md = buildAuditDossier(
        sealedDeck(),
        evidenceHashes: const {
          'images/bewijs.png': EvidenceHashes(sha1: 'aa11', sha256: 'bb22'),
        },
      );
      expect(md, contains('images/bewijs.png'));
      expect(md, contains('aa11'));
      expect(md, contains('bb22'));
    });

    test('notes the absence of evidence hashes', () {
      final md = buildAuditDossier(sealedDeck());
      expect(md, contains('_Geen bewijsmateriaal met hashes._'));
    });
  });
}
