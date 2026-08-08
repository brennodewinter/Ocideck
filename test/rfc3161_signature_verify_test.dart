import 'dart:convert';
import 'dart:typed_data';

import 'package:ocideck/services/rfc3161_timestamp.dart';
import 'package:flutter_test/flutter_test.dart';

/// Self-contained test voor CMS-signatuurverificatie.
///
/// Omdat de pure-Dart `cryptography`-package geen RSA `sign()` of
/// `newKeyPair()` ondersteunt, is het test-token pre-gegenereerd met openssl
/// (`openssl ts -reply`) en als base64 ingebed. De test decodeert het, roept
/// [verifyTimeStampSignature] aan, en controleert dat een geldig token wordt
/// geaccepteerd en een gemanipuleerd token wordt afgewezen.
void main() {
  // Een echt RFC 3161-token, gegenereerd met `openssl ts -reply` tegen een
  // self-signed TSA-certificaat (RSA-2048, sha256WithRSAEncryption). Het token
  // bevat het TSA-certificaat, de TSTInfo, en de CMS-handtekening.
  //
  // Gegenereerd met:
  //   openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048
  //   openssl req -new -x509 -key key.pem -out cert.pem -config tsa_cert.cnf
  //   openssl ts -query -data test_data.txt -sha256 -cert -out tsq.der
  //   openssl ts -reply -queryfile tsq.der -out tsr.der -config tsa.cnf
  //   base64 -i tsr.der
  const validTokenBase64 =
      ''
      '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';

  group('verifyTimeStampSignature', () {
    test('accepteert een geldig openssl-token', () async {
      final token = Uint8List.fromList(base64.decode(validTokenBase64));
      final status = await verifyTimeStampSignature(token);
      expect(status, TimeStampSignatureStatus.verified);
    });

    test('wijst een gemanipuleerd token af', () async {
      final token = Uint8List.fromList(base64.decode(validTokenBase64));
      // Flip een byte in de signature — de handtekeningverificatie moet falen.
      final tampered = Uint8List.fromList(token);
      tampered[tampered.length - 1] ^= 0x01;
      final status = await verifyTimeStampSignature(tampered);
      expect(status, TimeStampSignatureStatus.invalid);
    });

    test('retourneert notSigned voor lege data', () async {
      final status = await verifyTimeStampSignature(Uint8List(0));
      expect(status, TimeStampSignatureStatus.notSigned);
    });
  });
}
