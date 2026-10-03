// De redactiesleutel van een organisator (FORM_INTAKE.md §5.9): de age-identiteit die
// verzegelde inzendingen opent en het Ed25519-zaad dat bundels ondertekent, samen in de
// sleutelhanger van het besturingssysteem.
//
// Drie dingen maken deze sleutel anders dan een token dat je opnieuw kunt typen:
//
// * **Hij is onvervangbaar.** Een sleutel kwijt is elke nog niet binnengehaalde inzending
//   kwijt die er alleen voor verzegeld was (§5.9: de prijs van een server die niets leest).
//   Daarom wordt een sleutel **nooit overschreven**: een sleutelhanger die niet te lezen is,
//   is geen sleutelhanger die leeg is ([FormKeyUnreadable]), en een opgeslagen tekst die niet
//   te lezen is, is geen ruimte voor een nieuwe ([FormKeyDamaged]).
// * **Hij wordt zichtbaar aangemaakt**, niet stilletjes bij het eerste gebruik: er hoort een
//   herstelsleutel bij, en die moet iemand hebben opgeschreven.
// * **Publiceren wacht op een herstelweg** (§7.6): ten minste twee sleutels in het team, of een
//   herstelsleutel die is teruggetypt. Dat staat hier als één vraag ([FormKeyInfo.recoveryVerified])
//   die de rest van de app kan stellen.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../secret_store.dart';

/// De versie van de opgeslagen tekst.
const int kFormEditorialKeyVersion = 1;

/// De sleutel zoals de sleutelhanger hem bewaart. De geheimen zitten erin; dit object hoort
/// nergens te belanden behalve in [FormKeyService].
class FormEditorialKey {
  FormEditorialKey({
    required this.ageIdentity,
    required Uint8List signingSeed,
    required this.created,
    this.recoveryVerified = false,
  }) : signingSeed = Uint8List.fromList(signingSeed);

  /// `AGE-SECRET-KEY-1…`.
  final String ageIdentity;

  /// Het Ed25519-zaad, 32 bytes.
  final Uint8List signingSeed;

  /// De dag van aanmaken, `jjjj-mm-dd`.
  final String created;

  /// De herstelsleutel is teruggetypt en klopte.
  final bool recoveryVerified;

  FormEditorialKey withRecoveryVerified() => FormEditorialKey(
    ageIdentity: ageIdentity,
    signingSeed: signingSeed,
    created: created,
    recoveryVerified: true,
  );

  String toJsonText() => jsonEncode({
    'v': kFormEditorialKeyVersion,
    'identity': ageIdentity,
    'signing_seed': base32Encode(signingSeed),
    'created': created,
    'recovery_verified': recoveryVerified,
  });

  /// De sleutel uit [text], of `null` als het niet een sleutel van deze versie is: geen JSON,
  /// een andere versie, een identiteit die er geen is, een zaad dat geen 32 bytes is.
  static FormEditorialKey? fromJsonText(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (json is! Map || json['v'] != kFormEditorialKeyVersion) return null;
    final identity = json['identity'];
    final seedText = json['signing_seed'];
    final created = json['created'];
    final verified = json['recovery_verified'];
    final seed = seedText is String ? base32Decode(seedText) : null;
    if (identity is! String ||
        !isAgeIdentity(identity) ||
        seed == null ||
        seed.length != 32 ||
        created is! String ||
        !isValidCalendarDate(created) ||
        verified is! bool) {
      return null;
    }
    return FormEditorialKey(
      ageIdentity: identity,
      signingSeed: seed,
      created: created,
      recoveryVerified: verified,
    );
  }
}

/// Wat van de sleutel openbaar is: geen geheim, wel alles wat een bundel, een kaart of een
/// scherm nodig heeft.
class FormKeyInfo {
  const FormKeyInfo({
    required this.recipient,
    required this.signPublicKey,
    required this.fingerprint,
    required this.kid,
    required this.created,
    required this.recoveryVerified,
  });

  /// `age1…`: waaraan inzendingen worden verzegeld.
  final String recipient;

  /// De Ed25519-publieke sleutel, base32 (de `sign` van een bundel).
  final String signPublicKey;

  /// De vingerafdruk van de ondertekeningssleutel, 52 tekens (§6.4).
  final String fingerprint;

  /// De `kid` van deze organisator in een bundel.
  final String kid;

  final String created;
  final bool recoveryVerified;
}

/// De publieke kant van [key].
Future<FormKeyInfo> formKeyInfoOf(FormEditorialKey key) async {
  final signing = await formSigningKeyFromSeed(key.signingSeed);
  final recipient = (await ageRecipientOf(key.ageIdentity))!;
  return FormKeyInfo(
    recipient: recipient,
    signPublicKey: signing.publicKeyText,
    fingerprint: signing.fingerprint,
    kid: organiserKid(recipient),
    created: key.created,
    recoveryVerified: key.recoveryVerified,
  );
}

/// Waarom er geen bruikbare redactiesleutel is: wat een aanroeper die de sleutel nodig heeft aan
/// de gebruiker moet kunnen zeggen.
enum FormKeyProblem {
  /// Dit platform heeft geen sleutelhanger.
  unavailable,

  /// Er is nog geen redactiesleutel aangemaakt of hersteld.
  absent,

  /// De sleutelhanger gaf geen antwoord: wat erin staat is onbekend.
  unreadable,

  /// Er staat iets, maar het is geen redactiesleutel van deze versie.
  damaged,
}

/// Waarom [state] geen sleutel geeft, of `null` als er een is.
FormKeyProblem? keyProblemOf(FormKeyState state) => switch (state) {
  FormKeyPresent() => null,
  FormKeyUnavailable() => FormKeyProblem.unavailable,
  FormKeyAbsent() => FormKeyProblem.absent,
  FormKeyUnreadable() => FormKeyProblem.unreadable,
  FormKeyDamaged() => FormKeyProblem.damaged,
};

/// De redacteurskaart van [info] onder [name] (§5.1, §7.6): wat de eigenaar van een formulier nodig
/// heeft om deze sleutel in een bundel op te nemen. Werpt een [ArgumentError] voor een naam die niet
/// op een kaart kan; de aanroeper controleert hem met [isValidEditorName] en zegt het de gebruiker.
FormEditorCard editorCardOf(FormKeyInfo info, String name) =>
    createFormEditorCard(
      name: name,
      age: info.recipient,
      signPublicKey: base32Decode(info.signPublicKey)!,
    );

/// Wat de sleutelhanger over de redactiesleutel zegt.
sealed class FormKeyState {
  const FormKeyState();
}

/// Dit platform heeft geen sleutelhanger; er kan hier geen sleutel zijn of komen.
class FormKeyUnavailable extends FormKeyState {
  const FormKeyUnavailable();
}

/// Er is geen sleutel, en de sleutelhanger gaf dat zonder fout te kennen.
class FormKeyAbsent extends FormKeyState {
  const FormKeyAbsent();
}

/// De sleutelhanger kon niet worden gelezen (vergrendeld, toegang geweigerd). Er is niets
/// aangenomen: ook "er is geen sleutel" niet.
class FormKeyUnreadable extends FormKeyState {
  const FormKeyUnreadable();
}

/// Er staat iets in de sleutelhanger onder de naam van de sleutel dat geen sleutel is. Het is
/// niet overschreven.
class FormKeyDamaged extends FormKeyState {
  const FormKeyDamaged();
}

/// Een sleutel.
class FormKeyPresent extends FormKeyState {
  const FormKeyPresent(this.key, this.info);

  final FormEditorialKey key;
  final FormKeyInfo info;
}

/// De uitkomst van [FormKeyService.create] en [FormKeyService.restore].
sealed class FormKeyWrite {
  const FormKeyWrite();
}

/// De sleutel is aangemaakt of hersteld, bewaard en teruggelezen.
class FormKeyWritten extends FormKeyWrite {
  const FormKeyWritten(this.key, this.info);

  final FormEditorialKey key;
  final FormKeyInfo info;
}

/// Er is al een sleutel, of iets wat er een zou kunnen zijn: niets is geschreven.
class FormKeyNotWritten extends FormKeyWrite {
  const FormKeyNotWritten(this.state);

  /// Waarom: [FormKeyUnavailable], [FormKeyUnreadable], [FormKeyDamaged] of [FormKeyPresent].
  final FormKeyState state;
}

/// De sleutelhanger nam het niet aan, of gaf niet terug wat erin ging.
class FormKeyWriteFailed extends FormKeyWrite {
  const FormKeyWriteFailed();
}

/// Een herstelsleutel die is ingevoerd om te herstellen.
class FormKeyRestoreRefused extends FormKeyWrite {
  const FormKeyRestoreRefused(this.issue);

  final FormRecoveryIssue issue;
}

/// De uitkomst van [FormKeyService.verifyRecovery].
sealed class FormKeyVerify {
  const FormKeyVerify();
}

/// De herstelsleutel klopt; de sleutel is als gecontroleerd opgeslagen.
class FormKeyVerified extends FormKeyVerify {
  const FormKeyVerified();
}

/// Het is een herstelsleutel, maar niet die van deze sleutel.
class FormKeyDifferent extends FormKeyVerify {
  const FormKeyDifferent();
}

/// Het is geen herstelsleutel die te lezen is.
class FormKeyUnreadableRecovery extends FormKeyVerify {
  const FormKeyUnreadableRecovery(this.issue);

  final FormRecoveryIssue issue;
}

/// Er is geen sleutel om tegen te controleren, of hij is niet te lezen.
class FormKeyNothingToCheck extends FormKeyVerify {
  const FormKeyNothingToCheck();
}

/// De opgeslagen sleutel is gecontroleerd maar kon niet worden bijgewerkt.
class FormKeyVerifyNotSaved extends FormKeyVerify {
  const FormKeyVerifyNotSaved();
}

/// Aanmaken, lezen, controleren, herstellen en wissen van de redactiesleutel.
class FormKeyService {
  FormKeyService(this._store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SecretStore _store;
  final DateTime Function() _now;

  /// Wat er nu is. Leest de sleutelhanger; verandert niets.
  Future<FormKeyState> read() async {
    if (!_store.canStore) return const FormKeyUnavailable();
    final String? text;
    try {
      text = await _store.readFormEditorialKey();
    } on Exception {
      return const FormKeyUnreadable();
    }
    if (text == null) return const FormKeyAbsent();
    final key = FormEditorialKey.fromJsonText(text);
    if (key == null) return const FormKeyDamaged();
    return FormKeyPresent(key, await formKeyInfoOf(key));
  }

  /// Maakt de sleutel aan, **alleen als er geen is** en de sleutelhanger kon worden gelezen.
  /// Het resultaat is teruggelezen uit de sleutelhanger: een opslag die stil niets bewaart
  /// zou anders een herstelsleutel laten opschrijven bij een sleutel die er niet is.
  Future<FormKeyWrite> create() async {
    final state = await read();
    if (state is! FormKeyAbsent) return FormKeyNotWritten(state);
    final signing = await generateFormSigningKey();
    final key = FormEditorialKey(
      ageIdentity: generateAgeIdentity(),
      signingSeed: signing.seed,
      created: formDay(_now()),
    );
    return _install(key);
  }

  /// Herstelt de sleutel uit [recoveryKey], **alleen als er geen is**. Een herstelde sleutel
  /// geldt als gecontroleerd: wie hem intikt, heeft hem.
  Future<FormKeyWrite> restore(String recoveryKey) async {
    final state = await read();
    if (state is! FormKeyAbsent) return FormKeyNotWritten(state);
    final decoded = decodeFormRecoveryKey(recoveryKey);
    if (decoded is FormRecoveryRefused) {
      return FormKeyRestoreRefused(decoded.issue);
    }
    final recovered = decoded as FormRecoveredKey;
    return _install(
      FormEditorialKey(
        ageIdentity: recovered.ageIdentity,
        signingSeed: recovered.signingSeed,
        created: formDay(_now()),
        recoveryVerified: true,
      ),
    );
  }

  Future<FormKeyWrite> _install(FormEditorialKey key) async {
    try {
      await _store.writeFormEditorialKey(key.toJsonText());
    } on Exception {
      return const FormKeyWriteFailed();
    }
    final back = await read();
    if (back is! FormKeyPresent ||
        back.key.ageIdentity != key.ageIdentity ||
        !_same(back.key.signingSeed, key.signingSeed)) {
      return const FormKeyWriteFailed();
    }
    return FormKeyWritten(back.key, back.info);
  }

  /// De herstelsleutel van de bewaarde sleutel, of `null` als er geen is.
  Future<String?> recoveryKey() async {
    final state = await read();
    if (state is! FormKeyPresent) return null;
    return encodeFormRecoveryKey(
      signingSeed: state.key.signingSeed,
      ageIdentity: state.key.ageIdentity,
    );
  }

  /// Vergelijkt de teruggetypte [typed] met de bewaarde sleutel; klopt hij, dan wordt de
  /// sleutel als gecontroleerd bewaard.
  Future<FormKeyVerify> verifyRecovery(String typed) async {
    final state = await read();
    if (state is! FormKeyPresent) return const FormKeyNothingToCheck();
    final decoded = decodeFormRecoveryKey(typed);
    if (decoded is FormRecoveryRefused) {
      return FormKeyUnreadableRecovery(decoded.issue);
    }
    final recovered = decoded as FormRecoveredKey;
    if (recovered.ageIdentity != state.key.ageIdentity ||
        !_same(recovered.signingSeed, state.key.signingSeed)) {
      return const FormKeyDifferent();
    }
    if (state.key.recoveryVerified) return const FormKeyVerified();
    try {
      await _store.writeFormEditorialKey(
        state.key.withRecoveryVerified().toJsonText(),
      );
    } on Exception {
      return const FormKeyVerifyNotSaved();
    }
    return const FormKeyVerified();
  }

  /// Wist de sleutel — ook een die niet te lezen is. Onomkeerbaar; de aanroeper vraagt eerst.
  Future<void> delete() => _store.deleteFormEditorialKey();

  /// De tekst van een age-sleutelbestand, zoals `age-keygen` hem schrijft: de identiteit is
  /// de enige regel die telt, de commentaarregels zeggen wat hij is. Met dit bestand opent
  /// het programma `age` een verzegeld pakket zonder OciDeck (§5.9).
  String identityFileText(FormEditorialKey key, FormKeyInfo info) =>
      '# created: ${key.created}\n'
      '# public key: ${info.recipient}\n'
      '${key.ageIdentity}\n';
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}
