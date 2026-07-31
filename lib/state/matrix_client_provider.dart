import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../collab/matrix_client.dart';
import '../collab/matrix_http_transport.dart';
import '../models/matrix_settings.dart';
import 'settings_provider.dart';

/// Bouwt de app-globale [MatrixClient] uit het geconfigureerde account plus het
/// access-token uit de keychain, over de platform-transport (SSRF-gepind op
/// dart:io, browser-fetch op web). Geeft `null` wanneer geen account is
/// geconfigureerd of er nog geen token is opgeslagen. Wordt herbouwd zodra het
/// account wijzigt (de instellingen-provider).
///
/// De collab-sessieprovider leest dit om over de self-encrypted relay te hosten
/// of joinen. Eén client per app, gedeeld over sessies en tabbladen: de
/// CS-aanroepen zijn zustandsloos op de client — elke `MatrixRelayTransport`
/// houdt zijn eigen sync-cursor — dus delen is veilig én hergebruikt de
/// verbinding. De socket leeft mee met de provider; dezelfde afweging als
/// `webdavServiceProvider`.
final matrixClientProvider = FutureProvider<MatrixClient?>((ref) async {
  final account = ref.watch(matrixAccountProvider);
  if (account == null || !account.isConfigured) return null;
  final token = await ref.read(settingsProvider.notifier).matrixToken(account);
  if (token == null || token.isEmpty) return null;
  return buildMatrixClient(account: account, token: token);
});

/// The app-global Matrix account, or null. A thin read over [settingsProvider] so
/// consumers — the client provider, the collab session provider — depend on just
/// the account, and a test can override this one value rather than stand up all of
/// settings (which is backed by a process-wide `SharedPreferences` singleton).
final matrixAccountProvider = Provider<MatrixServer?>(
  (ref) => ref.watch(settingsProvider).matrixAccount,
);

/// Bouw een [MatrixClient] voor [account] met [token]. De [transport] is
/// injecteerbaar zodat dit zonder socket te toetsen is; de provider roept het aan
/// met de productie-transport. Werpt [MatrixException] (`config`) wanneer het
/// account geen geldige homeserver-origin heeft.
MatrixClient buildMatrixClient({
  required MatrixServer account,
  required String? token,
  MatrixHttpTransport? transport,
}) {
  final origin = account.origin;
  if (origin == null) {
    throw const MatrixException(
      MatrixErrorKind.config,
      'homeserver not configured',
    );
  }
  return MatrixClient(
    transport: transport ?? createMatrixHttpTransport(account),
    homeserver: origin,
    accessToken: token,
  );
}
