import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/dialogs/certificate_trust_dialog.dart';

/// Een certificaat zoals `dart:io` het aanbiedt, met vaste DER-bytes zodat de
/// vingerafdruk te narekenen is.
class _FakeCertificate implements X509Certificate {
  _FakeCertificate({
    required this.der,
    this.subject = '/CN=nextcloud.intern',
    this.issuer = '/CN=nextcloud.intern',
  });

  @override
  final Uint8List der;
  @override
  final String subject;
  @override
  final String issuer;

  @override
  DateTime get startValidity => DateTime.utc(2026, 1, 1);
  @override
  DateTime get endValidity => DateTime.utc(2027, 1, 1, 12, 30);
  @override
  String get pem => '-----BEGIN CERTIFICATE-----\n-----END CERTIFICATE-----';
  @override
  Uint8List get sha1 => Uint8List(20);
}

/// Het venster dat vraagt of één zelfondertekend certificaat vertrouwd mag
/// worden.
///
/// Dit is een beveiligingsbeslissing die de gebruiker alleen kan nemen als de
/// vingerafdruk die hij ziet dezelfde is als die er wordt vastgelegd. Toont het
/// venster iets anders dan het teruggeeft, dan vergelijkt hij met zijn server
/// en vertrouwt hij vervolgens iets anders — precies het geval waartegen dit
/// venster bestaat.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  final der = Uint8List.fromList(List<int>.generate(64, (i) => i));
  final verwacht = sha256.convert(der).toString().toLowerCase();

  Future<List<String?>> open(
    WidgetTester tester, {
    X509Certificate? certificate,
    String host = 'nextcloud.intern',
  }) async {
    final uitkomst = <String?>[];
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => uitkomst.add(
                await CertificateTrustDialog.show(
                  context,
                  certificate: certificate ?? _FakeCertificate(der: der),
                  host: host,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(CertificateTrustDialog), findsOneWidget);
    return uitkomst;
  }

  /// De vingerafdruk zoals hij op het scherm staat, ontdaan van de opmaak.
  String getoondeVingerafdruk(WidgetTester tester) => tester
      .widget<SelectableText>(find.byType(SelectableText))
      .data!
      .replaceAll(RegExp(r'[:\n]'), '')
      .toLowerCase();

  testWidgets('Vertrouwen geeft precies de getoonde vingerafdruk terug', (
    tester,
  ) async {
    final uitkomst = await open(tester);

    expect(
      getoondeVingerafdruk(tester),
      verwacht,
      reason: 'wat op het scherm staat moet de SHA-256 van de DER zijn',
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Vertrouwen'));
    await tester.pumpAndSettle();

    expect(
      uitkomst.single,
      verwacht,
      reason: 'de vastgelegde afdruk moet dezelfde zijn als de vergeleken',
    );
  });

  testWidgets('Annuleren vertrouwt niets', (tester) async {
    final uitkomst = await open(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
    await tester.pumpAndSettle();

    expect(uitkomst, [null]);
  });

  testWidgets('het venster toont waarop de gebruiker kan oordelen', (
    tester,
  ) async {
    await open(
      tester,
      certificate: _FakeCertificate(
        der: der,
        subject: '/CN=dav.klant.nl',
        issuer: '/CN=Eigen CA',
      ),
      host: 'dav.klant.nl',
    );

    // Zonder deze vier is de vraag niet te beantwoorden.
    expect(find.text('dav.klant.nl'), findsOneWidget);
    expect(find.text('/CN=dav.klant.nl'), findsOneWidget);
    expect(find.text('/CN=Eigen CA'), findsOneWidget);
    expect(find.textContaining('2027-01-01'), findsOneWidget);
    // En de waarschuwing dat dit er ook uitziet als afluisteren.
    expect(
      find.textContaining('hoe een afgeluisterde verbinding eruitziet'),
      findsOneWidget,
    );
  });

  group('groupFingerprint', () {
    test('zet de afdruk in paren van twee, acht paren per regel', () {
      // Met het oog te vergelijken; 64 tekens achter elkaar is dat niet.
      expect(
        CertificateTrustDialog.groupFingerprint('0a1b2c3d4e5f60718293'),
        '0A:1B:2C:3D:4E:5F:60:71\n82:93',
      );
    });

    test('een oneven staart valt niet weg', () {
      // Zou de laatste halve byte verdwijnen, dan vergelijkt de gebruiker een
      // afdruk die niet compleet is.
      expect(CertificateTrustDialog.groupFingerprint('abc'), 'AB:C');
    });

    test('een lege afdruk levert een lege regel op', () {
      expect(CertificateTrustDialog.groupFingerprint(''), '');
    });
  });
}
