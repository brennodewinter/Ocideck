// #2426: de certificatenlijst en de PDF-download. De PDF draagt een
// verificatiegeheim — de gateway levert alleen bytes die er echt als PDF
// uitzien, zodat geen afwijkende payload richting de viewer stroomt.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/services/ociserve/ociserve_gateway.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';

class _FakeTransport implements OciServeHttpTransport {
  final responses = <OciServeHttpResponse>[];
  final requests = <({String method, Uri url})>[];

  @override
  Future<OciServeHttpResponse> send({
    required String method,
    required Uri url,
    required bool trustedInternal,
    Map<String, String> headers = const {},
    List<int>? body,
    int maxResponseBytes = 0,
    Duration timeout = Duration.zero,
  }) async {
    requests.add((method: method, url: url));
    return responses.removeAt(0);
  }
}

OciServeHttpResponse _json(Object body, {int statusCode = 200}) =>
    OciServeHttpResponse(
      statusCode: statusCode,
      body: Uint8List.fromList(utf8.encode(jsonEncode(body))),
    );

final _pdfBytes = Uint8List.fromList(utf8.encode('%PDF-1.7 fake body'));

Map<String, Object?> _certificate({
  String id = 'cert-1',
  String status = 'issued',
  String? revokedAt,
  String? reason,
}) => {
  'id': id,
  'participant_id': 'p1',
  'title': 'BHV-certificaat',
  'description': '',
  'certificate_number': 'NR-42',
  'status': status,
  'issued_at': '2026-09-01T10:00:00Z',
  'revoked_at': revokedAt,
  'revocation_reason': reason,
  'created_at': '2026-09-01T10:00:00Z',
};

void main() {
  late _FakeTransport transport;
  late OciServeGateway gateway;

  setUp(() {
    transport = _FakeTransport();
    gateway = OciServeGateway(
      settings: const OciServeSettings(
        enabled: true,
        baseUrl: 'https://learn.example',
      ),
      transport: transport,
    );
  });

  test(
    'certificatenlijst roept de participant-route en parst de stukken',
    () async {
      transport.responses.add(
        _json({
          'certificates': [
            _certificate(),
            _certificate(
              id: 'cert-2',
              status: 'revoked',
              revokedAt: '2026-10-01T12:00:00Z',
              reason: 'Dubbel uitgegeven',
            ),
          ],
        }),
      );

      final list = await gateway.participantCertificates(
        accessToken: 'access',
        organizationId: 'org',
        participantId: 'p1',
      );

      expect(
        transport.requests.single.url.path,
        '/api/v1/organizations/org/participants/p1/certificates',
      );
      expect(list, hasLength(2));
      expect(list.first.title, 'BHV-certificaat');
      expect(list.first.certificateNumber, 'NR-42');
      expect(list.first.isRevoked, isFalse);
      expect(list.last.isRevoked, isTrue);
      expect(list.last.revocationReason, 'Dubbel uitgegeven');
    },
  );

  test('een afwijkende lijst faalt als ongeldig antwoord', () async {
    transport.responses.add(_json({'certificates': 'nope'}));

    expect(
      () => gateway.participantCertificates(
        accessToken: 'access',
        organizationId: 'org',
        participantId: 'p1',
      ),
      throwsA(isA<OciServeException>()),
    );
  });

  test('certificaat-PDF geeft de bytes als ze er als PDF uitzien', () async {
    transport.responses.add(
      OciServeHttpResponse(statusCode: 200, body: _pdfBytes),
    );

    final bytes = await gateway.certificatePdf(
      accessToken: 'access',
      organizationId: 'org',
      certificateId: 'cert-1',
    );

    expect(
      transport.requests.single.url.path,
      '/api/v1/organizations/org/certificates/cert-1/pdf',
    );
    expect(bytes, _pdfBytes);
  });

  test('een non-PDF payload verlaat de gateway niet', () async {
    transport.responses.add(
      OciServeHttpResponse(
        statusCode: 200,
        body: Uint8List.fromList(utf8.encode('<html>oops</html>')),
      ),
    );

    expect(
      () => gateway.certificatePdf(
        accessToken: 'access',
        organizationId: 'org',
        certificateId: 'cert-1',
      ),
      throwsA(isA<OciServeException>()),
    );
  });
}
