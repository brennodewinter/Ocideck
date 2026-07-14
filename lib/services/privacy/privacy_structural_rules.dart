// Structurele lekken: de verstopplekken in markdown.
//
// Dit is de familie die generieke PII-scanners missen, omdat ze naar de *inhoud*
// van een slide kijken en niet naar wat er omheen zit. Een gebruikerspad in een
// stacktrace, een token in een URL, een deellink die iedereen toegang geeft — dat
// zijn geen persoonsgegevens in de tekst, maar ze lekken er wel.
//
// De grap is dat deze regels bijna allemaal een heel scherp formaat hebben. Een
// `?X-Amz-Signature=` staat niet per ongeluk in een zin. Dat maakt de familie
// goedkoop én precies — mits je de generieke gevallen eruit filtert, want
// `/home/runner/` in een CI-log verraadt niemand.

import '../../models/privacy_finding.dart';

/// Eén structurele regel.
class StructuralRule {
  final String id;
  final RegExp pattern;
  final PrivacyConfidence confidence;

  /// Extra controle bovenop de regex.
  final bool Function(RegExpMatch match)? validate;

  const StructuralRule(
    this.id,
    this.pattern, {
    this.confidence = PrivacyConfidence.certain,
    this.validate,
  });
}

/// Accountnamen die niemand aanwijzen.
///
/// Zonder deze lijst gaat elke CI-log en elk Docker-voorbeeld af: `/home/runner`,
/// `/Users/admin`, `C:\Users\Public`. Een pad verraadt pas iets als er een naam in
/// staat, en `runner` is geen naam.
const Set<String> genericAccountNames = {
  'user',
  'users',
  'admin',
  'administrator',
  'root',
  'runner',
  'ubuntu',
  'debian',
  'jenkins',
  'build',
  'ci',
  'docker',
  'guest',
  'public',
  'default',
  'shared',
  'test',
  'demo',
  'me',
  'home',
  'app',
  'node',
  'vagrant',
  'ec2-user',
  'localadmin',
};

/// Querysleutels waarvan de waarde een geheim is.
const Set<String> secretQueryKeys = {
  'token',
  'access_token',
  'id_token',
  'refresh_token',
  'api_key',
  'apikey',
  'key',
  'secret',
  'client_secret',
  'sig',
  'signature',
  'auth',
  'password',
  'x-amz-signature',
  'x-amz-credential',
  'sas',
  'se',
};

/// Querysleutels waarvan de waarde een persoonsgegeven is.
const Set<String> personalQueryKeys = {
  'email',
  'e-mail',
  'mail',
  'user',
  'username',
  'phone',
  'tel',
  'bsn',
  'ssn',
  'name',
  'naam',
};

/// Is dit accountnaam-deel van een pad een echte naam?
bool _isPersonalAccountName(RegExpMatch match) {
  final name = match.group(1)?.toLowerCase();
  if (name == null || name.isEmpty) return false;
  if (genericAccountNames.contains(name)) return false;
  // Een naam van één of twee tekens zegt niets. `/Users/x/` is geen lek.
  if (name.length < 3) return false;
  return true;
}

bool _isSecretQuery(RegExpMatch match) =>
    secretQueryKeys.contains(match.group(1)?.toLowerCase());

bool _isPersonalQuery(RegExpMatch match) =>
    personalQueryKeys.contains(match.group(1)?.toLowerCase());

final List<StructuralRule> structuralRules = [
  // Een gebruikerspad verraadt gewoon een naam. Het staat in stacktraces, in
  // screenshots van een terminal, en — het vaakst — in het pad van een
  // ingesloten afbeelding.
  StructuralRule(
    'struct.user_path',
    RegExp(
      r'(?:/Users/|/home/|[A-Za-z]:\\Users\\)([A-Za-z0-9._\-]+)',
      caseSensitive: false,
    ),
    validate: _isPersonalAccountName,
  ),

  // Een token in een URL-query. Wie de link heeft, heeft de toegang — en een
  // presigned S3-link of een Azure SAS-token staat zó in een slide geplakt.
  StructuralRule(
    'struct.url_token',
    RegExp(r'[?&]([A-Za-z0-9_\-]+)=([^\s&"\x27<>)]{8,})'),
    validate: _isSecretQuery,
  ),

  // Een persoonsgegeven in een URL-query. Onderdeel van de tracking-realiteit:
  // `?email=jan@…` in een unsubscribe-link.
  StructuralRule(
    'struct.url_pii',
    RegExp(r'[?&]([A-Za-z0-9_\-]+)=([^\s&"\x27<>)]{3,})'),
    validate: _isPersonalQuery,
  ),

  // Deellinks met een ingebakken toegangstoken: SharePoint, OneDrive, Drive,
  // Dropbox, WeTransfer. Wie de link heeft, heeft het bestand.
  StructuralRule(
    'struct.share_link',
    RegExp(
      r'https?://[^\s]*(?:'
      r'sharepoint\.com/[^\s]*(?::[bwtfop]:/|guestaccess)'
      r'|1drv\.ms/'
      r'|drive\.google\.com/(?:file/d/|open\?id=)'
      r'|docs\.google\.com/[a-z]+/d/'
      r'|dropbox\.com/s(?:cl)?/'
      r'|wetransfer\.com/downloads/'
      r')[^\s]*',
      caseSensitive: false,
    ),
    confidence: PrivacyConfidence.likely,
  ),

  // Een `mailto:` is een e-mailadres, ook als het in een link verstopt zit.
  StructuralRule(
    'struct.mailto',
    RegExp(r'mailto:([A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,})'),
  ),
];

/// Een ingesloten afbeelding als data-URI.
///
/// Hier kunnen we niet in kijken — dit is een blob base64 die net zo goed een
/// screenshot van een CRM-scherm vol namen kan zijn. Dat is geen bevinding maar
/// een **eerlijke mededeling**: dit stuk deck is voor ons onzichtbaar.
///
/// Bewust alleen informatief. Een data-URI is doodnormaal en er alarm op slaan zou
/// de controle ongeloofwaardig maken; er níéts over zeggen zou de gebruiker in de
/// waan laten dat we alles hebben gezien.
final RegExp dataUriPattern = RegExp(
  r'data:image/[a-z+]+;base64,[A-Za-z0-9+/=]{40,}',
);
