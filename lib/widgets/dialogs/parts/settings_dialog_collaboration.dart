// Part of the settings_dialog library — see ../settings_dialog.dart.
//
// Het tabblad Samenwerken: het app-globale Matrix-account voor realtime
// samenwerken (SELF_ENCRYPTED_RELAY.md §6, §8). Matrix is bewust géén
// opslagverbinding — een homeserver is een rendez-vous, geen deck-opslag — dus
// het hoort niet onder Opslag maar in een eigen tabblad. Het invulwerk zit in
// `settings/matrix_panel.dart`; hier staat alleen de inbedding in het venster en
// het inladen van het opgeslagen account.
part of '../settings_dialog.dart';

extension _SettingsCollaboration on _SettingsDialogState {
  Widget _collaborationTab() => MatrixPanel(form: _matrixForm);

  /// Vul het formulier met het opgeslagen account en haal het token asynchroon
  /// uit de sleutelhanger na — zodat de gebruiker ziet dát het er is en het niet
  /// opnieuw hoeft te plakken. Zelfde patroon als [_adoptConnectionForm].
  void _adoptMatrixForm(MatrixServer? account) {
    _matrixForm.adoptFrom(account);
    if (account == null || !account.isConfigured) return;
    ref.read(settingsProvider.notifier).matrixToken(account).then((token) {
      if (!mounted || token == null) return;
      _rebuild(() => _matrixForm.token.adopt(token));
    });
  }
}
