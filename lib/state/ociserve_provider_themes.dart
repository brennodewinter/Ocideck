part of 'ociserve_provider.dart';

/// Het organisatie-themaregister (#2429). Dunne doorgeeflaag: delen is altijd
/// een bewuste handeling in de stijl-instellingen — de provider koppelt nooit
/// zelf iets terug naar de server.
mixin _OciServeThemeMethods on OciServeNotifierBase {
  /// Alle profielen van de organisatie, over de pagina's heen, begrensd.
  Future<List<OciServeTheme>> organizationThemes(String organizationId) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    final gateway = _gatewayFactory(state.settings);
    final themes = <OciServeTheme>[];
    String? cursor;
    // Pathologisch veel thema's mag de dialoog niet eindeloos laten laden.
    for (var page = 0; page < 5; page++) {
      final result = await gateway.themes(
        accessToken: access,
        organizationId: organizationId,
        cursor: cursor,
      );
      themes.addAll(result.themes);
      cursor = result.nextCursor;
      if (cursor == null) break;
    }
    return List.unmodifiable(themes);
  }

  /// Eén profiel met zijn ETag (voor een latere If-Match-bijwerking).
  Future<({OciServeTheme theme, String? etag})> organizationTheme({
    required String organizationId,
    required String themeId,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(state.settings).theme(
      accessToken: access,
      organizationId: organizationId,
      themeId: themeId,
    );
  }

  /// Deelt een stijlprofiel onder [name]. 409 = naam bestaat al — de UI
  /// beslist dan of het een bijwerking van dat server-thema wordt.
  Future<OciServeTheme> shareTheme({
    required String organizationId,
    required String name,
    required Map<String, Object?> definition,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(state.settings).createTheme(
      accessToken: access,
      organizationId: organizationId,
      name: name,
      definition: definition,
      idempotencyKey: _uuid.v4(),
    );
  }

  /// Werkt een server-thema bij met `If-Match`; `*` is de bewuste
  /// overschrijf-keuze van de gebruiker na een 409.
  Future<({OciServeTheme theme, String? etag})> updateOrganizationTheme({
    required String organizationId,
    required String themeId,
    required String name,
    required Map<String, Object?> definition,
    required String ifMatch,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(state.settings).updateTheme(
      accessToken: access,
      organizationId: organizationId,
      themeId: themeId,
      name: name,
      definition: definition,
      ifMatch: ifMatch,
    );
  }

  /// Verwijdert een server-thema; 409 = ingebouwd of in gebruik — de UI
  /// legt dat uit in plaats van te falen.
  Future<void> deleteOrganizationTheme({
    required String organizationId,
    required String themeId,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    await _gatewayFactory(state.settings).deleteTheme(
      accessToken: access,
      organizationId: organizationId,
      themeId: themeId,
    );
  }
}
