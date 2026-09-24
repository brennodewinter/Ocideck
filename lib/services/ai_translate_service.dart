import '../models/deck.dart';
import '../models/slide.dart';
import '../models/timeline.dart';
import 'ai_client_service.dart';
import 'ai_request.dart';
import 'ai_security_gate.dart';
import '../utils/log.dart';
import 'menu_blocks.dart';

/// Vertalen van een hele presentatie via de optionele AI-backend.
///
/// De kernbeslissing: het model ziet alleen kale proza-eenheden. Alles wat
/// structuur draagt — inspringing, checklist- en tussenkop-markeringen,
/// `::`-veldscheidingen, menu-ankers, afbeeldingspaden, gantt-statussen en
/// -afhankelijkheden — wordt vóór het verzoek deterministisch afgesplitst en
/// achteraf weer teruggeschreven. Zo kan het model nooit het bestandsformaat
/// of de interne verwijzingen breken; het enige dat vertaalt is tekst die ook
/// bedoeld is om gelezen te worden.
///
/// Bewust níet meegenomen: alt-teksten, code, grafiek-/vraag-/cockpitblokken
/// (gestructureerde `customMarkdown`), `preservedMarpLines` en identifiers
/// (anchors, finding-id's, scope-verwijzingen).

/// Het segmentmerk waarmee eenheden naar het model en terug gaan. De tekens
/// komen uit een wiskundige-haakjesblok dat in normale proza nooit voorkomt;
/// in de uitzondering dat een tekst ze wél bevat, worden ze eruit gefilterd
/// voordat de segmenten verpakt worden.
const kTranslationMarkOpen = '⟦';
const kTranslationMarkClose = '⟧';

/// Eén te vertalen proza-eenheid, met waar hij teruggeschreven wordt.
typedef TranslationUnit = ({
  /// De `ocideck_ai_assisted`-veldnaam die de eenheid markeert zodra hij
  /// vertaald is (AI_ASSIST §16.3).
  String field,
  String text,
  Slide Function(Slide slide, String translated) write,
});

/// Het vertaalplan van één dia: de platte [units] die het model krijgt en een
/// [apply] die vertaalde eenheden terugschrijft. Eenheden zonder resultaat
/// (gemist, leeg, weggevallen uit een afgebroken antwoord) houden hun
/// oorspronkelijke tekst — falen is per eenheid, nooit per dia.
class SlideTranslationPlan {
  const SlideTranslationPlan._(this.slide, this.units);

  final Slide slide;
  final List<TranslationUnit> units;

  /// Schrijf [translated] terug. `translated[i]` hoort bij `units[i]`; `null`
  /// of blanco betekent 'geen bruikbare vertaling' → origineel blijft staan.
  /// Geeft de bijgewerkte dia plus de veldnamen die echt vertaalden.
  (Slide, Set<String>) apply(List<String?> translated) {
    var out = slide;
    final fields = <String>{};
    for (var i = 0; i < units.length && i < translated.length; i++) {
      final text = translated[i]?.trim();
      if (text == null || text.isEmpty) continue;
      out = units[i].write(out, text);
      fields.add(units[i].field);
    }
    return (out, fields);
  }
}

/// Dia's wiens [Slide.customMarkdown] geen vrije tekst maar een
/// gestructureerd blok is (JSON-spec, grafiekblok, cockpitblok, broncode).
/// Die gaan niet door de vertaler — titels en notities van die dia's wél.
const _structuredBodyTypes = {
  SlideType.question,
  SlideType.chart,
  SlideType.cockpit,
  SlideType.code,
};

/// Bouw het vertaalplan van [slide]: alle proza-velden als geordende eenheden.
SlideTranslationPlan translationPlanFor(Slide slide) {
  final units = <TranslationUnit>[];
  void add(String field, String text, Slide Function(Slide, String) write) {
    if (text.trim().isEmpty) return;
    units.add((field: field, text: text, write: write));
  }

  add('title', slide.title, (s, t) => s.copyWith(title: t));
  add('subtitle', slide.subtitle, (s, t) => s.copyWith(subtitle: t));
  add(
    'columnTitle1',
    slide.columnTitle1,
    (s, t) => s.copyWith(columnTitle1: t),
  );
  add(
    'columnTitle2',
    slide.columnTitle2,
    (s, t) => s.copyWith(columnTitle2: t),
  );
  add(
    'imageCaption',
    slide.imageCaption,
    (s, t) => s.copyWith(imageCaption: t),
  );
  add(
    'imageCaption2',
    slide.imageCaption2,
    (s, t) => s.copyWith(imageCaption2: t),
  );
  // Alleen de tekst van een citaat; de naam van de auteur is een eigennaam en
  // hoort onvertaald te blijven.
  add('quote', slide.quote, (s, t) => s.copyWith(quote: t));
  add('notes', slide.notes, (s, t) => s.copyWith(notes: t));
  if (!_structuredBodyTypes.contains(slide.type)) {
    add(
      'customMarkdown',
      slide.customMarkdown,
      (s, t) => s.copyWith(customMarkdown: t),
    );
  }

  _addBulletUnits(units, slide, 'bullets', slide.bullets);
  _addBulletUnits(units, slide, 'bullets2', slide.bullets2);
  _addTableUnits(units, slide);

  return SlideTranslationPlan._(slide, units);
}

// ── Bullets per dia-type ────────────────────────────────────────────────────

void _addBulletUnits(
  List<TranslationUnit> units,
  Slide slide,
  String field,
  List<String> bullets,
) {
  for (var i = 0; i < bullets.length; i++) {
    switch (slide.type) {
      case SlideType.menu:
        _addMenuBulletUnits(units, field, bullets[i], i);
      case SlideType.timeline:
        _addTimelineBulletUnits(units, field, bullets[i], i);
      case SlideType.flow || SlideType.tree || SlideType.phaseGate:
        _addFlowBulletUnits(units, field, bullets[i], i);
      default:
        _addPlainBulletUnit(units, field, bullets[i], i);
    }
  }
}

/// Schrijf vertaalde [text] terug in bullet [index] van veld [field], met
/// [rebuild] om uit de tussentijdse (al gedeeltelijk vertaalde) bullet weer
/// een geheel te maken.
Slide _writeBullet(
  Slide slide,
  String field,
  int index,
  String text,
  String Function(String current) rebuild,
) {
  final list = field == 'bullets'
      ? List<String>.of(slide.bullets)
      : List<String>.of(slide.bullets2);
  if (index >= list.length) return slide;
  list[index] = rebuild(list[index]);
  return field == 'bullets'
      ? slide.copyWith(bullets: list)
      : slide.copyWith(bullets2: list);
}

/// Gewone bullet: inspringing, checklist-markering en het tussenkop-sentinel
/// zijn van het formaat, niet van de tekst. Alleen de rest vertaalt.
void _addPlainBulletUnit(
  List<TranslationUnit> units,
  String field,
  String raw,
  int index,
) {
  final level = bulletLevel(raw);
  var prefix = '\t' * level;
  var rest = raw.substring(level);
  final check = RegExp(r'^\[[ xX]\]\s*').firstMatch(rest);
  if (check != null) {
    prefix += check.group(0)!;
    rest = rest.substring(check.end);
  }
  if (rest.startsWith(kGroupHeadingMarker)) {
    prefix += kGroupHeadingMarker;
    rest = rest.substring(kGroupHeadingMarker.length);
  }
  if (rest.trim().isEmpty) return;
  units.add((
    field: field,
    text: rest,
    write: (s, t) => _writeBullet(s, field, index, t, (cur) {
      // De prefix is onveranderlijk; de body wordt integraal vervangen.
      return prefix + t;
    }),
  ));
}

/// Menu-blok: `[label](#anker) — uitleg ![](pad)`. Anker en pad zijn
/// verwijzingen; alleen label en uitleg vertalen.
void _addMenuBulletUnits(
  List<TranslationUnit> units,
  String field,
  String raw,
  int index,
) {
  final level = bulletLevel(raw);
  final body = bulletText(raw);
  if (isGroupHeading(body)) {
    final label = groupHeadingText(body);
    if (label.trim().isEmpty) return;
    units.add((
      field: field,
      text: label,
      write: (s, t) => _writeBullet(
        s,
        field,
        index,
        t,
        (cur) => '${'\t' * level}$kGroupHeadingMarker$t',
      ),
    ));
    return;
  }
  final block = parseMenuBlock(body);
  if (block.label.trim().isNotEmpty) {
    units.add((
      field: field,
      text: block.label,
      write: (s, t) => _writeBullet(
        s,
        field,
        index,
        t,
        (cur) =>
            '${'\t' * level}'
            '${menuBlockToBullet(parseMenuBlock(bulletText(cur)).copyWith(label: t))}',
      ),
    ));
  }
  if (block.description.trim().isNotEmpty) {
    units.add((
      field: field,
      text: block.description,
      write: (s, t) => _writeBullet(
        s,
        field,
        index,
        t,
        (cur) =>
            '${'\t' * level}'
            '${menuBlockToBullet(parseMenuBlock(bulletText(cur)).copyWith(description: t))}',
      ),
    ));
  }
}

/// Tijdlijn-event: `marker :: titel :: toelichting`. Alle drie zijn tekst
/// voor de lezer; de scheiding (inclusief ontsnapping) regelt
/// [TimelineEvent.toBullet] zelf.
void _addTimelineBulletUnits(
  List<TranslationUnit> units,
  String field,
  String raw,
  int index,
) {
  final event = TimelineEvent.fromBullet(raw);
  void addPart(String text, TimelineEvent Function(TimelineEvent, String) set) {
    if (text.trim().isEmpty) return;
    units.add((
      field: field,
      text: text,
      write: (s, t) => _writeBullet(
        s,
        field,
        index,
        t,
        (cur) => set(TimelineEvent.fromBullet(cur), t).toBullet(),
      ),
    ));
  }

  addPart(event.marker, (e, t) => e.copyWith(marker: t));
  addPart(event.title, (e, t) => e.copyWith(title: t));
  addPart(event.description, (e, t) => e.copyWith(description: t));
}

/// Flow/tree/phaseGate-bullet: `titel :: kind :: attrs`. Alleen de titel is
/// proza; `kind` en `attrs` (`pt=…;lane=…`) zijn machinevocabulaire en blijven
/// byte-voor-byte staan.
void _addFlowBulletUnits(
  List<TranslationUnit> units,
  String field,
  String raw,
  int index,
) {
  final level = bulletLevel(raw);
  final body = bulletText(raw);
  final sep = body.indexOf('::');
  final title = (sep < 0 ? body : body.substring(0, sep)).trim();
  if (title.isEmpty) return;
  units.add((
    field: field,
    text: title,
    write: (s, t) => _writeBullet(
      s,
      field,
      index,
      t,
      // De huidige staart leidend laten: zo overleeft alles na de eerste
      // `::` exact zoals hij stond.
      (cur) {
        final curBody = bulletText(cur);
        var sep = curBody.indexOf('::');
        // De witruimte vóór `::` hoort bij de staart ('Titel :: kind'), niet
        // bij de titel — anders plakt de vertaling tegen de scheiding aan.
        while (sep > 0 && curBody[sep - 1] == ' ') {
          sep--;
        }
        return '${'\t' * level}$t${sep < 0 ? '' : curBody.substring(sep)}';
      },
    ),
  ));
}

// ── Tabellen ────────────────────────────────────────────────────────────────

void _addTableUnits(List<TranslationUnit> units, Slide slide) {
  final rows = slide.tableRows;
  if (rows.isEmpty) return;
  if (slide.type == SlideType.gantt) {
    _addGanttTableUnits(units, slide);
    return;
  }
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      _addCellUnit(units, field: 'tableRows', cell: rows[r][c], row: r, col: c);
    }
  }
}

/// Gantt-tabel (Taak | Start | Duur | Voortgang | Afhankelijk van): alleen de
/// koprij en de taaknamen (kolom 0) zijn proza. Start/Duur/Voortgang zijn
/// DSL-waarden en 'Afhankelijk van' verwijst naar taaknamen — die kolom wordt
/// in [applyGanttDependencies] herschreven met de vertaalde namen, niet door
/// het model.
void _addGanttTableUnits(List<TranslationUnit> units, Slide slide) {
  final rows = slide.tableRows;
  // Koprij: alle labels zijn zichtbare tekst.
  for (var c = 0; c < rows.first.length; c++) {
    _addCellUnit(
      units,
      field: 'tableRows',
      cell: rows.first[c],
      row: 0,
      col: c,
    );
  }
  for (var r = 1; r < rows.length; r++) {
    final cell = rows[r].isEmpty ? '' : rows[r][0];
    // `## ` (sectiekop) en `Milestone: ` zijn formaatprefixen; de naam zelf
    // vertaalt wel.
    var prefix = '';
    var name = cell;
    if (name.startsWith('## ')) {
      prefix = '## ';
      name = name.substring(3);
    } else if (name.startsWith('Milestone: ')) {
      prefix = 'Milestone: ';
      name = name.substring('Milestone: '.length);
    }
    if (name.trim().isEmpty) continue;
    units.add((
      field: 'tableRows',
      text: name,
      write: (s, t) => _writeCell(s, r, 0, '$prefix$t'),
    ));
  }
}

void _addCellUnit(
  List<TranslationUnit> units, {
  required String field,
  required String cell,
  required int row,
  required int col,
}) {
  // Cellen zonder letter (datums, getallen, percentages, vinkjes) zijn data —
  /// niet te vertalen en aan geen model toe te vertrouwen.
  if (!RegExp(r'\p{L}', unicode: true).hasMatch(cell)) return;
  units.add((
    field: field,
    text: cell,
    write: (s, t) => _writeCell(s, row, col, t),
  ));
}

Slide _writeCell(Slide slide, int row, int col, String text) {
  final rows = [for (final r in slide.tableRows) List<String>.of(r)];
  if (row >= rows.length || col >= rows[row].length) return slide;
  rows[row][col] = text;
  return slide.copyWith(tableRows: rows);
}

/// Herschrijf de gantt-kolom 'Afhankelijk van' (index 4) nadat de taaknamen in
/// kolom 0 vertaald zijn: elke komma-gescheiden naam wordt vervangen door zijn
/// vertaling, zodat `after`-verwijzingen consistent blijven. Namen die niet
/// vertaalden (of niet bestaan) blijven staan.
Slide applyGanttDependencies(Slide before, Slide after) {
  if (after.type != SlideType.gantt) return after;
  final names = <String, String>{};
  for (
    var r = 1;
    r < before.tableRows.length && r < after.tableRows.length;
    r++
  ) {
    final oldName = _ganttName(before.tableRows[r][0]);
    final newName = _ganttName(after.tableRows[r][0]);
    if (oldName.isNotEmpty && oldName != newName) names[oldName] = newName;
  }
  if (names.isEmpty) return after;
  final rows = [for (final r in after.tableRows) List<String>.of(r)];
  for (var r = 1; r < rows.length; r++) {
    if (rows[r].length <= 4) continue;
    final deps = rows[r][4].split(',');
    var changed = false;
    for (var i = 0; i < deps.length; i++) {
      final name = deps[i].trim();
      final renamed = names[name];
      if (renamed != null) {
        deps[i] = ' $renamed';
        changed = true;
      }
    }
    if (changed) rows[r][4] = deps.join(',').trim();
  }
  return after.copyWith(tableRows: rows);
}

/// De kale taaknaam zonder `## `- of `Milestone: `-prefix.
String _ganttName(String cell) {
  var name = cell.trim();
  if (name.startsWith('## ')) name = name.substring(3).trim();
  if (name.startsWith('Milestone: ')) {
    name = name.substring('Milestone: '.length).trim();
  }
  return name;
}

// ── Verpakken en teruglezen ─────────────────────────────────────────────────

/// Verpak [units] als gemarkeerde segmenten voor het verzoek. De merktekens
/// worden uit de inhoud gefilterd — anders zou een tekst met `⟦` de teruglezing
/// van de segmenten breken.
String packTranslationUnits(List<String> units) => [
  for (var i = 0; i < units.length; i++)
    '$kTranslationMarkOpen${i + 1}$kTranslationMarkClose '
        '${units[i].replaceAll(kTranslationMarkOpen, '').replaceAll(kTranslationMarkClose, '')}',
].join('\n');

/// Lees de gemarkeerde segmenten uit het antwoord terug. Alles vóór de eerste
/// markering (een preambule) en alles zonder nummer wordt genegeerd; ontbrekende
/// nummers blijven simpelweg afwezig in de map.
Map<int, String> parseTranslationResponse(String raw) {
  final marks = RegExp(
    '${RegExp.escape(kTranslationMarkOpen)}\\s*(\\d+)\\s*'
    '${RegExp.escape(kTranslationMarkClose)}',
  ).allMatches(raw).toList();
  final out = <int, String>{};
  for (var i = 0; i < marks.length; i++) {
    final n = int.tryParse(marks[i].group(1)!);
    if (n == null) continue;
    final end = i + 1 < marks.length ? marks[i + 1].start : raw.length;
    out[n] = raw.substring(marks[i].end, end).trim();
  }
  return out;
}

/// De system-instructie voor een vertaalverzoek. Anders dan de
/// 'grounded draft'-guardrail van [AiPrompts]: vertalen is geen feitenwerk —
/// elke eenheid moet wél iets teruggeven.
String translationSystemPrompt(String languageName) =>
    'You are a professional translator embedded in a presentation tool. '
    'Translate every numbered segment into $languageName. Rules: keep '
    'Markdown and HTML syntax (headings, emphasis, links, images, comments, '
    'footnotes) exactly as-is; never translate URLs, file paths, anchor '
    'names, code, or proper names; keep callout letters like "(A)" and '
    'checkbox markers unchanged. Return the segments in order, each starting '
    'with its own $kTranslationMarkOpen'
    'n$kTranslationMarkClose marker. '
    'No preamble, no commentary.';

/// Het resultaat van een deckvertaling.
class DeckTranslationResult {
  const DeckTranslationResult({
    required this.deck,
    required this.translatedSlides,
    required this.failedSlides,
  });

  /// Het vertaalde deck (kopie; het bron-deck is ongemoeid gebleven).
  final Deck deck;

  /// Dia's met minstens één vertaalde eenheid.
  final int translatedSlides;

  /// Dia's waarvan het verzoek faalde — die staan onvertaald in [deck].
  final int failedSlides;
}

/// De deckvertaler als consumer van de gegate [AiClientService]. Eén verzoek
/// per dia houdt de antwoorden klein en maakt voortgang én annuleren per dia
/// mogelijk; deck-titel en -beschrijving gaan in een eigen verzoek vooraf.
class AiTranslateService {
  AiTranslateService(this._client);

  final AiClientService _client;

  /// Vertaal [deck] naar [languageCode] (weggeschreven in `Deck.language`,
  /// zodat o.a. getalopmaak meegaat) met weergavenaam [languageName] in de
  /// prompt. [onProgress] rapporteert `done` van `total` (dia's + het
  /// deck-metablock); [isCancelled] breekt de run af en levert `null`.
  ///
  /// Een dia waarvan het verzoek faalt blijft onvertaald — beter een deck met
  /// drie Nederlandse dia's ertussen dan een halve run die niets oplevert.
  Future<DeckTranslationResult?> translateDeck({
    required Deck deck,
    required String languageCode,
    required String languageName,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final cancelled = isCancelled ?? () => false;
    final total = deck.slides.length + 1;
    var done = 0;

    // ── Deck-meta (titel + beschrijving) ──
    var title = deck.title;
    var description = deck.description;
    final metaUnits = [
      if (deck.title.trim().isNotEmpty) deck.title,
      if (deck.description.trim().isNotEmpty) deck.description,
    ];
    if (metaUnits.isNotEmpty && !cancelled()) {
      try {
        final translated = await _translateUnits(metaUnits, languageName);
        var i = 0;
        if (deck.title.trim().isNotEmpty) {
          title = translated[i] ?? deck.title;
          i++;
        }
        if (deck.description.trim().isNotEmpty) {
          description = translated[i] ?? deck.description;
        }
      } on AiGateException {
        rethrow;
      } catch (error, stack) {
        // Meta mislukt is geen ramp: de dia's gaan gewoon door.
        logError('AiTranslateService.translateDeck: deck-meta', error, stack);
      }
    }
    if (cancelled()) return null;
    onProgress?.call(++done, total);

    // ── Per dia ──
    var translatedCount = 0;
    var failedCount = 0;
    final slides = <Slide>[];
    for (final slide in deck.slides) {
      if (cancelled()) return null;
      final plan = translationPlanFor(slide);
      if (plan.units.isEmpty) {
        slides.add(slide);
        onProgress?.call(++done, total);
        continue;
      }
      try {
        final translated = await _translateUnits([
          for (final u in plan.units) u.text,
        ], languageName);
        final (updated, fields) = plan.apply(translated);
        var out = applyGanttDependencies(plan.slide, updated);
        for (final field in fields) {
          out = out.withAiAssistedField(field, present: true);
        }
        slides.add(out);
        if (fields.isNotEmpty) translatedCount++;
      } on AiGateException {
        // Een gate-weigering is permanent (toestemming/configuratie) — elke
        // volgende dia zou hetzelfde falen. Doorgeven, niet per dia tellen.
        rethrow;
      } catch (error, stack) {
        logError('AiTranslateService.translateDeck: dia', error, stack);
        failedCount++;
        slides.add(slide);
      }
      onProgress?.call(++done, total);
    }

    return DeckTranslationResult(
      deck: deck.copyWith(
        title: title,
        description: description,
        language: languageCode,
        slides: slides,
      ),
      translatedSlides: translatedCount,
      failedSlides: failedCount,
    );
  }

  /// Eén verzoek: [units] in, vertaalde eenheden op index uit.
  /// `null` op een plek betekent 'deze eenheid is niet vertaald'.
  Future<List<String?>> _translateUnits(
    List<String> units,
    String languageName,
  ) async {
    final response = await _client.chat(
      AiChatRequest(
        model: _client.settings.model,
        messages: [
          AiMessage.text(AiRole.system, translationSystemPrompt(languageName)),
          AiMessage.text(AiRole.user, packTranslationUnits(units)),
        ],
      ),
    );
    final parsed = parseTranslationResponse(response.text);
    return [
      for (var i = 0; i < units.length; i++)
        parsed[i + 1]?.isNotEmpty == true ? parsed[i + 1] : null,
    ];
  }
}
