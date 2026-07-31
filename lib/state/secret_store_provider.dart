import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/secret_store.dart';

/// De app-brede [SecretStore]: de enige weg naar de OS-sleutelbos. Als provider
/// — in plaats van een losse `SecretStore()` op elke plek — zodat een test hem
/// kan vervangen door één met een nep-sleutelbos, en de collab-sessieprovider
/// zijn apparaatsleutels (`loadOrCreateDeviceKeys`) toetsbaar kan laden zonder
/// echte keychain. Standaard de echte sleutelbos.
final secretStoreProvider = Provider<SecretStore>((ref) => SecretStore());
