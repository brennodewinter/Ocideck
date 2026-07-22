import 'dart:convert';

import '../models/document_signature.dart';
import '../models/seal_record.dart';
import '../utils/log.dart';
import 'sidecar_format.dart';

/// De zegel- en handtekeningsidecar naast een `.md` (`<naam>.seal.json`).
///
/// **Waarom ernaast en niet erin.** Tot 0.1.0 stonden het zegelblok
/// (`ocideck_finalized`, `ocideck_seal_*`) en het handtekeningblok
/// (`ocideck_sig_*`) in de front matter van de `.md`. Twee bezwaren, en het
/// tweede is het zwaarste:
///
/// 1. Twee van die waarden waren ondoorzichtig — `ocideck_seal_tsr` is een
///    base64-DER-token, `ocideck_sig_image` een base64-PNG — in een bestand dat
///    met een teksteditor te lezen hoort te zijn.
/// 2. Ze gaan *over* het document in plaats van dat ze het document zíjn.
///    Precies de scheiding die `.ink.json`, `.user-notes.json` en `.miauw.json`
///    al maakten.
///
/// En de winst: staat het zegel ernáást, dan kan de hash over de **bytes van de
/// `.md`** gaan in plaats van over de uitvoer van OciDecks eigen serialisator.
/// Daarmee is de integriteitscontrole voor het eerst door een derde na te
/// rekenen, met `sha512sum` en zonder OciDeck. Zie [SealForm] en
/// docs/FILE_FORMAT.md §6.6.
///
/// Zegel en handtekening delen bewust één sidecar. Ze zijn één handeling — "ik
/// verklaar dit, en dit is de vaststelling van wat ik verklaarde" — en een
/// ontvanger moet ze samen krijgen: een handtekening zonder zegel heeft geen
/// anker, en een zegel zonder ondertekenaar zegt niet wie er instaat. Twee
/// bestanden zouden vooral betekenen dat er één van de twee kan zoekraken.
class SealCodec {
  /// De formaatversie van de sidecar. Zie [sidecarIsFromNewerBuild] voor wat er
  /// met een hoger nummer gebeurt: niets laden, en niets overschrijven.
  static const int version = 1;

  static const String finalizedKey = 'finalized';
  static const String hashKey = 'hash';
  static const String algoKey = 'algo';
  static const String atKey = 'at';
  static const String formKey = 'form';
  static const String timestampTokenKey = 'timestamp_token';

  /// De nonce van een uitstaand verzoek.
  ///
  /// Toegevoegd zonder [version] te verhogen, en dat is opzet: een oudere build
  /// leest per sleutel en negeert deze gewoon. Wél verhogen zou die build de
  /// hele sidecar laten weigeren — dan zou het zegel zoekraken om een veld dat
  /// hij niet nodig heeft.
  static const String timestampNonceKey = 'timestamp_nonce';
  static const String signatureKey = 'signature';

  /// De JSON voor [record], of null wanneer er niets vast te leggen is.
  static String? encode(SealRecord record) {
    if (record.isEmpty) return null;
    final sig = record.signature;
    return jsonEncode({
      kSidecarVersionKey: version,
      if (record.finalized) finalizedKey: true,
      if (record.hash.isNotEmpty) ...{
        hashKey: record.hash,
        algoKey: record.algo,
        formKey: record.form.key,
      },
      if (record.at.isNotEmpty) atKey: record.at,
      if (record.timestampToken.isNotEmpty)
        timestampTokenKey: record.timestampToken,
      if (record.timestampNonce.isNotEmpty)
        timestampNonceKey: record.timestampNonce,
      if (sig != null && sig.isNotEmpty) signatureKey: _signatureToJson(sig),
    });
  }

  /// Leest [json] terug, of null wanneer er niets bruikbaars in staat. Een
  /// kapotte of te nieuwe sidecar levert null op: het openen van het deck mag
  /// er nooit op stuklopen, en half inlezen zou erger zijn dan niets inlezen.
  static SealRecord? decode(String json) {
    try {
      final data = jsonDecode(json);
      final fileVersion = declaredSidecarVersion(data);
      if (fileVersion > version) {
        logWarning(
          'SealCodec.decode: seal sidecar is version $fileVersion, this build '
          'reads $version — not loading it',
        );
        return null;
      }
      if (data is! Map) return null;
      final record = SealRecord(
        finalized: data[finalizedKey] == true,
        hash: _text(data[hashKey]),
        algo: _text(data[algoKey]),
        at: _text(data[atKey]),
        form: SealForm.fromKey(_text(data[formKey])),
        timestampToken: _text(data[timestampTokenKey]),
        timestampNonce: _text(data[timestampNonceKey]),
        signature: _signatureFromJson(data[signatureKey]),
      );
      return record.isEmpty ? null : record;
    } catch (e, s) {
      logError('SealCodec.decode: decode seal sidecar JSON', e, s);
      return null;
    }
  }

  static Map<String, String> _signatureToJson(DocumentSignature sig) => {
    if (sig.name.isNotEmpty) 'name': sig.name,
    if (sig.role.isNotEmpty) 'role': sig.role,
    if (sig.certification.isNotEmpty) 'certification': sig.certification,
    if (sig.date.isNotEmpty) 'date': sig.date,
    if (sig.statement.isNotEmpty) 'statement': sig.statement,
    if (sig.typedSignature.isNotEmpty) 'typed': sig.typedSignature,
    if (sig.imagePath.isNotEmpty) 'image': sig.imagePath,
  };

  static DocumentSignature? _signatureFromJson(Object? raw) {
    if (raw is! Map) return null;
    final sig = DocumentSignature(
      name: _text(raw['name']),
      role: _text(raw['role']),
      certification: _text(raw['certification']),
      date: _text(raw['date']),
      statement: _text(raw['statement']),
      typedSignature: _text(raw['typed']),
      imagePath: _text(raw['image']),
    );
    return sig.isEmpty ? null : sig;
  }

  static String _text(Object? raw) => raw is String ? raw : '';
}
