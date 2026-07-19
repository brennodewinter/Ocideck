import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/net_guard.dart';

/// Vraagt of de gebruiker dít certificaat wil vertrouwen, en toont waarop hij
/// die keuze kan baseren.
///
/// Het geval: een zelf gehoste server met een certificaat dat geen erkende
/// uitgever heeft ondertekend. De verbinding weigeren zou die hele populatie
/// buitensluiten; alles doorlaten wat zelfondertekend is, zou de beveiliging
/// weggooien — dan accepteert de app óók het certificaat van iemand die
/// tussen jou en de server zit.
///
/// Dus: precies dit ene certificaat, herkend aan zijn vingerafdruk. Die staat
/// hier voluit, want de enige manier waarop de gebruiker dit goed kán
/// beoordelen is door hem te vergelijken met wat zijn server zelf toont. Dat
/// staat er ook bij — een dialoog die alleen "vertrouwen?" vraagt, leert
/// niemand iets en wordt weggeklikt.
class CertificateTrustDialog extends StatelessWidget {
  final X509Certificate certificate;
  final String host;

  const CertificateTrustDialog({
    super.key,
    required this.certificate,
    required this.host,
  });

  /// Toont de dialoog. Geeft de vingerafdruk terug wanneer de gebruiker
  /// vertrouwt, of `null` bij annuleren.
  static Future<String?> show(
    BuildContext context, {
    required X509Certificate certificate,
    required String host,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) =>
          CertificateTrustDialog(certificate: certificate, host: host),
    );
  }

  /// De vingerafdruk in paren van twee, zoals elk ander gereedschap hem toont —
  /// zo is hij met het oog te vergelijken in plaats van 64 tekens achter
  /// elkaar.
  static String groupFingerprint(String hex) {
    final out = StringBuffer();
    for (var i = 0; i < hex.length; i += 2) {
      if (i > 0) out.write(i % 16 == 0 ? '\n' : ':');
      out.write(hex.substring(i, i + 2 > hex.length ? hex.length : i + 2));
    }
    return out.toString().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fingerprint = NetGuard.certificateFingerprint(certificate);
    return AlertDialog(
      title: Text(l10n.d('Certificaat vertrouwen?')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Het certificaat van deze server is niet ondertekend door een erkende uitgever. Dat is gewoon bij een zelf gehoste server, maar het is ook hoe een afgeluisterde verbinding eruitziet.',
              ),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.d(
                'Vergelijk de vingerafdruk hieronder met wat je server zelf toont. Komen ze overeen, dan praat je met de juiste machine.',
              ),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 14),
            _row(l10n.d('Server'), host),
            _row(l10n.d('Uitgegeven aan'), certificate.subject),
            _row(l10n.d('Uitgegeven door'), certificate.issuer),
            _row(
              l10n.d('Geldig tot'),
              certificate.endValidity.toLocal().toString().split('.').first,
            ),
            const SizedBox(height: 10),
            Text(
              l10n.d('Vingerafdruk (SHA-256)'),
              style: TextStyle(fontSize: 11, color: AppTheme.slate500),
            ),
            const SizedBox(height: 4),
            SelectableText(
              groupFingerprint(fingerprint),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.d(
                'Alleen dit ene certificaat wordt vertrouwd. Vervangt de server het later, dan vraagt OciDeck het opnieuw.',
              ),
              style: TextStyle(fontSize: 11, color: AppTheme.slate500),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.t('cancel')),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, fingerprint),
          child: Text(l10n.d('Vertrouwen')),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: AppTheme.slate500),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 11))),
      ],
    ),
  );
}
