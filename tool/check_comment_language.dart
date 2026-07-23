// Bewaakt de commentaartaalregel uit CONTRIBUTING: **Nederlands of Engels, maar
// nooit allebei in één commentaarblok** — voor gewoon commentaar. Dartdoc valt
// er bewust buiten; zie [CommentBlock.isMixed] voor de reden.
//
// Waarom alleen het mengen en niet de taalkeuze zelf: CONTRIBUTING zegt er
// uitdrukkelijk bij dat een taalheuristiek die 5% van de tijd fout zit een
// slechtere poort is dan geen poort. Dat klopt — voor *classificeren* ("is dit
// blok Nederlands of Engels?"), want daar moet elk blok een antwoord krijgen en
// telt elke twijfel mee. Mengdetectie is een andere vraag: die zwijgt tenzij er
// van béide talen hard bewijs is, en twijfelgevallen leveren dus geen melding
// op maar stilte. Dat is de reden dat dít wél te bewaken valt en de taalkeuze
// niet.
//
// De regel bestaat omdat een blok dat halverwege van taal wisselt niet leest.
// De codebase is tweetalig en blijft dat; dat is geen slordigheid maar een
// keuze. Wat niet werkt is één gedachte in twee talen afmaken.
//
// Meten gebeurt op de commentaartokens uit de `analyzer` — niet op regels die
// op `//` lijken, want dan telt elke URL en elk stukje Markdown in een string
// mee.
//
// Exits non-zero met de plekken zodra er meer gemengde blokken zijn dan de
// basislijn.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/line_info.dart';

/// Hoeveel gemengde blokken er nog in de boom staan. RATCHET: mag dalen, nooit
/// stijgen.
///
/// Niet nul, en die tien worden hier ook niet weggewerkt: CONTRIBUTING verbiedt
/// het herschrijven van bestaand commentaar alléén om de taal te wijzigen —
/// duizenden regels ruis met andermans redenering onder jouw naam in `git
/// blame`. Ze zakken vanzelf, want wie zo'n blok tóch bewerkt volgt de regel.
const int mixedCommentBaseline = 10;

/// Woorden die in het Nederlands gewoon zijn en in het Engels niet bestaan (of
/// zó zeldzaam zijn dat ze in code-commentaar niet voorkomen).
///
/// Bewust géén woorden die in beide talen bestaan — `in`, `is`, `of`, `over`,
/// `we`, `was`, `die`, `van`, `door`. Eén zo'n woord in de lijst maakt van elk
/// Engels blok een halve treffer, en dan meet de poort zichzelf.
const Set<String> dutchMarkers = {
  'aan',
  'als',
  'altijd',
  'behalve',
  'bestand',
  'bij',
  'blijft',
  'daar',
  'daarna',
  'daarom',
  'dan',
  'dat',
  'deze',
  'dus',
  'echt',
  'eerst',
  'elke',
  'geen',
  'geeft',
  'gewoon',
  'haar',
  'het',
  'hier',
  'hoort',
  'iets',
  'kan',
  'komt',
  'kunnen',
  'laat',
  'meer',
  'met',
  'moet',
  'moeten',
  'naar',
  'niet',
  'niets',
  'nooit',
  'omdat',
  'ook',
  'precies',
  'staat',
  'terwijl',
  'tussen',
  'uit',
  'vandaar',
  'veel',
  'voor',
  'waar',
  'waarom',
  'want',
  'wordt',
  'worden',
  'zodat',
  'zonder',
};

/// Idem, andersom. Geen `in`, `is`, `of`, `over`, `we`, `was`.
const Set<String> englishMarkers = {
  'after',
  'also',
  'always',
  'and',
  'because',
  'been',
  'before',
  'both',
  'could',
  'does',
  'each',
  'every',
  'from',
  'has',
  'have',
  'instead',
  'into',
  'its',
  'just',
  'never',
  'only',
  'otherwise',
  'should',
  'since',
  'still',
  'than',
  'that',
  'the',
  'their',
  'then',
  'there',
  'these',
  'they',
  'this',
  'those',
  'through',
  'when',
  'where',
  'whether',
  'which',
  'while',
  'with',
  'without',
  'would',
};

/// Hoeveel *verschillende* markers van beide talen een blok moet dragen voor het
/// als gemengd telt.
///
/// Twee en niet één, omdat één Engels woord in een Nederlands blok bijna altijd
/// een geciteerde term is en geen taalwissel — en precies die citaten zijn wat
/// een naïeve teller de hele dag laat afgaan.
const int markersNeeded = 2;

/// Eén commentaarblok: aaneengesloten `//`- of `///`-regels, of één `/* */`.
class CommentBlock {
  final String path;
  final int line;
  final String text;

  /// Of dit een dartdoc (`///`) is en geen gewoon commentaar.
  final bool isDoc;

  CommentBlock(this.path, this.line, this.text, {required this.isDoc});

  /// De woorden waarop geteld wordt.
  ///
  /// Weggehaald vóór het tellen: alles tussen backticks (identifiers en
  /// codefragmenten), alles tussen aanhalingstekens (geciteerde interfaceteksten
  /// — die zijn per definitie in een andere taal dan het commentaar eromheen),
  /// URL's, en woorden met een hoofdletter middenin een zin (typenamen).
  static final _fence = RegExp(r'`[^`]*`');
  static final _quoted = RegExp('"[^"]*"|“[^”]*”');
  static final _url = RegExp(r'https?://\S+');
  static final _word = RegExp(r"[a-zA-Zà-üÀ-Ü']+");

  Iterable<String> get words {
    final stripped = text
        .replaceAll(_fence, ' ')
        .replaceAll(_quoted, ' ')
        .replaceAll(_url, ' ');
    // Wél kleingemaakt en niet weggegooid: een blok begint vaak met "The …" of
    // "Het …", en dat is juist de sterkste aanwijzing die er is. Hoofdletters
    // filteren om typenamen te weren kostte precies die woorden — en het levert
    // niets op, want de markerlijsten bevatten alleen functiewoorden en daar
    // heet geen enkel type naar.
    return _word.allMatches(stripped).map((m) => m.group(0)!.toLowerCase());
  }

  Set<String> markersOf(Set<String> vocabulary) =>
      words.where(vocabulary.contains).toSet();

  /// Of dit blok halverwege van taal wisselt.
  ///
  /// Dartdoc telt niet mee, en dat is geen gemakzucht maar de enige uitkomst
  /// die met de rest van CONTRIBUTING klopt. Datzelfde document schrijft
  /// namelijk vóór dat nieuwe publieke types in `lib/models/` en
  /// `lib/services/` een *Engelse* dartdoc krijgen — dat is de laag die
  /// `dart doc`, pub.dev en de IDE tonen — terwijl de redenering eronder in de
  /// werktaal Nederlands staat. Eén Engelse samenvattingsregel plus een
  /// Nederlandse alinea eronder is dus geen overtreding maar precies wat er
  /// gevraagd wordt, en gemeten op 2026-07-23 is dát de vorm van 37 van de 47
  /// treffers. Een poort die de eigen bijdragersgids beboet, is een poort die
  /// wordt uitgezet.
  ///
  /// Bij gewoon commentaar bestaat die tweede regel niet: daar is een
  /// taalwissel binnen één blok altijd wat de regel bedoelt. Alle tien de
  /// treffers in die groep zijn met de hand nagekeken en alle tien echt — van
  /// een Engelse alinea met een Nederlandse eronder tot één zin die in het
  /// Engels begint en in het Nederlands afloopt.
  bool get isMixed =>
      !isDoc &&
      markersOf(dutchMarkers).length >= markersNeeded &&
      markersOf(englishMarkers).length >= markersNeeded;
}

List<CommentBlock> commentBlocks(File file) {
  final source = file.readAsStringSync();
  final unit = parseString(
    content: source,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  ).unit;
  final lineInfo = LineInfo.fromContent(source);
  final path = file.path.replaceAll(r'\', '/');

  final blocks = <CommentBlock>[];
  // Losse `//`-regels die direct op elkaar volgen zijn één gedachte en dus één
  // blok; een lege regel ertussen breekt hem. Zonder dat samenvoegen zou een
  // Nederlandse alinea met één Engelse citaatregel nooit als één blok gemeten
  // worden — en dat is juist het geval waar de regel over gaat.
  var buffer = StringBuffer();
  var bufferLine = 0;
  var bufferIsDoc = false;
  var previousLine = -2;

  void flush() {
    if (buffer.isEmpty) return;
    blocks.add(
      CommentBlock(path, bufferLine, buffer.toString(), isDoc: bufferIsDoc),
    );
    buffer = StringBuffer();
  }

  for (var token = unit.beginToken; ; token = token.next!) {
    for (Token? c = token.precedingComments; c != null; c = c.next) {
      final line = lineInfo.getLocation(c.offset).lineNumber;
      final isLineComment = c.lexeme.startsWith('//');
      final isDoc = c.lexeme.startsWith('///');
      if (!isLineComment || line != previousLine + 1 || isDoc != bufferIsDoc) {
        flush();
        bufferLine = line;
        bufferIsDoc = isDoc;
      }
      buffer.writeln(c.lexeme.replaceFirst(RegExp(r'^/[/*]+'), ''));
      previousLine = line;
    }
    if (token.next == null || token == token.next) break;
  }
  flush();
  return blocks;
}

Iterable<File> dartFiles(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    // De vertaalbestanden zijn data, geen proza: 3.000 regels sleutel-waarde
    // met hooguit een kopregel erboven.
    .where((f) => !f.path.replaceAll(r'\', '/').contains('lib/l10n/'));

void main(List<String> args) {
  final listing = args.contains('--list');
  final mixed = <CommentBlock>[];
  for (final file in dartFiles(Directory('lib'))) {
    for (final block in commentBlocks(file)) {
      if (block.isMixed) mixed.add(block);
    }
  }

  if (listing) {
    for (final block in mixed) {
      stdout.writeln(
        '${block.path}:${block.line} ${block.isDoc ? "DOC" : "//"}',
      );
      stdout.writeln(block.text.trim());
      stdout.writeln('  NL: ${block.markersOf(dutchMarkers).join(", ")}');
      stdout.writeln('  EN: ${block.markersOf(englishMarkers).join(", ")}');
      stdout.writeln('---');
    }
  }

  if (mixed.length > mixedCommentBaseline) {
    stdout.writeln('Comment language check FAILED:');
    stdout.writeln(
      '  ${mixed.length} commentaarblok(ken) mengen Nederlands en Engels '
      '(basislijn $mixedCommentBaseline). CONTRIBUTING: kies één taal per '
      'blok en maak de gedachte daarin af. Bewerk je een bestaand blok, volg '
      'dan de taal die er al staat — herschrijven puur om de taal te wijzigen '
      'is nadrukkelijk niet de bedoeling.',
    );
    for (final block in mixed.take(20)) {
      stdout.writeln('    ${block.path}:${block.line}');
    }
    stdout.writeln(
      '  Volledige lijst met de gewogen woorden: '
      'dart run tool/check_comment_language.dart --list',
    );
    exit(1);
  }
  stdout.writeln(
    'Comment language OK: ${mixed.length} gemengd commentaarblok(ken) '
    '(basislijn $mixedCommentBaseline); dartdoc telt niet mee, zie isMixed.',
  );
  if (mixed.length < mixedCommentBaseline) {
    stdout.writeln(
      'Tip: de basislijn kan naar ${mixed.length} — verlaag hem in '
      'tool/check_comment_language.dart om de winst vast te zetten.',
    );
  }
}
