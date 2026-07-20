import 'package:path/path.dart' as p;
import 'storage_origin.dart';

/// De ondersteunde forges. Volgorde = prioriteit uit het ontwerp: Forgejo/Gitea
/// eerst (zelfde REST-oppervlak), daarna GitHub en GitLab.
enum GitProvider {
  /// Forgejo én Gitea: één adapter, want Forgejo is een fork van Gitea en de
  /// REST-API's zijn op de punten die wij raken identiek.
  gitea,
  github,
  gitlab,
}

/// Configuratie van één git-repository als deck-bron. Bewust géén token: dat
/// staat in de keychain (zie `SecretStore.gitToken*`), gekeyd op
/// [baseUrl] + [owner]. Deze waarden mogen wél in het prefs-domein.
///
/// Spiegelt bewust `WebdavServer`: het git-backend ís de WebDAV-bron met
/// versiebeheer erbij, dus dezelfde vorm, dezelfde SSRF-opt-in, dezelfde
/// scheiding tussen configuratie en geheim.
class GitRepoConfig {
  /// Server-origin zonder pad, bv. `https://git.example.org`. Trailing slashes
  /// worden bij het bouwen van URL's genegeerd.
  final String baseUrl;

  /// Eigenaar: gebruiker, organisatie of (bij GitLab) groepspad.
  final String owner;

  /// Repository-naam.
  final String repo;

  /// De hoofdbranch waartegen releases mergen, meestal `main`.
  final String defaultBranch;

  final GitProvider provider;

  /// De gebruiker heeft expliciet bevestigd dat dit een vertrouwde interne
  /// server is; pas dán mag een privé/LAN-host de SSRF-blokkade passeren.
  final bool trustedInternal;

  /// SHA-256 van het certificaat dat de gebruiker uitdrukkelijk heeft
  /// vertrouwd, of leeg wanneer alleen de normale keten van erkende uitgevers
  /// telt. Zie [NetGuard.pinnedCertCheck].
  ///
  /// Bewust een vingerafdruk en geen vlag als "accepteer zelfondertekend": dat
  /// laatste zou élk certificaat toelaten, ook dat van een aanvaller.
  final String pinnedCertSha256;

  const GitRepoConfig({
    required this.baseUrl,
    required this.owner,
    required this.repo,
    this.provider = GitProvider.gitea,
    this.defaultBranch = 'main',
    this.trustedInternal = false,
    this.pinnedCertSha256 = '',
  });

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty &&
      owner.trim().isNotEmpty &&
      repo.trim().isNotEmpty;

  /// De host van [baseUrl], of leeg wanneer onparseerbaar.
  String get host => Uri.tryParse(baseUrl.trim())?.host ?? '';

  /// Origin (scheme + host + poort) van [baseUrl] zonder pad.
  Uri? get origin {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    );
  }

  /// Menselijke aanduiding `owner/repo`, voor UI en logregels.
  String get slug => '${owner.trim()}/${repo.trim()}';

  /// Een stabiele, veilige sleutel per repo: host + owner + repo, gestript tot
  /// tekens die overal mogen — in een mapnaam én in een prefs-sleutel.
  ///
  /// Dit is wat een repo van een andere onderscheidt in de opslag eromheen: de
  /// clone-map, de wachtrij met nog niet gepushte commits, en de werkkopie. Een
  /// repo is een vertrouwensgrens (§6), dus die drie mogen nooit gedeeld worden
  /// — twee repo's met een gelijknamig deck zouden elkaars werk overschrijven.
  ///
  /// Bevat per constructie geen `:`, waardoor een gescopede sleutel
  /// (`<prefix>::<storageSlug>::<deckDir>`) niet te verwarren is met een oude,
  /// ongescopede (`<prefix>::<deckDir>`) — deckmappen mogen ook geen `:`
  /// bevatten (zie [GitRepoLayout]).
  String get storageSlug {
    final raw = '${host}_${owner.trim()}_${repo.trim()}';
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
  }

  GitRepoConfig copyWith({
    String? baseUrl,
    String? owner,
    String? repo,
    GitProvider? provider,
    String? defaultBranch,
    bool? trustedInternal,
    String? pinnedCertSha256,
  }) {
    return GitRepoConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      owner: owner ?? this.owner,
      repo: repo ?? this.repo,
      provider: provider ?? this.provider,
      defaultBranch: defaultBranch ?? this.defaultBranch,
      trustedInternal: trustedInternal ?? this.trustedInternal,
      pinnedCertSha256: pinnedCertSha256 ?? this.pinnedCertSha256,
    );
  }

  Map<String, Object?> toJson() => {
    'baseUrl': baseUrl,
    'owner': owner,
    'repo': repo,
    'provider': provider.name,
    'defaultBranch': defaultBranch,
    'trustedInternal': trustedInternal,
    if (pinnedCertSha256.isNotEmpty) 'pinnedCertSha256': pinnedCertSha256,
  };

  factory GitRepoConfig.fromJson(Map<String, Object?> json) {
    final rawProvider = json['provider'] as String?;
    return GitRepoConfig(
      baseUrl: (json['baseUrl'] as String?) ?? '',
      owner: (json['owner'] as String?) ?? '',
      repo: (json['repo'] as String?) ?? '',
      provider: GitProvider.values.firstWhere(
        (p) => p.name == rawProvider,
        // Onbekende provider (nieuwer prefs-bestand, of gerommel): val terug op
        // gitea in plaats van te gooien — de config is niet vertrouwd genoeg om
        // een crash op te baseren, en gitea is de standaardkeuze.
        orElse: () => GitProvider.gitea,
      ),
      defaultBranch:
          (json['defaultBranch'] as String?)?.trim().isNotEmpty == true
          ? (json['defaultBranch'] as String).trim()
          : 'main',
      trustedInternal: (json['trustedInternal'] as bool?) ?? false,
      pinnedCertSha256: (json['pinnedCertSha256'] as String?) ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GitRepoConfig &&
      other.baseUrl.trim() == baseUrl.trim() &&
      other.owner.trim() == owner.trim() &&
      other.repo.trim() == repo.trim() &&
      other.provider == provider &&
      other.defaultBranch == defaultBranch &&
      other.trustedInternal == trustedInternal &&
      other.pinnedCertSha256 == pinnedCertSha256;

  @override
  int get hashCode => Object.hash(
    baseUrl.trim(),
    owner.trim(),
    repo.trim(),
    provider,
    defaultBranch,
    trustedInternal,
    pinnedCertSha256,
  );
}

/// Padregels van de repo-layout uit het ontwerp (§6). Eén repo draagt vele
/// decks onder `decks/<naam>/`, met een gedeelde asset-pool onder `assets/`.
///
/// Een repo waarvan de wortel zélf één deck is bestaat bewust niet: één layout,
/// geen detectie. De keerzijde daarvan is dat de repo de vertrouwensgrens ís —
/// forge-toegang is alles-of-niets, dus alle decks in één repo delen één
/// publiek. Dat is beleid dat de forge afdwingt, niet iets dat deze klasse kan
/// controleren.
class GitRepoLayout {
  GitRepoLayout._();

  /// Map met alle decks.
  static const String decksRoot = 'decks';

  /// Gedeelde, content-geadresseerde asset-pool.
  static const String assetsRoot = 'assets';

  /// Verwijzingsschema naar de pool, naast de bestaande `mem:` en `asset:`
  /// (§6.1). Vorm: `repo:assets/<sha256>.<ext>`.
  ///
  /// Het bestaat omdat het pad tegen de **repo-wortel** oplost, niet tegen de
  /// deckmap. Een relatieve `../../assets/…` zou door `resolveProjectRelative`
  /// geweigerd worden — en terecht, want die fail-closet op traversal. Een deck
  /// drie mappen diep moet tóch bij de gedeelde pool kunnen, dus krijgt de
  /// verwijzing een eigen schema in plaats van een uitzondering op de guard.
  static const String assetScheme = 'repo:';

  static bool isRepoAsset(String path) => path.startsWith(assetScheme);

  /// De verwijzing voor een blob met [sha256] en extensie [ext] (zonder punt).
  /// Null bij een sha of extensie die geen pad-segment mag worden.
  static String? assetRef(String sha256, String ext) {
    final h = sha256.trim().toLowerCase();
    final e = ext.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(h)) return null;
    if (!RegExp(r'^[a-z0-9]{1,10}$').hasMatch(e)) return null;
    return '$assetScheme$assetsRoot/$h.$e';
  }

  /// Het repo-pad achter een `repo:`-verwijzing, of null wanneer het er geen is
  /// of wanneer hij niet onder [assetsRoot] blijft.
  ///
  /// Dit is de eigen guard die §6.1 eist: een `repo:`-doel komt uit deck-inhoud
  /// die we niet vertrouwen, dus het moet normaliseren naar een pad ónder
  /// `assets/` en mag daar niet uit traverseren. `repo:assets/../decks/x` is
  /// geen asset.
  static String? assetPathOf(String reference) {
    if (!isRepoAsset(reference)) return null;
    final raw = reference.substring(assetScheme.length).trim();
    if (!isSafeRepoPath(raw)) return null;
    final normalized = p.posix.normalize(raw);
    if (!p.posix.isWithin(assetsRoot, normalized)) return null;
    return normalized;
  }

  /// Naamregels voor een deckmap. Bewust streng: de naam wordt een pad-segment
  /// én een deel van een git-refnaam (`decks/<naam>/v1.0`), dus alles wat in
  /// één van beide een bijzondere betekenis heeft, weigeren we hier al.
  ///
  /// Toegestaan: letters, cijfers, `-`, `_` en `.` — maar niet beginnend of
  /// eindigend op `.`, en geen `..` (padtraversal én een verboden reeks in een
  /// refnaam).
  static final RegExp _deckName = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9._-]*$');

  static bool isValidDeckName(String name) {
    final n = name.trim();
    if (n.isEmpty || n.length > 100) return false;
    if (n.endsWith('.') || n.endsWith('.lock')) return false;
    if (n.contains('..')) return false;
    return _deckName.hasMatch(n);
  }

  /// Pad van de deckmap, of null wanneer [name] geen geldige deknaam is.
  static String? deckDir(String name) =>
      isValidDeckName(name) ? '$decksRoot/${name.trim()}' : null;

  /// De deknaam uit een deckmap-pad, of null wanneer het pad niet de vorm
  /// `decks/<geldige naam>` heeft.
  static String? deckNameOf(String dir) {
    final normalized = p.posix.normalize(dir.trim());
    final parts = normalized.split('/');
    if (parts.length != 2 || parts[0] != decksRoot) return null;
    return isValidDeckName(parts[1]) ? parts[1] : null;
  }

  /// De deckmap uit een `decks/<naam>/deck.md`-pad, of null wanneer het pad geen
  /// `deck.md` in een geldige deckmap is (een asset, een genest of los bestand).
  /// Zo maken de zoekversnellers — `git grep` en de server-codezoekopdracht —
  /// van een gevonden bestandspad een deckmap die de zoeker kan openen.
  static String? deckDirOfDeckFile(String repoPath) {
    const file = '/deck.md';
    if (!repoPath.endsWith(file)) return null;
    final dir = repoPath.substring(0, repoPath.length - file.length);
    return deckNameOf(dir) == null ? null : dir;
  }

  /// Naam van een release-tag: `decks/<naam>/v1.0` (D9). De slash-vorm groepeert
  /// leesbaar in forge-UI's en maakt tag-protection (`decks/*/v*`) natuurlijk —
  /// wat telt, want een release-tag is gated (P8). Git's D/F-conflict bijt hier
  /// niet: `decks/<naam>` is zelf nooit een tag.
  static String? releaseTag(String deckName, String version) {
    final dir = deckDir(deckName);
    if (dir == null) return null;
    final v = version.trim();
    if (v.isEmpty || !RegExp(r'^v[0-9][A-Za-z0-9._-]*$').hasMatch(v)) {
      return null;
    }
    if (v.contains('..') || v.endsWith('.') || v.endsWith('.lock')) return null;
    return '$dir/$v';
  }

  /// De versie uit een release-tag `decks/<naam>/vX`, of null wanneer [tag] niet
  /// die vorm heeft of niet bij [deckName] hoort. Het omgekeerde van
  /// [releaseTag] — voor de versiekiezer die tags als `v1.0` toont.
  static String? versionOfTag(String tag, String deckName) {
    final dir = deckDir(deckName);
    if (dir == null) return null;
    final prefix = '$dir/';
    if (!tag.startsWith(prefix)) return null;
    final version = tag.substring(prefix.length);
    // Alleen als het door releaseTag heen zou komen (geen submap onder de deck).
    return releaseTag(deckName, version) == tag ? version : null;
  }

  /// Of [tag] een release-tag voor [deckName] is (`decks/<naam>/vX`).
  static bool isReleaseTagFor(String tag, String deckName) =>
      versionOfTag(tag, deckName) != null;

  /// Naam van een werkbranch voor één bewerkingsronde: `decks/<naam>/<datum>`
  /// (D3). De branch wordt gegenereerd, niet getypt — de auteur ziet "concept"
  /// en "uitgebrachte versie", nooit een branchnaam.
  static String? workBranch(String deckName, DateTime when) {
    final dir = deckDir(deckName);
    if (dir == null) return null;
    final y = when.year.toString().padLeft(4, '0');
    final m = when.month.toString().padLeft(2, '0');
    final d = when.day.toString().padLeft(2, '0');
    return '$dir/$y-$m-$d';
  }

  /// Weiger elk pad dat buiten de repo-wortel zou breken. Tree-entries komen van
  /// een server die we niet vertrouwen, dus dit is de zip-slip-equivalent voor
  /// een git-tree (§10.1).
  /// Let op wat hier bewust NIET wordt geweigerd: een spatie. `assets/my
  /// image.png` is een volstrekt geldig git-pad, en een spatie is geen
  /// traversal. Het subprocess krijgt paden als argv-element zonder shell
  /// (§10.2), dus er valt niets te injecteren. Deze functie bewaakt
  /// containment, niet onze eigen naamconventie — die zit in
  /// [isValidDeckName], waar hij thuishoort.
  static bool isSafeRepoPath(String path) {
    final raw = path.trim();
    if (raw.isEmpty) return false;
    if (raw.startsWith('/')) return false;
    if (raw.contains('\\')) return false; // Windows-scheiding hoort hier niet
    if (raw.codeUnits.any((c) => c < 0x20 || c == 0x7f)) return false;
    final normalized = p.posix.normalize(raw);
    if (normalized == '.' || normalized.startsWith('..')) return false;
    return !normalized.split('/').contains('..');
  }
}

/// Herkomst van een tab die uit een git-repo is geopend, zodat opslaan weet waar
/// terug te schrijven en tegen welke commit het werk is geschreven.
///
/// Spiegelt `WebdavOrigin`, met [baseSha] als toevoeging: dát is wat versiebeheer
/// erbij geeft. Een gequeuede commit draagt de sha waar hij tegenaan is
/// geschreven, zodat de forge een non-fast-forward kan weigeren in plaats van
/// stil werk te overschrijven.
class GitOrigin implements StorageOrigin {
  final GitRepoConfig config;

  /// De bestandsverbinding waar dit deck vandaan kwam. Hiermee gaat opslaan
  /// terug naar dezelfde opdrachtgever zonder opnieuw te vragen, en blijft dat
  /// kloppen als de gebruiker de verbinding hernoemt of een typefout in de URL
  /// herstelt — [config] verandert dan wél mee.
  ///
  /// Leeg voor herkomst uit een versie van vóór de verbindingenlijst; dan valt
  /// de app terug op het vergelijken van [config] (zie [matchesRepo]).
  @override
  final String connectionId;

  /// Branch waarop deze tab werkt.
  final String branch;

  /// Deckmap binnen de repo, bv. `decks/kwartaalcijfers`.
  final String deckDir;

  /// De laatste commit waarop deze tab is gebaseerd.
  final String baseSha;

  const GitOrigin({
    required this.config,
    required this.branch,
    required this.deckDir,
    required this.baseSha,
    this.connectionId = '',
  });

  /// De deknaam, of null wanneer [deckDir] niet de layout van §6 volgt.
  String? get deckName => GitRepoLayout.deckNameOf(deckDir);

  @override
  String get remoteLocation => deckDir;

  bool matchesRepo(GitRepoConfig other) => other == config;

  GitOrigin copyWith({
    GitRepoConfig? config,
    String? branch,
    String? deckDir,
    String? baseSha,
    String? connectionId,
  }) {
    return GitOrigin(
      config: config ?? this.config,
      branch: branch ?? this.branch,
      deckDir: deckDir ?? this.deckDir,
      baseSha: baseSha ?? this.baseSha,
      connectionId: connectionId ?? this.connectionId,
    );
  }
}
