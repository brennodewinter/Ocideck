import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/services/audit_dossier.dart';
import 'package:ocideck/services/evidence_hash_service.dart';
import 'package:ocideck/services/miauw_compliance_analyzer.dart';
import 'package:ocideck/utils/asn1_der.dart';

const _sha512Oid = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03];
const _idSignedData = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02];
const _idCtTstInfo = [
  0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x09, 0x10, 0x01, 0x04, //
];

List<int> _bytesFromHex(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

/// A structurally-faithful RFC 3161 token whose message imprint is [hash],
/// base64url-encoded exactly as the deck stores it (see rfc3161_timestamp_test
/// for the wire shape). The CMS signature is not present — matching how the app
/// only checks the imprint, never the TSA signature.
String _tsr(List<int> hash, {String genTime = '20260712120000Z'}) {
  final tstInfo = derSequence([
    derInteger(1),
    derOid(const [0x2b, 0x06, 0x01]),
    derSequence([
      derSequence([derOid(_sha512Oid), derNull()]),
      derOctetString(hash),
    ]),
    derInteger(42),
    derTlv(0x18, genTime.codeUnits),
  ]);
  final token = derSequence([
    derOid(_idSignedData),
    derTlv(
      0xa0,
      derSequence([
        derTlv(
          0x31,
          derSequence([
            derSequence([derOid(_sha512Oid), derNull()]),
          ]),
        ),
        derSequence([
          derOid(_idCtTstInfo),
          derTlv(0xa0, derOctetString(tstInfo)),
        ]),
      ]),
    ),
  ]);
  return base64Url.encode(token);
}

/// The seal hash used by [sealedDeck], as raw bytes — a token built over these
/// bytes has a message imprint that matches the deck's seal.
final _sealHashBytes = _bytesFromHex('abc123def456');

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

    test('a matching token is reported present but not signature-verified', () {
      final md = buildAuditDossier(sealedDeck(tsr: _tsr(_sealHashBytes)));
      expect(
        md,
        contains('RFC 3161-tijdstempel:** aanwezig; imprint komt overeen'),
      );
      expect(md, contains('TSA-handtekening niet in-app geverifieerd'));
      // The claimed genTime is surfaced as a claim, not a checked fact.
      expect(md, contains('Getijdstempeld op (claim)'));
    });

    test('a token whose imprint does not match the seal is flagged', () {
      // A structurally-valid token over different bytes than the seal hash.
      final md = buildAuditDossier(
        sealedDeck(tsr: _tsr(_bytesFromHex('0011223344'))),
      );
      expect(md, contains('imprint komt niet overeen met de zegel-hash'));
    });

    test('a malformed token string is flagged, not reported as anchored', () {
      final md = buildAuditDossier(sealedDeck(tsr: 'not-a-valid-token'));
      expect(md, contains('imprint komt niet overeen met de zegel-hash'));
    });

    test('never claims unverified external time-anchoring', () {
      final md = buildAuditDossier(sealedDeck(tsr: _tsr(_sealHashBytes)));
      // The old wording overstated what was checked.
      expect(md, isNot(contains('verankert die hash extern in de tijd')));
      // Instead it states the honest limitation.
      expect(md, contains('geen geverifieerd feit'));
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
