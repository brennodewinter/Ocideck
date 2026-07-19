import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/storage_connection.dart';
import '../services/s3/s3_service.dart';
import 'settings_provider.dart';

/// Bouwt een [S3Service] voor één S3-verbinding: de opgeslagen
/// bucketconfiguratie plus de secret access key uit de keychain. Geeft `null`
/// wanneer de verbinding niet (meer) bestaat, half is ingevuld, of er nog geen
/// sleutel is opgeslagen.
///
/// Gekeyd op verbindings-id en niet op de bucket zelf, om dezelfde reden als bij
/// `webdavServiceProvider`: de id blijft gelijk als de gebruiker het endpoint
/// corrigeert, zodat een geopend deck zijn bron niet kwijtraakt bij een
/// hersteld typefoutje.
final s3ServiceProvider = FutureProvider.family<S3Service?, String>((
  ref,
  connectionId,
) async {
  final connection = ref.watch(settingsProvider).connectionById(connectionId);
  if (connection is! S3Connection || !connection.isConfigured) return null;
  final bucket = connection.bucket;
  final secret = await ref
      .read(settingsProvider.notifier)
      .readS3SecretKey(bucket.endpoint, bucket.accessKeyId);
  if (secret == null || secret.isEmpty) return null;
  return S3Service(bucket: bucket, secretAccessKey: secret);
});

/// De verbinding waarmee de app werkt als de gebruiker niet is gevraagd te
/// kiezen: de bovenste bruikbare S3-verbinding, of `null`.
final primaryS3ConnectionProvider = Provider<S3Connection?>(
  (ref) =>
      ref.watch(settingsProvider).primaryOf(StorageConnectionKind.s3)
          as S3Connection?,
);

/// Alle bruikbare S3-verbindingen, in de volgorde die de gebruiker sleepte —
/// de lijst die de keuzedialoog toont.
final s3ConnectionsProvider = Provider<List<S3Connection>>(
  (ref) => ref.watch(settingsProvider).connectionsOf<S3Connection>(),
);

/// Listing van één prefix (pad relatief aan de wortel) voor de bladeraar.
/// `autoDispose` zodat een gesloten dialoog de cache niet vasthoudt.
///
/// De sleutel draagt de verbinding mee: twee buckets met dezelfde mapnaam
/// leverden anders elkaars inhoud op uit de cache.
typedef S3ListingKey = ({String connectionId, String remotePath});

final s3ListingProvider = FutureProvider.autoDispose
    .family<List<S3Entry>, S3ListingKey>((ref, key) async {
      final service = await ref.watch(
        s3ServiceProvider(key.connectionId).future,
      );
      if (service == null) {
        throw S3Exception(S3Error.config, 'Geen S3-bucket ingesteld');
      }
      return service.list(key.remotePath);
    });
