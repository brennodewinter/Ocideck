import 'dart:convert';
import 'dart:typed_data';

import '../../models/git_settings.dart';
import '../file_service.dart';
import 'git_forge.dart';
import 'git_transport.dart';

/// Een blob mag zo groot zijn als een pakket: assets zijn hier de grote
/// jongens, en de limiet verwijst naar de bron zodat de twee niet kunnen
/// divergeren.
const int kForgeMaxBlobBytes = FileService.maxPackageBytes;

/// Cap op een listing-respons, zodat een vijandige forge het geheugen niet kan
/// laten vollopen.
const int kForgeMaxListingBytes = 16 * 1024 * 1024;

/// Maximaal aantal entries dat we uit één listing accepteren.
const int kForgeMaxListingEntries = 5000;

/// De HTTP-plumbing die de drie forge-adapters delen.
///
/// Géén nieuwe laag: naar boven is en blijft [GitForge] het contract. Wat hier
/// staat is de herhaling eronder — dezelfde statusvertaling, dezelfde
/// JSON-decode, dezelfde refcontrole. Drie keer hetzelfde onderhouden betekent
/// dat een verscherping op één plek landt en op de andere twee vergeten wordt.
///
/// Wat écht per forge verschilt levert de adapter zelf aan: de URL-vorm
/// ([apiUri]), de auth-header ([headers]), de naam waaronder de forge in een
/// foutmelding aan de gebruiker verschijnt ([forgeName]), en of een 409 "de
/// repository is leeg" betekent ([treats409AsEmptyRepo]).
mixin ForgeHttp {
  /// De repo waar deze adapter aan vastzit; alleen [GitRepoConfig.slug] komt
  /// hier langs, in de aanmeldfout.
  GitRepoConfig get config;

  /// De testnaad: de adapters nemen hem in hun constructor aan, zodat een test
  /// er een neppe voor in de plaats kan zetten.
  GitTransport get transport;

  /// De headers voor elk verzoek, inclusief de auth-vorm van deze forge.
  Map<String, String> get headers;

  /// Zoals de forge in een foutmelding heet. Gitea/Forgejo blijft bewust "de
  /// forge": één adapter bedient twee producten, en een gebruiker die Forgejo
  /// draait moet niet lezen dat het aanmelden "bij Gitea" mislukte.
  String get forgeName;

  /// GitHub en Gitea melden een lege repository met een 409. GitLab gebruikt
  /// die status voor iets anders en zou daar dus onterecht "leeg" zeggen.
  bool get treats409AsEmptyRepo;

  /// De API-URL voor deze forge; de vormen lopen te ver uiteen om te delen.
  Uri apiUri(List<String> segments, {Map<String, String>? query});

  /// Eén GET die als JSON terugkomt.
  Future<Object?> getJson(
    List<String> segments, {
    Map<String, String>? query,
  }) async {
    final response = await transport.get(
      apiUri(segments, query: query),
      headers: headers,
      maxBytes: kForgeMaxListingBytes,
    );
    checkStatus(response.status);
    return decodeJson(response.bytes);
  }

  /// Eén schrijfverzoek met een JSON-body, ruw teruggegeven. Voor de gevallen
  /// waar de adapter zélf naar de status wil kijken vóór [checkStatus] — een
  /// 409 betekent bij een commit iets heel anders dan bij een leesactie.
  Future<GitResponse> sendJson(
    String method,
    List<String> segments,
    Map<String, Object?> body, {
    Map<String, String>? query,
  }) {
    return transport.send(
      method,
      apiUri(segments, query: query),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: utf8.encode(jsonEncode(body)),
      maxBytes: kForgeMaxListingBytes,
    );
  }

  /// Eén POST met een JSON-body die als JSON terugkomt.
  Future<Object?> post(
    List<String> segments,
    Map<String, Object?> body,
  ) async {
    final response = await sendJson('POST', segments, body);
    checkStatus(response.status);
    return decodeJson(response.bytes);
  }

  /// Vertaal een HTTP-status naar een [GitForgeException]. Alleen 2xx gaat door.
  void checkStatus(int status) {
    if (status >= 200 && status < 300) return;
    if (status == 401) {
      throw GitForgeException(
        GitForgeError.auth,
        'Aanmelden bij $forgeName mislukt ($status). Controleer je token en of '
        'het toegang heeft tot ${config.slug}.',
      );
    }
    if (status == 403) {
      throw const GitForgeException(
        GitForgeError.forbidden,
        'Token geldig, maar zonder rechten hiervoor (403).',
      );
    }
    if (status == 404) {
      // Een forge geeft ook 404 wanneer het token de repo niet mag zien: hij
      // verraadt liever niet dát hij bestaat. De melding mag dat niet als
      // zekerheid presenteren.
      throw const GitForgeException(
        GitForgeError.notFound,
        'Niet gevonden — of je token heeft er geen toegang toe.',
      );
    }
    if (status == 409 && treats409AsEmptyRepo) {
      throw const GitForgeException(
        GitForgeError.notFound,
        'Repository is leeg.',
      );
    }
    if (status >= 500) {
      throw GitForgeException(GitForgeError.server, 'Serverfout ($status)');
    }
    throw GitForgeException(GitForgeError.server, 'Onverwachte status $status');
  }

  Object? decodeJson(Uint8List bytes) {
    // Een lege body is geen kapotte JSON: een geslaagde merge of delete geeft
    // er een. De aanroeper ziet dan `null` en klaagt zelf over wat er ontbrak.
    if (bytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (e) {
      throw GitForgeException(
        GitForgeError.malformed,
        'Antwoord van $forgeName is geen geldige JSON',
      );
    }
  }

  void requireEntryCount(int count) {
    if (count > kForgeMaxListingEntries) {
      throw GitForgeException(
        GitForgeError.tooLarge,
        'Te veel bestanden in één listing ($count)',
      );
    }
  }

  /// Een ref komt soms uit door de gebruiker of de forge geleverde data. Hij
  /// belandt in een URL-pad, dus weigeren we alles wat daar een betekenis heeft
  /// of wat git zelf niet als refnaam accepteert.
  void requireRef(String ref) {
    final r = ref.trim();
    if (r.isEmpty ||
        r.length > 255 ||
        r.startsWith('-') ||
        r.contains('..') ||
        r.contains('?') ||
        r.contains('#') ||
        r.contains('&') ||
        r.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Ongeldige branch-, tag- of commitnaam',
      );
    }
  }
}
