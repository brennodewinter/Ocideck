import '../models/deck.dart';
import '../models/document_signature.dart';
import '../models/privacy_disposition.dart';
import 'front_matter_merge.dart';

// YAML scalars that need quoting to remain strings in Marp and other readers.
final _yamlSpecial = RegExp('[:#"\u0000-\u001f]');
final _yamlLeadingSigil = RegExp(r'''^[\[\]{}>|*&!%@`,?-]''');
final _yamlReserved = RegExp(
  r'^(?:true|false|null|yes|no|on|off|~)$',
  caseSensitive: false,
);
final _yamlStrippableControl = RegExp(
  '[\u0000-\u0008\u000b\u000c\u000e-\u001f]',
);

/// The front-matter lines owned by OciDeck, in stable serialization order.
List<String> ownedFrontMatterLines(
  Deck deck, {
  required bool includeFormatVersion,
  bool legacySignatureLines = false,
}) {
  final out = <String>['marp: true'];
  if (includeFormatVersion) {
    out.add(
      '$kFormatVersionKey: ${persistedFormatVersion(deck.formatVersion)}',
    );
  }
  out.add('theme: ${deck.theme}');
  if (deck.paginate) out.add('paginate: true');
  if (deck.marpStyle.hasColor) {
    out.add('color: ${markdownYamlScalar(deck.marpStyle.color)}');
  }
  if (deck.marpStyle.hasBackgroundColor) {
    out.add(
      'backgroundColor: ${markdownYamlScalar(deck.marpStyle.backgroundColor)}',
    );
  }
  if (deck.marpStyle.hasBackgroundImage) {
    out.add(
      'backgroundImage: ${markdownYamlScalar(deck.marpStyle.backgroundImage)}',
    );
  }
  if (deck.marpStyle.hasHeader) {
    out.add('header: ${markdownYamlScalar(deck.marpStyle.header)}');
  }
  if (deck.marpStyle.hasFooter) {
    out.add('footer: ${markdownYamlScalar(deck.marpStyle.footer)}');
  }
  if (deck.title.isNotEmpty) {
    out.add('title: ${markdownYamlScalar(deck.title)}');
  }
  if (deck.author.isNotEmpty) {
    out.add('author: ${markdownYamlScalar(deck.author)}');
  }
  if (deck.organization.isNotEmpty) {
    out.add('organization: ${markdownYamlScalar(deck.organization)}');
  }
  if (deck.version.isNotEmpty) {
    out.add('version: ${markdownYamlScalar(deck.version)}');
  }
  if (deck.date.isNotEmpty) {
    out.add('date: ${markdownYamlScalar(deck.date)}');
  }
  if (deck.description.isNotEmpty) {
    out.add('description: ${markdownYamlScalar(deck.description)}');
  }
  if (deck.keywords.isNotEmpty) {
    out.add('keywords: ${markdownYamlScalar(deck.keywords)}');
  }
  if (deck.standardsUsed.isNotEmpty) {
    out.add('standards: ${markdownYamlScalar(deck.standardsUsed.join(', '))}');
  }
  for (final tool in deck.toolsUsed) {
    out.add('tool: ${markdownYamlScalar(tool.format())}');
  }
  if (deck.language.isNotEmpty) {
    out.add('language: ${markdownYamlScalar(deck.language)}');
  }
  if (deck.tlp != TlpLevel.none) out.add('tlp: ${deck.tlp.key}');
  if (deck.privacy != PrivacyDisposition.warn) {
    out.add('privacy: ${deck.privacy.key}');
  }
  if (deck.presentationTargetSeconds > 0) {
    out.add('ocideck_target_seconds: ${deck.presentationTargetSeconds}');
  }
  if (deck.showRehearsalSummary) {
    out.add('ocideck_show_rehearsal_summary: true');
  }
  if (deck.playOnly) out.add('ocideck_play_only: true');
  if (deck.improvementFramework.isNotEmpty) {
    out.add(
      'ocideck_improvement_framework: '
      '${markdownYamlScalar(deck.improvementFramework)}',
    );
  }
  final y01 = deck.improvementY01Metric;
  if (y01.name.isNotEmpty) {
    out.add('ocideck_improvement_y01: ${markdownYamlScalar(y01.name)}');
  }
  if (y01.unit.isNotEmpty) {
    out.add('ocideck_improvement_y01_unit: ${markdownYamlScalar(y01.unit)}');
  }
  void addNumber(String key, double? value) {
    if (value != null) out.add('$key: $value');
  }

  addNumber('ocideck_improvement_y01_usl', y01.usl);
  addNumber('ocideck_improvement_y01_lsl', y01.lsl);
  addNumber('ocideck_improvement_y01_target', y01.target);
  addNumber('ocideck_improvement_y01_baseline', y01.baseline);
  addNumber('ocideck_improvement_y01_goal', y01.goal);
  if (legacySignatureLines) _addLegacySignature(out, deck.signature);
  return out;
}

void _addLegacySignature(List<String> out, DocumentSignature? signature) {
  if (signature == null || signature.isEmpty) return;
  void add(String key, String value) {
    if (value.isNotEmpty) out.add('$key: ${markdownYamlScalar(value)}');
  }

  add('ocideck_sig_name', signature.name);
  add('ocideck_sig_role', signature.role);
  add('ocideck_sig_cert', signature.certification);
  add('ocideck_sig_date', signature.date);
  add('ocideck_sig_statement', signature.statement);
  add('ocideck_sig_typed', signature.typedSignature);
  add('ocideck_sig_image', signature.imagePath);
}

/// Renders a YAML scalar, quoting only when another YAML reader requires it.
String markdownYamlScalar(String value) {
  final clean = value.replaceAll(_yamlStrippableControl, '');
  final needsQuote =
      clean.isEmpty ||
      clean != clean.trim() ||
      _yamlSpecial.hasMatch(clean) ||
      _yamlLeadingSigil.hasMatch(clean) ||
      _yamlReserved.hasMatch(clean);
  if (!needsQuote) return clean;
  final escaped = clean
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t')
      .replaceAll('\n', r'\n');
  return '"$escaped"';
}

/// Parses the scalar subset emitted by [markdownYamlScalar].
String parseMarkdownYamlScalar(String raw) {
  final value = raw.trim();
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return _unescape(value.substring(1, value.length - 1));
  }
  if (value.length >= 2 && value.startsWith("'") && value.endsWith("'")) {
    return value.substring(1, value.length - 1).replaceAll("''", "'");
  }
  return value;
}

String _unescape(String value) {
  final out = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    if (value[i] != r'\'[0] || i + 1 >= value.length) {
      out.write(value[i]);
      continue;
    }
    final next = value[i + 1];
    switch (next) {
      case 'n':
        out.write('\n');
        i++;
      case 'r':
        out.write('\r');
        i++;
      case 't':
        out.write('\t');
        i++;
      case '"':
        out.write('"');
        i++;
      case r'\':
        out.write(r'\');
        i++;
      default:
        out.write(value[i]);
    }
  }
  return out.toString();
}
