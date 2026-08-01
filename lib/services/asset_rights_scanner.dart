import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import '../models/asset_rights.dart';
import 'image_service.dart';

class AssetRightsScanner {
  const AssetRightsScanner();

  static const version = 'local-1';

  Future<AssetRightsAssessment> scan(
    Uint8List bytes, {
    required String filename,
    AssetRightsProvenance provenance = const AssetRightsProvenance(),
    List<AssetRightsDisposition> dispositions = const [],
    DateTime? now,
  }) async {
    final hash = sha256.convert(bytes).toString();
    final mime = ImageService.imageMimeFromBytes(bytes.take(16).toList());
    if (mime == null) {
      throw const FormatException('Geen ondersteunde afbeelding');
    }
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Afbeelding is niet decodeerbaar');
    }

    final metadata = _rightsMetadata(decoded);
    final signals = <AssetRightsSignal>[];
    if (!provenance.hasRightsEvidence) {
      signals.add(
        _signal(
          'rights.missing_evidence',
          AssetRightsRisk.review,
          'Er is geen licentie met bewijsstuk vastgelegd.',
          '${provenance.license ?? ''}|${provenance.licenseEvidence ?? ''}',
        ),
      );
    }
    if (provenance.licenseExpiresAt case final expiry?) {
      if (!expiry.isAfter((now ?? DateTime.now()).toUtc())) {
        signals.add(
          _signal(
            'rights.license_expired',
            AssetRightsRisk.high,
            'De vastgelegde licentie is verlopen.',
            expiry.toUtc().toIso8601String(),
          ),
        );
      }
    }
    if (metadata.isNotEmpty) {
      signals.add(
        _signal(
          'rights.embedded_notice',
          AssetRightsRisk.review,
          'De afbeelding bevat ingebedde makers- of auteursrechtgegevens.',
          jsonEncode(metadata),
          evidence: metadata,
        ),
      );
    }
    final lowerName = filename.toLowerCase();
    if (const [
      'getty',
      'shutterstock',
      'alamy',
      'adobe-stock',
      'istock',
    ].any(lowerName.contains)) {
      signals.add(
        _signal(
          'rights.stock_marker',
          AssetRightsRisk.high,
          'De bestandsnaam bevat een verwijzing naar een beeldbank.',
          lowerName,
          evidence: {'filename': filename},
        ),
      );
    }

    return AssetRightsAssessment(
      sha256: hash,
      mimeType: mime,
      byteLength: bytes.length,
      width: decoded.width,
      height: decoded.height,
      scannerVersion: version,
      scannedAt: (now ?? DateTime.now()).toUtc(),
      provenance: provenance,
      signals: signals,
      dispositions: dispositions,
    );
  }

  static Map<String, String> _rightsMetadata(img.Image image) {
    final result = <String, String>{};
    const names = ['Artist', 'Copyright', 'ImageDescription', 'Software'];
    for (final name in names) {
      final value = image.exif.imageIfd[name]?.toString().trim();
      if (value != null && value.isNotEmpty) result[name] = value;
    }
    final text = image.textData;
    if (text != null) {
      for (final entry in text.entries) {
        final key = entry.key.toLowerCase();
        if (key.contains('author') ||
            key.contains('artist') ||
            key.contains('copyright') ||
            key.contains('license')) {
          final value = entry.value.trim();
          if (value.isNotEmpty) result['text:${entry.key}'] = value;
        }
      }
    }
    return result;
  }

  static AssetRightsSignal _signal(
    String rule,
    AssetRightsRisk risk,
    String message,
    String evidenceSeed, {
    Map<String, String> evidence = const {},
  }) => AssetRightsSignal(
    ruleId: rule,
    risk: risk,
    message: message,
    fingerprint: sha256
        .convert(utf8.encode('$rule\u0000$evidenceSeed'))
        .toString(),
    evidence: evidence,
  );
}
