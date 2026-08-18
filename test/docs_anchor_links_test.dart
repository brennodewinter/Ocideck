import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Bewaakt dat een verwijzing tussen twee Markdown-documenten ergens uitkomt.
///
/// `docs_registration_test` bewaakt dát een document bereikbaar is en
/// `docs_claims_match_code_test` of wat er staat waar is. Daartussen zat een
/// gat: een link naar een kop die hernoemd of verplaatst is blijft er in de
/// bron precies hetzelfde uitzien, en op een forge klik je hem stil naar de
/// bovenkant van de pagina. Twee lagen daarvan stonden in `USER_GUIDE.md` — de
/// inhoudsopgave verwees naar `#redaction-leaving-data-out` terwijl de kop
/// *Redaction — leaving data out* heet, en een gedachtestreepje telt in de
/// ankernaam als een extra streepje mee.
///
/// Aanleiding is #589: de README kreeg een link naar de webdemo en daarmee ook
/// twee verse ankers naar `PRIVACY.md` en `KNOWN_LIMITATIONS.md`. Een gate die
/// alleen die twee kende zou de volgende hernoeming weer missen, dus loopt hij
/// alle Markdown in de repo langs.
void main() {
  /// De ankernaam die een forge van een kop maakt.
  ///
  /// Kleine letters, leestekens weg, spaties naar streepjes — en nadrukkelijk
  /// *niet* meerdere spaties samengetrokken: `A — B` verliest het streepje en
  /// houdt de twee spaties eromheen over, wat `a--b` oplevert. Precies dat
  /// dubbele streepje is waar de twee fouten hierboven op stukliepen.
  String ankerVan(String kop) {
    final kaal = kop.trim().toLowerCase().replaceAll(RegExp(r'[^\w\s-]'), '');
    return kaal.replaceAll(RegExp(r'\s'), '-');
  }

  final wortel = Directory.current;

  List<File> markdownBestanden() {
    return wortel
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .where((f) {
          final rel = p.relative(f.path, from: wortel.path);
          // Alleen Markdown die van ons is. `build/` en `.dart_tool/` zijn
          // bouwafval; `third_party/`, `node_modules/` en de
          // `ephemeral/.plugin_symlinks/` van de bureaubladbouw zijn andermans
          // documentatie — een kapotte link daarin zegt niets over deze repo
          // en is niet van ons om te repareren.
          const buiten = [
            'build',
            '.dart_tool',
            'third_party',
            'node_modules',
            'ephemeral',
            'Pods',
          ];
          return !p.split(rel).any(buiten.contains);
        })
        .toList();
  }

  final bestanden = markdownBestanden();

  /// Per bestand de ankers die zijn koppen opleveren.
  final ankersPer = <String, Set<String>>{
    for (final f in bestanden)
      p.canonicalize(f.path): {
        for (final m in RegExp(
          r'^#{1,6}\s+(.*)$',
          multiLine: true,
        ).allMatches(f.readAsStringSync()))
          ankerVan(m.group(1)!),
      },
  };

  test('er is Markdown gevonden om te controleren', () {
    // Zonder deze meting meet de rest niets: een filter dat per ongeluk alles
    // wegvangt zou de hele test stilzwijgend groen maken.
    expect(bestanden.length, greaterThan(20));
  });

  /// Wat er in een codeblok staat is een *voorbeeld*, geen verwijzing.
  /// FILE_FORMAT toont bij het keuze-menu (#1162) de echte bulletvorm —
  /// `[Prijzen](#prijzen)` — en dat anker is een dia in het voorbeelddeck, niet
  /// een kop in dit document. Een gate die daarover klaagt dwingt de
  /// documentatie om de syntaxis te omschrijven in plaats van te tonen, en dat
  /// is precies verkeerd om.
  ///
  /// Simpel heen-en-weer op elke regel die met ``` begint werkt hier niet: deze
  /// documentatie nest codeblokken (een ````markdown-blok met een ```chart-blok
  /// erin) en heeft alinea's die met inline code openen (`` ```cockpit`` ``).
  /// Daarom de CommonMark-regels: de infostring van een openingshek bevat geen
  /// backtick, en alleen een hek zónder infostring dat minstens even lang is
  /// sluit het blok.
  ///
  /// Alleen een hek op kolom 0 telt. Een ingesprongen hek zit in een lijstitem —
  /// zoals de recepten in de CHANGELOG — en die staan niet allemaal netjes in
  /// paren; ze meetellen zou daar een half document aan het oog onttrekken, en
  /// een gate die te weinig ziet is erger dan een die te veel ziet.
  final hekRegel = RegExp(r'^(`{3,})([^`]*)$');

  String zonderCodeblokken(String tekst) {
    final uit = StringBuffer();
    var open = 0; // 0 = geen blok open, anders de lengte van het openingshek.
    for (final regel in tekst.split('\n')) {
      final hek = hekRegel.firstMatch(regel);
      if (hek != null) {
        final lengte = hek.group(1)!.length;
        final info = hek.group(2)!.trim();
        if (open == 0) {
          open = lengte;
          uit.writeln();
          continue;
        }
        if (info.isEmpty && lengte >= open) {
          open = 0;
          uit.writeln();
          continue;
        }
      }
      // De regel blijft staan (leeg) zodat regelnummers niet verschuiven.
      uit.writeln(open == 0 ? regel : '');
    }
    return uit.toString();
  }

  /// Dezelfde redenering als voor codeblokken, maar dan voor `code-spans` in
  /// een lopende zin: `[Prijzen](#prijzen)` tússen backticks is een voorbeeld
  /// van syntaxis, en Markdown maakt er zelf ook geen link van. De span wordt
  /// door blanco's vervangen zodat regel- en kolomnummers niet verschuiven.
  /// `dotAll`, want een span mag over een regeleinde heen lopen — in deze
  /// documenten is dat eerder regel dan uitzondering, omdat de tekst op tachtig
  /// tekens wordt afgebroken.
  final codeSpan = RegExp(r'(`+)(?:(?!\1).)*?\1', dotAll: true);
  final nietRegeleinde = RegExp(r'[^\n]');

  String zonderCodeSpans(String tekst) => tekst.replaceAllMapped(
    codeSpan,
    // Regeleinden blijven staan zodat regelnummers niet verschuiven.
    (m) => m.group(0)!.replaceAll(nietRegeleinde, ' '),
  );

  test('elke link naar een kop komt uit bij een bestaande kop', () {
    // `](pad.md#anker)` en `](#anker)`. Absolute URL's blijven buiten schot:
    // die wijzen naar iets waar deze repo niets over kan zeggen.
    final patroon = RegExp(r'\]\((?!https?:)([^)\s#]+\.md)?#([^)\s]+)\)');
    final klachten = <String>[];

    for (final bestand in bestanden) {
      final tekst = zonderCodeSpans(
        zonderCodeblokken(bestand.readAsStringSync()),
      );
      final hier = p.relative(bestand.path, from: wortel.path);

      for (final m in patroon.allMatches(tekst)) {
        final doelPad = m.group(1);
        final anker = m.group(2)!;
        final doel = doelPad == null
            ? p.canonicalize(bestand.path)
            : p.canonicalize(p.join(p.dirname(bestand.path), doelPad));

        final ankers = ankersPer[doel];
        if (ankers == null) {
          klachten.add('$hier: $doelPad bestaat niet');
          continue;
        }
        if (!ankers.contains(anker)) {
          klachten.add('$hier: #$anker bestaat niet in ${doelPad ?? hier}');
        }
      }
    }

    expect(
      klachten,
      isEmpty,
      reason:
          'Een link naar een kop die niet bestaat springt op een forge stil '
          'naar de bovenkant van de pagina:\n${klachten.join('\n')}',
    );
  });
}
