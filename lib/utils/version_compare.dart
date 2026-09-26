/// Een geparste semantische versie (`X.Y.Z` met optionele pre-release), voor
/// de vergelijking tussen het draaiende nummer en wat de release-index van de
/// forge als nieuwste terugmeldt.
///
/// De volledige semver-regels zijn bewust niet geïmplementeerd — alleen wat
/// vergelijking nodig heeft: `+build`-metadata telt niet mee, een `v`-prefix
/// mag, en pre-release-identifiers ordenen zoals semver §11 voorschrijft
/// (numeriek < alfanumeriek, kortere lijst < langere lijst, en een release
/// staat bóven elke pre-release van hetzelfde nummer). Numerieke identifiers
/// met voorloopnullen worden als numeriek gelezen; onze eigen tags hebben die
/// niet.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion._(this._core, this._prerelease);

  final List<int> _core;
  final List<String> _prerelease;

  /// De `X.Y.Z`-kern als `X.Y.Z`-tekst, zonder `v`-prefix of pre-release.
  String get core => '${_core[0]}.${_core[1]}.${_core[2]}';

  /// Parseert [raw] (`v0.6.12`, `0.6.12-rc1`, `1.0.0+4`). Geeft `null` bij een
  /// kern die niet uit drie gehele getallen bestaat of bij lege
  /// pre-release-identifiers.
  static AppVersion? tryParse(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    s = s.split('+').first;
    final dash = s.indexOf('-');
    final coreText = dash < 0 ? s : s.substring(0, dash);
    final preText = dash < 0 ? '' : s.substring(dash + 1);
    final parts = coreText.split('.');
    if (parts.length != 3) return null;
    final core = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0) return null;
      core.add(n);
    }
    // Alleen splitten als er echt een streepje stond: `''.split('.')` geeft
    // `['']`, dus een los eind-streepje (`1.2.3-`) valt hier ook door de
    // lege-identifier-weigering.
    final pre = dash < 0 ? const <String>[] : preText.split('.');
    if (pre.any((id) => id.isEmpty)) return null;
    return AppVersion._(core, pre);
  }

  @override
  int compareTo(AppVersion other) {
    for (var i = 0; i < 3; i++) {
      final d = _core[i].compareTo(other._core[i]);
      if (d != 0) return d;
    }
    if (_prerelease.isEmpty != other._prerelease.isEmpty) {
      return _prerelease.isEmpty ? 1 : -1;
    }
    final shared = _prerelease.length < other._prerelease.length
        ? _prerelease.length
        : other._prerelease.length;
    for (var i = 0; i < shared; i++) {
      final d = _compareIdentifier(_prerelease[i], other._prerelease[i]);
      if (d != 0) return d;
    }
    return _prerelease.length.compareTo(other._prerelease.length);
  }

  /// Semver §11.4.4: numerieke identifiers vergelijken numeriek en staan
  /// altijd lager dan alfanumerieke.
  static int _compareIdentifier(String a, String b) {
    final an = int.tryParse(a);
    final bn = int.tryParse(b);
    if (an != null && bn != null) return an.compareTo(bn);
    if (an != null) return -1;
    if (bn != null) return 1;
    return a.compareTo(b);
  }

  /// Of [candidate] strikt nieuwer is dan [current]. Geeft `false` bij een
  /// onparseerbare kant — een raar release-label is geen reden om te melden.
  static bool isNewer(String candidate, String current) {
    final c = tryParse(candidate);
    final cur = tryParse(current);
    if (c == null || cur == null) return false;
    return c.compareTo(cur) > 0;
  }

  @override
  String toString() {
    final pre = _prerelease.isEmpty ? '' : '-${_prerelease.join('.')}';
    return '$core$pre';
  }
}
