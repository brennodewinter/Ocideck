// Part of the markdown_service library — see ../markdown_service.dart.
// Split out for navigability (de front matter: de `--- … ---`-kop van een deck,
// plus de struct waarin hij landt). Alle imports leven in het hoofdbestand.
part of '../markdown_service.dart';

/// Mutable accumulator for the deck-level front-matter fields, filled by
/// [_MarkdownParseFrontMatter._parseFrontMatter]. Held as a struct — the same
/// idiom as [_BodyParse] — so [_MarkdownParse._doParse] stays short and the
/// per-key switch reads top-to-bottom.
class _FrontMatter {
  String theme = 'ocideck';
  bool paginate = true;

  /// De MIAUW-dispositie uit een bestand van vóór 0.1.0, toen ze nog als
  /// base64 in de front matter stond. Nieuwe bestanden dragen haar in de
  /// `.miauw.json`-sidecar; die overschrijft dit bij het openen. Zie
  /// [MiauwCodec.legacyFrontMatterMap].
  Map<String, String> legacyMiauwWaivers = const {};
  Map<String, String> legacyMiauwConfirmations = const {};
  String? presentationTitle;
  String author = '';
  String language = '';
  List<String> standardsUsed = const [];
  final List<UsedTool> toolsUsed = [];
  String organization = '';
  String version = '';
  String date = '';
  String description = '';
  String keywords = '';
  TlpLevel tlp = TlpLevel.none;
  PrivacyDisposition privacy = PrivacyDisposition.warn;
  int presentationTargetSeconds = 0;
  bool showRehearsalSummary = false;
  bool playOnly = false;
  String improvementFramework = '';
  String improvementY01 = '';
  String improvementY01Unit = '';
  double? improvementY01Usl;
  double? improvementY01Lsl;
  double? improvementY01Target;
  double? improvementY01Baseline;
  double? improvementY01Goal;
  bool finalized = false;
  String sealHash = '';
  String sealAlgo = '';
  String sealAt = '';
  String sealTsr = '';
  DocumentSignature signature = const DocumentSignature();

  /// De front-matter-regels precies zoals ze in het bestand stonden, inclusief
  /// wat de switch hieronder niet herkent. Zie [Deck.frontMatterSource].
  List<String> sourceLines = const [];

  /// De formaatversie die het bestand declareerde; ontbreekt de sleutel, dan is
  /// het de oudste versie. Zie [Deck.formatVersion].
  int formatVersion = kOldestFormatVersion;

  /// The markdown body with the front-matter block stripped off.
  String body = '';
}

extension _MarkdownParseFrontMatter on MarkdownService {
  /// Parses and strips the optional `---`-delimited front matter, returning the
  /// deck-level fields plus the remaining markdown ([_FrontMatter.body]).
  /// Extracted from [_doParse] to keep that method under the length limit;
  /// behaviour is identical to the previous inline block.
  _FrontMatter _parseFrontMatter(String markdown) {
    final fm = _FrontMatter();
    String content = markdown;

    if (content.startsWith('---\n')) {
      final end = content.indexOf('\n---\n', 4);
      if (end != -1) {
        final frontMatter = content.substring(4, end);
        fm.sourceLines = frontMatter.split('\n');
        for (final rawLine in fm.sourceLines) {
          // Alleen een sleutel op kolom 0 telt — [frontMatterKeyOf] is dezelfde
          // toets die [mergeFrontMatter] gebruikt bij het terugschrijven, zodat
          // lezen en schrijven het over de grenzen van een blok eens zijn. Een
          // ingesprongen regel hoort bij het blok erboven: de CSS in een
          // `style: |` mag geen deck-velden zetten. Splitsen op de *eerste*
          // dubbele punt houdt dubbele punten in de waarde heel (een ISO-datum).
          final key = frontMatterKeyOf(rawLine);
          if (key == null) continue;
          final value = rawLine.substring(rawLine.indexOf(':') + 1).trim();
          // Visual-signature fields share a prefix; fold them into the
          // accumulator here so the switch below stays short.
          if (key.startsWith('ocideck_sig_')) {
            fm.signature = _applySignatureField(
              fm.signature,
              key,
              _parseScalar(value),
            );
            continue;
          }
          switch (key) {
            case 'theme':
              fm.theme = value;
            case 'paginate':
              fm.paginate = value == 'true';
            case 'title':
              fm.presentationTitle = _parseScalar(value);
            case 'author':
              fm.author = _parseScalar(value);
            case 'organization':
              fm.organization = _parseScalar(value);
            case 'version':
              fm.version = _parseScalar(value);
            case 'date':
              fm.date = _parseScalar(value);
            case 'description':
              fm.description = _parseScalar(value);
            case 'keywords':
              fm.keywords = _parseScalar(value);
            case 'language':
              fm.language = _parseScalar(value);
            case 'tool':
              // Meerdere `tool:`-regels stapelen in plaats van elkaar te
              // overschrijven — anders houdt een deck maar één hulpmiddel over.
              final tool = UsedTool.parse(_parseScalar(value));
              if (tool != null) fm.toolsUsed.add(tool);
            case 'standards':
              fm.standardsUsed = _parseScalar(value)
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
            case 'tlp':
              fm.tlp = TlpLevelX.fromKey(value);
            case 'privacy':
              fm.privacy = PrivacyDispositionX.fromKey(value);
            case kFormatVersionKey:
              fm.formatVersion = readFormatVersion(value);
            case 'ocideck_target_seconds':
              fm.presentationTargetSeconds = int.tryParse(value) ?? 0;
            case 'ocideck_show_rehearsal_summary':
              fm.showRehearsalSummary = value == 'true';
            case 'ocideck_play_only':
              fm.playOnly = value == 'true';
            case 'ocideck_improvement_framework':
              fm.improvementFramework = _parseScalar(value);
            case 'ocideck_improvement_y01':
              fm.improvementY01 = _parseScalar(value);
            case 'ocideck_improvement_y01_unit':
              fm.improvementY01Unit = _parseScalar(value);
            case 'ocideck_improvement_y01_usl':
              fm.improvementY01Usl = double.tryParse(value.trim());
            case 'ocideck_improvement_y01_lsl':
              fm.improvementY01Lsl = double.tryParse(value.trim());
            case 'ocideck_improvement_y01_target':
              fm.improvementY01Target = double.tryParse(value.trim());
            case 'ocideck_improvement_y01_baseline':
              fm.improvementY01Baseline = double.tryParse(value.trim());
            case 'ocideck_improvement_y01_goal':
              fm.improvementY01Goal = double.tryParse(value.trim());
            case 'ocideck_finalized':
              fm.finalized = value == 'true';
            case 'ocideck_seal_hash':
              fm.sealHash = _parseScalar(value);
            case 'ocideck_seal_algo':
              fm.sealAlgo = _parseScalar(value);
            case 'ocideck_seal_at':
              fm.sealAt = _parseScalar(value);
            case 'ocideck_seal_tsr':
              fm.sealTsr = value;
            // Alleen lezen, nooit meer schrijven: het opwaardeerpad voor een
            // bestand van vóór 0.1.0.
            case 'ocideck_miauw_waivers':
              fm.legacyMiauwWaivers = MiauwCodec.legacyFrontMatterMap(
                value,
                key,
              );
            case 'ocideck_miauw_confirmations':
              fm.legacyMiauwConfirmations = MiauwCodec.legacyFrontMatterMap(
                value,
                key,
              );
          }
        }
        content = content.substring(end + 5).trim();
      }
    }

    fm.body = content;
    return fm;
  }

  /// Folds one `ocideck_sig_*` front-matter field into the running visual
  /// signature (§8 A1). Unknown `ocideck_sig_*` keys are ignored so a future
  /// field never breaks the parse.
  DocumentSignature _applySignatureField(
    DocumentSignature sig,
    String key,
    String value,
  ) {
    switch (key) {
      case 'ocideck_sig_name':
        return sig.copyWith(name: value);
      case 'ocideck_sig_role':
        return sig.copyWith(role: value);
      case 'ocideck_sig_cert':
        return sig.copyWith(certification: value);
      case 'ocideck_sig_date':
        return sig.copyWith(date: value);
      case 'ocideck_sig_statement':
        return sig.copyWith(statement: value);
      case 'ocideck_sig_typed':
        return sig.copyWith(typedSignature: value);
      case 'ocideck_sig_image':
        return sig.copyWith(imagePath: value);
      default:
        return sig;
    }
  }
}
