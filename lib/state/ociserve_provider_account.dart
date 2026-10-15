part of 'ociserve_provider.dart';

/// Accountmutaties en auditregistraties van de cursist (issue #2428):
/// aanmelding en geopende lessen als gebeurtenis naar de server, en de eigen
/// profielfoto vervangen of verwijderen.
mixin _OciServeAccountMethods on OciServeNotifierBase {
  /// Eén auditpunt per interactieve PKCE-aanmelding. Refresh en herstelde
  /// sessies komen hier nooit langs — die melden zich niet opnieuw aan.
  /// De registratie is bijzaak: hij mag de aanmelding niet vertragen en een
  /// mislukte call is een gelogde aantekening, geen fout voor de gebruiker.
  @override
  Future<void> _auditOciDeckLogin(
    OciServeApi gateway,
    String accessToken,
  ) async {
    try {
      await _nonInteractive(
        () => gateway.reportOciDeckLogin(
          accessToken: accessToken,
          idempotencyKey: _uuid.v4(),
        ),
      );
    } catch (error, stack) {
      logError('OciServe: aanmelding registreren', error.runtimeType, stack);
    }
  }

  /// Het les-openen is het auditpunt dat "de cursist is begonnen" betekent —
  /// hij loopt pas ná de integriteitscontrole én een geslaagde open. Komt de
  /// call er niet door, dan wacht hij in dezelfde versleutelde wachtrij als
  /// de voortgangsrapporten en gaat hij mee met de eerstvolgende flush; hij
  /// blokkeert het afspelen nooit.
  @override
  Future<void> _auditLessonOpened({
    required String organizationId,
    required OciServeFeedItem lesson,
    required String accessToken,
  }) async {
    if (!state.authenticated) return;
    // Eén sleutel voor de eerste call én de herhaling. Een nieuwe sleutel
    // zou dezelfde opening een tweede keer laten tellen.
    final idempotencyKey = _uuid.v4();
    try {
      await _nonInteractive(
        () => _gatewayFactory(state.settings).markLessonOpened(
          accessToken: accessToken,
          organizationId: organizationId,
          versionId: lesson.versionId,
          lessonId: lesson.lessonId,
          idempotencyKey: idempotencyKey,
        ),
      );
    } on OciServeException catch (error, stack) {
      logError('OciServe: geopende les registreren', error.runtimeType, stack);
      // Een 4xx is een afwijzing, geen transportstoring. Die mag de
      // wachtrij niet blijven vergiftigen.
      if (state.authenticated && _lessonOpenShouldQueue(error)) {
        await _enqueueLessonOpened(organizationId, lesson, idempotencyKey);
      }
    }
  }

  bool _lessonOpenShouldQueue(OciServeException error) {
    final status = error.statusCode;
    if (status != null) return status >= 500;
    return error.code == 'network' || error.code == 'timeout';
  }

  Future<void> _enqueueLessonOpened(
    String organizationId,
    OciServeFeedItem lesson,
    String idempotencyKey,
  ) async {
    try {
      await _enqueueRaw({
        'kind': 'lesson_opened_v1',
        'account_id': state.account?.id ?? '',
        'organization_id': organizationId,
        'version_id': lesson.versionId,
        'lesson_id': lesson.lessonId,
        // De sleutel reist mee in de wachtrij: een herzending van dezelfde
        // gebeurtenis draagt dezelfde sleutel en kan dus nooit dubbel tellen.
        'key': idempotencyKey,
      });
    } catch (error, stack) {
      logError(
        'OciServe: geopende les in wachtrij zetten',
        error.runtimeType,
        stack,
      );
    }
  }

  /// Vervangt de eigen profielfoto door [bytes] (PNG, JPEG of WebP) en
  /// ververst daarna het account in state zodat elke avatar in beeld de
  /// nieuwe hash toont.
  Future<void> replaceAccountAvatar(Uint8List bytes, String contentType) async {
    final access = await _accessToken();
    final gateway = _gatewayFactory(state.settings);
    await _nonInteractive(
      () => gateway.replaceAccountAvatar(
        accessToken: access,
        bytes: bytes,
        contentType: contentType,
      ),
    );
    state = state.copyWith(
      account: await _nonInteractive(() => gateway.me(access)),
    );
  }

  /// Verwijdert de eigen profielfoto en ververst het account.
  Future<void> removeAccountAvatar() async {
    final access = await _accessToken();
    final gateway = _gatewayFactory(state.settings);
    await _nonInteractive(
      () => gateway.removeAccountAvatar(accessToken: access),
    );
    state = state.copyWith(
      account: await _nonInteractive(() => gateway.me(access)),
    );
  }
}
