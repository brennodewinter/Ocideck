// Part of the settings_provider library — see ../settings_provider.dart.
// Split out for navigability (het app-globale Matrix-account voor realtime
// samenwerken); alle imports leven in het hoofdbestand.
part of '../settings_provider.dart';

/// Het app-globale Matrix-account. Spiegelt bewust [setAiSettings]/[setAiApiKey]:
/// de niet-geheime configuratie mag in prefs, het access-token nooit — dat gaat
/// versleuteld naar de keychain (`SecretStore`).
extension SettingsNotifierMatrix on SettingsNotifier {
  /// Bewaar (of wis met `null`) het Matrix-account in het prefs-domein — zonder
  /// access-token, dat gaat via [setMatrixToken] naar de keychain. Wist enkel deze
  /// key, nooit het hele domein.
  Future<void> setMatrixAccount(MatrixServer? account) async {
    currentState = currentState.copyWith(
      matrixAccount: account,
      clearMatrixAccount: account == null,
    );
    await _persist('setMatrixAccount', (prefs) async {
      if (account == null) {
        await prefs.remove('matrixAccount');
      } else {
        await prefs.setString('matrixAccount', jsonEncode(account.toJson()));
      }
    });
  }

  /// Schrijf het Matrix-access-token versleuteld naar de keychain (gekeyd op de
  /// homeserver + user-id), of wis het bij een leeg token. Vangt keychain-fouten
  /// zelf af (en logt ze) zodat een niet-afgewachte aanroep — zoals vanuit de
  /// login-dialoog — nooit een onafgevangen async-exceptie oplevert.
  Future<bool> setMatrixToken(
    String homeserver,
    String userId,
    String token,
  ) async {
    try {
      if (token.isEmpty) {
        await _secrets.deleteMatrixToken(homeserver, userId);
      } else {
        await _secrets.writeMatrixToken(homeserver, userId, token);
      }
      return true;
    } catch (e) {
      logError('SettingsNotifier.setMatrixToken: keychain write failed', e);
      return false;
    }
  }

  /// Read the Matrix access token for [account] back from the keychain, or null.
  Future<String?> matrixToken(MatrixServer account) =>
      _secrets.readMatrixToken(account.homeserverUrl, account.userId);
}
