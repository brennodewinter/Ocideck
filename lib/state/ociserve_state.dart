part of 'ociserve_provider.dart';

const _uuid = Uuid();

typedef OciServeGatewayFactory =
    OciServeApi Function(OciServeSettings settings);
typedef OciServeAuthenticatorFactory =
    OciServeAuthenticator Function(OciServeSettings settings);

final ociServeGatewayFactoryProvider = Provider<OciServeGatewayFactory>(
  (ref) =>
      (settings) => OciServeGateway(settings: settings),
);

final ociServeAuthenticatorFactoryProvider =
    Provider<OciServeAuthenticatorFactory>(
      (ref) =>
          (settings) => OciServePkceAuthenticator(settings: settings),
    );

final ociServeProvider = NotifierProvider<OciServeNotifier, OciServeState>(
  OciServeNotifier.new,
);

final ociServeEnabledProvider = Provider<bool>(
  (ref) =>
      ref.watch(ociServeProvider.select((state) => state.settings.enabled)),
);

/// De eLearning-koppeling is op elk platform zichtbaar. Op web legt de kaart
/// uit waarom aanmelden zonder veilige sleutelbos niet beschikbaar is.
final ociServeAvailableProvider = Provider<bool>((ref) => true);

/// True only after a restored or fresh token has successfully called `/me`.
final ociServeAuthenticatedProvider = Provider<bool>(
  (ref) => ref.watch(ociServeProvider.select((state) => state.authenticated)),
);

enum OciServeStatus { loading, signedOut, authenticating, authenticated }

String _restoreErrorCode(String errorCode) => switch (errorCode) {
  'identity_provider_confirmation_required' => errorCode,
  'connection_failed' || 'network' || 'timeout' => errorCode,
  _ => 'restore_failed',
};

class OciServeState {
  const OciServeState({
    this.settings = const OciServeSettings(),
    this.status = OciServeStatus.loading,
    this.account,
    this.errorCode,
    this.warningCode,
    this.identityProviderHost,
    this.pendingReports = 0,
  });

  final OciServeSettings settings;
  final OciServeStatus status;
  final OciServeAccount? account;
  final String? errorCode;
  final String? warningCode;
  final String? identityProviderHost;
  final int pendingReports;

  bool get authenticated =>
      settings.enabled &&
      status == OciServeStatus.authenticated &&
      account != null;

  /// De server was bij de laatste expliciete verbindingspoging niet bereikbaar.
  /// Andere aanmeldfouten krijgen geen netwerklabel: een geweigerd account is
  /// iets anders dan een ontbrekende verbinding en vraagt een andere oplossing.
  bool get serverUnavailable =>
      const {'connection_failed', 'network', 'timeout'}.contains(errorCode);

  bool get loading => status == OciServeStatus.loading;
  bool get authenticating => status == OciServeStatus.authenticating;
  List<OciServeMembership> get memberships =>
      account?.activeMemberships ?? const [];
  String? get error => errorCode;
  int get pendingSync => pendingReports;

  OciServeState copyWith({
    OciServeSettings? settings,
    OciServeStatus? status,
    OciServeAccount? account,
    bool clearAccount = false,
    String? errorCode,
    bool clearError = false,
    String? warningCode,
    bool clearWarning = false,
    String? identityProviderHost,
    bool clearIdentityProviderHost = false,
    int? pendingReports,
  }) => OciServeState(
    settings: settings ?? this.settings,
    status: status ?? this.status,
    account: clearAccount ? null : account ?? this.account,
    errorCode: clearError ? null : errorCode ?? this.errorCode,
    warningCode: clearWarning ? null : warningCode ?? this.warningCode,
    identityProviderHost: clearIdentityProviderHost
        ? null
        : identityProviderHost ?? this.identityProviderHost,
    pendingReports: pendingReports ?? this.pendingReports,
  );
}
