import 'ociserve_http.dart';

/// De server weigerde een verzoek omdat de aanmelding niet sterk of recent
/// genoeg is voor het beleid van de organisatie (RFC 9470,
/// `insufficient_user_authentication`). De uitdaging noemt wat een nieuwe
/// aanmelding moet bevatten.
///
/// Dit is geen "uitgelogd": het token is geldig, het beleid vraagt méér. Een
/// gewone vernieuwing van het token verandert daar niets aan, want de
/// `auth_time` en de `acr` van de oorspronkelijke aanmelding blijven gelden.
class OciServeStepUpRequired extends OciServeException {
  const OciServeStepUpRequired({
    this.acrValues = const [],
    this.maxAge,
    super.problem,
  }) : super('step_up_required', statusCode: 401);

  /// De gevraagde `acr`-waarden in voorkeursvolgorde; leeg als het beleid geen
  /// ACR eist (een AMR-eis kan RFC 9470 niet uitdrukken).
  final List<String> acrValues;

  /// De hoogst toegestane leeftijd van de laatste actieve aanmelding.
  final Duration? maxAge;
}

/// Voert de stap-omhoog-aanmelding uit en geeft het verse toegangstoken terug,
/// of gooit als dat niet lukt of niet mag. Het verzoek wordt daarna één keer
/// met dat token herhaald.
typedef OciServeStepUpHandler =
    Future<String> Function(OciServeStepUpRequired need);

/// Een gateway die een uitdaging zelf kan afhandelen zodra hem een handler is
/// meegegeven. Zonder handler gooit hij [OciServeStepUpRequired] naar de
/// aanroeper.
abstract interface class OciServeStepUpAware {
  set stepUpHandler(OciServeStepUpHandler? handler);
}

const _maxChallengeLength = 2048;
const _maxAcrValues = 8;
const _maxAcrLength = 256;
const _maxAgeSeconds = 366 * 24 * 3600;

final _bearerScheme = RegExp(r'^Bearer(\s|$)', caseSensitive: false);
final _authParam = RegExp(
  r'([A-Za-z0-9_-]+)\s*=\s*(?:"((?:[^"\\]|\\.)*)"|([^\s,"]+))',
);
final _quotedPair = RegExp(r'\\(.)');
final _whitespace = RegExp(r'\s+');

/// Dezelfde tekens als de server voor een `acr` toestaat: afdrukbaar ASCII
/// zonder spatie, dubbele aanhalingsteken en backslash.
final _acrToken = RegExp(r'^[\x21\x23-\x5B\x5D-\x7E]+$');

/// Leest de uitdaging uit de antwoordheaders, of geeft null als dit geen
/// uitdaging om een sterkere aanmelding is. De waarden worden begrensd en
/// gecontroleerd: ze komen van de server en worden straks in een
/// autorisatieverzoek bij de identiteitsprovider gezet.
OciServeStepUpRequired? parseOciServeStepUpChallenge(
  Map<String, String> headers, {
  OciServeProblem? problem,
}) {
  String? raw;
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == 'www-authenticate') raw = entry.value;
  }
  raw = raw?.trim();
  if (raw == null ||
      raw.isEmpty ||
      raw.length > _maxChallengeLength ||
      !_bearerScheme.hasMatch(raw)) {
    return null;
  }
  final params = <String, String>{};
  for (final match in _authParam.allMatches(raw)) {
    final quoted = match.group(2);
    params.putIfAbsent(
      match.group(1)!.toLowerCase(),
      () => quoted == null
          ? match.group(3)!
          : quoted.replaceAllMapped(_quotedPair, (m) => m.group(1)!),
    );
  }
  if (params['error'] != 'insufficient_user_authentication') return null;

  final acr = (params['acr_values'] ?? '')
      .split(_whitespace)
      .where(
        (value) =>
            value.isNotEmpty &&
            value.length <= _maxAcrLength &&
            _acrToken.hasMatch(value),
      )
      .take(_maxAcrValues)
      .toList(growable: false);
  final seconds = int.tryParse(params['max_age'] ?? '');
  return OciServeStepUpRequired(
    acrValues: acr,
    maxAge: seconds != null && seconds >= 0 && seconds <= _maxAgeSeconds
        ? Duration(seconds: seconds)
        : null,
    problem: problem,
  );
}
