import 'dart:convert';

import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

const String _fid = 'mfrggzdfmztwq2lknnwg23tpoa';
const String _sid = 'nvqwy3dpoixxg5dfonzgc3tjnq';
final String _secret = 'ma' * 26;

IntakeReceipt _receipt() => IntakeReceipt(
  host: 'intake.example.org',
  fid: _fid,
  withdrawalSecret: _secret,
  note: const IntakeArrivalNote(
    sid: _sid,
    at: '2026-10-04T09:30:12Z',
    ciphertextSha256:
        'abababababababababababababababababababababababababababababababab',
    contact: 'redactie@example.org',
  ),
);

Map<String, Object?> _json() =>
    jsonDecode(_receipt().toJsonText()) as Map<String, Object?>;

void main() {
  group('the receipt a respondent keeps (§5.8)', () {
    test('is written and read back', () {
      final back = parseIntakeReceipt(_receipt().toJsonText())!;
      expect(back.host, 'intake.example.org');
      expect(back.fid, _fid);
      expect(back.withdrawalSecret, _secret);
      expect(back.sid, _sid);
      expect(back.note.at, '2026-10-04T09:30:12Z');
      expect(back.note.contact, 'redactie@example.org');
      expect(back.note.ciphertextSha256, 'ab' * 32);
    });

    test('has exactly these members, in this version', () {
      expect(_json().keys.toSet(), {
        'v',
        'host',
        'fid',
        'withdrawal_secret',
        'note',
      });
      expect(_json()['v'], kIntakeReceiptVersion);
      expect(kIntakeReceiptVersion, 1);
      expect(kIntakeReceiptSuffix, '.receipt.json');
      expect((_json()['note']! as Map).keys.toSet(), {
        'sid',
        'at',
        'ciphertext_sha256',
        'contact',
      });
    });

    test('is readable by a person: indented', () {
      expect(_receipt().toJsonText(), contains('\n  "host"'));
    });

    test('is refused when a member is changed, missing or added', () {
      Map<String, Object?> with_(String k, Object? v) => {..._json(), k: v};
      final bad = <String, Map<String, Object?>>{
        'another version': with_('v', 2),
        'no version': {..._json()}..remove('v'),
        'no host': {..._json()}..remove('host'),
        'no fid': {..._json()}..remove('fid'),
        'no secret': {..._json()}..remove('withdrawal_secret'),
        'no note': {..._json()}..remove('note'),
        'an extra member': with_('extra', 1),
        'a host in capitals': with_('host', 'Intake.Example.org'),
        'a host that is a path': with_('host', 'intake.example.org/x'),
        'a host that is not text': with_('host', 5),
        'a form id that is too short': with_('fid', _fid.substring(1)),
        'a form id in capitals': with_('fid', _fid.toUpperCase()),
        'a secret that is too short': with_(
          'withdrawal_secret',
          _secret.substring(1),
        ),
        'a secret in capitals': with_(
          'withdrawal_secret',
          _secret.toUpperCase(),
        ),
        'a secret that is not canonical': with_(
          'withdrawal_secret',
          '${_secret.substring(0, 51)}b',
        ),
        'a note that is not an object': with_('note', 'x'),
      };
      bad.forEach((name, json) {
        expect(parseIntakeReceipt(jsonEncode(json)), isNull, reason: name);
      });
    });

    test('is refused when the note is not exactly a note', () {
      Map<String, Object?> note(void Function(Map<String, Object?>) edit) {
        final n = Map<String, Object?>.of(
          _json()['note']! as Map<String, Object?>,
        );
        edit(n);
        return {..._json(), 'note': n};
      }

      final bad = <String, Map<String, Object?>>{
        'no sid': note((n) => n.remove('sid')),
        'no time': note((n) => n.remove('at')),
        'no hash': note((n) => n.remove('ciphertext_sha256')),
        'no contact': note((n) => n.remove('contact')),
        'an extra member': note((n) => n['sig'] = 'x'),
        'a time with an offset': note(
          (n) => n['at'] = '2026-10-04T09:30:12+00:00',
        ),
        'a hash in capitals': note((n) => n['ciphertext_sha256'] = 'AB' * 32),
        'a sid that is not an id': note((n) => n['sid'] = 'x'),
        'a contact with a control character': note(
          (n) => n['contact'] = 'a\nb',
        ),
      };
      bad.forEach((name, json) {
        expect(parseIntakeReceipt(jsonEncode(json)), isNull, reason: name);
      });
    });

    test('is not a receipt when it is not JSON, not an object or too long', () {
      expect(parseIntakeReceipt('nope'), isNull);
      expect(parseIntakeReceipt('[]'), isNull);
      expect(parseIntakeReceipt(''), isNull);
      expect(
        parseIntakeReceipt(
          jsonEncode({..._json(), 'pad': 'x' * kIntakeMaxJsonBytes}),
        ),
        isNull,
      );
    });
  });
}
