import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/markdown_kind.dart';
import '../utils/atomic_file.dart';
import '../utils/json_depth_guard.dart';
import '../utils/log.dart';

/// Eén automatisch bewaard herstelbestand voor een (nog) niet-opgeslagen deck of
/// document.
class RecoverySnapshot {
  final String id;
  final DateTime savedAt;
  final String? filePath;
  final String label;
  final String markdown;

  /// Of deze momentopname een presentatie of een document is, zodat het herstel
  /// de juiste soort tabblad terugzet. Oude herstelbestanden dragen geen sleutel
  /// en vallen terug op [MarkdownKind.presentation] — backward compatible.
  final MarkdownKind kind;

  /// Unapplied source-editor text. Kept separate from [markdown], which must
  /// remain parseable so recovery can always reopen the last valid deck.
  final String? markdownDraft;
  final String? markdownDraftScope;
  final int? markdownDraftSlideIndex;

  /// JSON payload from [UserNotesCodec.encode], when the deck has user notes.
  final String? userNotes;

  /// JSON payload from [MiauwCodec.encode], when the deck carries a MIAUW
  /// disposition. Reist apart mee om dezelfde reden als [userNotes]: sinds
  /// 0.1.0 staat ze niet meer in de markdown, dus een momentopname die alleen
  /// de markdown bewaart zou de afspraken met de klant kwijtraken.
  final String? miauw;

  /// JSON-payload van [SealCodec.encode], als het deck is afgerond of een
  /// handtekening draagt. Reist mee om dezelfde reden als [userNotes]: sinds
  /// 0.1.0 staat het zegelblok niet meer in de markdown, en juist ná het
  /// verzegelen — wanneer het deck vuil is maar nog niet opgeslagen — zou een
  /// momentopname anders de zojuist gezette handtekening kwijtraken.
  final String? seal;

  /// JSON-payload van [AnnotationCodec.encode], als er tekeningen op de slides
  /// staan.
  ///
  /// Annotaties maken het deck vuil ([DeckNotifier.setAnnotations]), dus een
  /// deck waarin alleen getekend is komt hier terecht — en zonder dit veld gaf
  /// herstel het deck stil zonder die tekeningen terug. Ze leven op schijf in
  /// een eigen sidecar (`.ink.json`) en zitten dus níét in [markdown]; wie ze
  /// wil bewaren moet ze apart meenemen.
  final String? annotations;

  const RecoverySnapshot({
    required this.id,
    required this.savedAt,
    required this.filePath,
    required this.label,
    required this.markdown,
    this.kind = MarkdownKind.presentation,
    this.markdownDraft,
    this.markdownDraftScope,
    this.markdownDraftSlideIndex,
    this.userNotes,
    this.miauw,
    this.seal,
    this.annotations,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'savedAt': savedAt.toIso8601String(),
    'filePath': filePath,
    'label': label,
    'markdown': markdown,
    'kind': kind.key,
    if (markdownDraft != null) 'markdownDraft': markdownDraft,
    if (markdownDraftScope != null) 'markdownDraftScope': markdownDraftScope,
    if (markdownDraftSlideIndex != null)
      'markdownDraftSlideIndex': markdownDraftSlideIndex,
    if (userNotes != null) 'userNotes': userNotes,
    if (miauw != null) 'miauw': miauw,
    if (seal != null) 'seal': seal,
    if (annotations != null) 'annotations': annotations,
  };

  static RecoverySnapshot fromJson(Map<String, Object?> json) {
    return RecoverySnapshot(
      id: json['id'] as String,
      savedAt:
          DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now(),
      filePath: json['filePath'] as String?,
      label: (json['label'] as String?) ?? 'Presentatie',
      markdown: (json['markdown'] as String?) ?? '',
      kind: MarkdownKindX.fromKey(json['kind'] as String?),
      markdownDraft: json['markdownDraft'] as String?,
      markdownDraftScope: json['markdownDraftScope'] as String?,
      markdownDraftSlideIndex: json['markdownDraftSlideIndex'] as int?,
      userNotes: json['userNotes'] as String?,
      miauw: json['miauw'] as String?,
      seal: json['seal'] as String?,
      annotations: json['annotations'] as String?,
    );
  }
}

/// Schrijft en leest autosave-herstelbestanden. Elk dirty tabblad krijgt een
/// eigen `<id>.json` in de herstelmap; bij opslaan/sluiten wordt het gewist,
/// zodat resterende bestanden bij de volgende start op niet-opgeslagen werk
/// (een crash) wijzen.
class RecoveryService {
  /// Tests injecteren een tijdelijke map; in productie wordt de app-support-map
  /// gebruikt (path_provider).
  final Future<Directory> Function() _resolveDir;

  RecoveryService({Directory? baseDir})
    : _resolveDir = baseDir != null ? (() async => baseDir) : _defaultDir;

  /// #1953: een schrijffout naar de herstelmap mag niet stil blijven. De eerste
  /// fout in een sessie (of de eerste ná een geslaagde schrijfbeurt) meldt zich
  /// via deze callback aan de UI; daarna niet elke 25 s herhalen. Een geslaagde
  /// schrijfbeurt reset de vlag, zodat een volgende fout wélt meldt.
  void Function(Object error)? onWriteError;
  bool _lastWriteFailed = false;

  static Future<Directory> _defaultDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'recovery'));
  }

  Future<Directory> _dir() async {
    final dir = await _resolveDir();
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  File _file(Directory dir, String id) => File(p.join(dir.path, '$id.json'));

  /// Per-id operation chains. The periodic autosave tick (`save`) and the
  /// "tab became clean" listener (`discard`) fire independently for the same
  /// id; without ordering, a save that was already in flight could land *after*
  /// a discard and leave a stale recovery file that falsely prompts to restore
  /// already-saved work. Serialising per id makes the later call win.
  final Map<String, Future<void>> _chains = {};

  Future<void> _enqueue(String id, Future<void> Function() op) {
    final next = (_chains[id] ?? Future<void>.value()).then((_) => op());
    _chains[id] = next;
    next.whenComplete(() {
      if (_chains[id] == next) _chains.remove(id);
    });
    return next;
  }

  /// Op web is er geen app-supportmap (path_provider/dart:io ontbreken): elke
  /// operatie is daar een stille no-op in plaats van een logregen aan
  /// UnsupportedErrors uit de dart:io-stubs.
  static bool get _unavailable => kIsWeb;

  /// Of crashherstel op dit platform überhaupt bestaat.
  ///
  /// Vraag dit in plaats van zelf `kIsWeb` te toetsen: de reden dat een tabblad
  /// in de browser geen herstelkopie krijgt is dat déze dienst er niets kan, en
  /// wie dat elders naschrijft laat de twee vanzelf uit elkaar lopen. De UI
  /// meldt aan de hand hiervan eenmalig dat er in de browser niets terugkomt na
  /// een crash — stilzwijgen is daar een valstrik, want op desktop wérkt het.
  bool get available => !_unavailable;

  Future<void> save(RecoverySnapshot snapshot) {
    if (_unavailable) return Future.value();
    return _enqueue(snapshot.id, () async {
      try {
        final dir = await _dir();
        // Atomair: een crash midden in de autosave — precies het moment
        // waarvoor recovery bestaat — mag het vorige snapshot niet slopen.
        await writeStringAtomic(
          _file(dir, snapshot.id),
          jsonEncode(snapshot.toJson()),
        );
        _lastWriteFailed = false;
      } catch (e) {
        logWarning('RecoveryService.save: write recovery snapshot', e);
        // #1953: de eerste fout (of de eerste ná een geslaagde schrijfbeurt)
        // meldt zich één keer aan de UI; daarna niet elke 25 s herhalen.
        if (!_lastWriteFailed) {
          _lastWriteFailed = true;
          onWriteError?.call(e);
        }
        // Autosave mag nooit de app verstoren.
      }
    });
  }

  Future<void> discard(String id) {
    if (_unavailable) return Future.value();
    return _enqueue(id, () async {
      try {
        final file = _file(await _dir(), id);
        if (file.existsSync()) await file.delete();
      } catch (e) {
        logWarning('RecoveryService.discard: delete recovery file', e);
      }
    });
  }

  /// Recovery snapshots hold full deck markdown (and notes) in plaintext, so an
  /// orphaned one — left by a crash the user never followed up on — is a slow
  /// leak of possibly-classified content on disk. Cap how long that can
  /// linger: zeven dagen dekt "vorige week gecrasht, pas na het weekend weer
  /// geopend" ruim, zonder geclassificeerde restanten een maand te bewaren.
  static const Duration defaultMaxAge = Duration(days: 7);

  /// Wis álle herstelbestanden, ongeacht leeftijd (knop in Instellingen →
  /// Privacy). Best-effort; geeft het aantal verwijderde bestanden terug.
  Future<int> discardAll() => pruneOlderThan(Duration.zero);

  /// Wanneer er voor het laatst tijdens deze sessie is opgeruimd.
  DateTime? _lastPrune;

  /// Hoe vaak er tijdens het draaien wordt opgeruimd.
  ///
  /// Ruim genoeg dat het niets kost, vaak genoeg dat [defaultMaxAge] ook een
  /// grens is voor een machine die weken aan blijft staan.
  static const pruneInterval = Duration(hours: 1);

  /// Ruim verlopen herstelbestanden op terwijl de app draait.
  ///
  /// Zonder dit gold de houdbaarheid alleen bij het opstarten: wie zijn laptop
  /// niet afsluit, hield een momentopname van een crash van vorige maand op
  /// schijf, want alleen [loadAll] veegde. Een bewaartermijn die je pas
  /// handhaaft bij de volgende start, is geen bewaartermijn.
  ///
  /// Zelf-beperkend op [pruneInterval], zodat de autosave-tik hem elke 25
  /// seconden mag aanroepen zonder de map elke keer te doorlopen.
  Future<void> pruneIfDue() async {
    if (_unavailable) return;
    final last = _lastPrune;
    final now = DateTime.now();
    if (last != null && now.difference(last) < pruneInterval) return;
    _lastPrune = now;
    await pruneOlderThan(defaultMaxAge);
  }

  /// Delete recovery files last modified more than [maxAge] ago. Best-effort:
  /// failures are logged, never thrown. Returns the number of files removed.
  Future<int> pruneOlderThan(Duration maxAge) async {
    if (_unavailable) return 0;
    var removed = 0;
    try {
      final dir = await _dir();
      final now = DateTime.now();
      for (final entry in dir.listSync()) {
        // Een `.tmp` is het restant van een atomaire write die een crash niet
        // haalde; net zo goed plaintext-residu, dus dezelfde houdbaarheid. De
        // naam draagt sinds kort een teller (`.json.3.tmp`), dus matchen op het
        // achtervoegsel alleen.
        if (entry is! File ||
            !(entry.path.endsWith('.json') || entry.path.endsWith('.tmp'))) {
          continue;
        }
        try {
          final age = now.difference(entry.statSync().modified);
          if (age > maxAge) {
            await entry.delete();
            removed++;
          }
        } catch (e) {
          logWarning('RecoveryService.pruneOlderThan: stat/delete', e);
        }
      }
    } catch (e) {
      logWarning('RecoveryService.pruneOlderThan: list recovery dir', e);
    }
    return removed;
  }

  Future<List<RecoverySnapshot>> loadAll() async {
    if (_unavailable) return const [];
    // Bound plaintext residue: drop stale orphans before offering the rest.
    await pruneOlderThan(defaultMaxAge);
    try {
      final dir = await _dir();
      final out = <RecoverySnapshot>[];
      for (final entry in dir.listSync()) {
        if (entry is File && entry.path.endsWith('.json')) {
          try {
            final data = jsonDecodeGuarded(await entry.readAsString());
            if (data is! Map) {
              throw const FormatException('Recovery snapshot is not a map');
            }
            out.add(RecoverySnapshot.fromJson(Map<String, Object?>.from(data)));
          } catch (e, s) {
            logError('RecoveryService.loadAll: decode recovery snapshot', e, s);
          }
        }
      }
      out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return out;
    } catch (e, s) {
      // Opstart-veilige fallback: een StackOverflowError ontsnapt aan de
      // per-file try/catch (het is een Error, geen Exception) en kan de app
      // laten crashen vóór de UI op staat. De recovery-map hernoemen naar een
      // backup — niet verwijderen, de gebruiker wil misschien iets terughalen —
      // en normaal opstarten met een lege lijst. Recovery is een
      // gemaksfunctie, geen voorwaarde om te kunnen werken.
      logError(
        'RecoveryService.loadAll: fatal — quarantining recovery dir',
        e,
        s,
      );
      try {
        final dir = await _dir();
        final backup = Directory(
          '${dir.path}-corrupt-${DateTime.now().millisecondsSinceEpoch}',
        );
        await dir.rename(backup.path);
        logWarning(
          'RecoveryService.loadAll: recovery map hernoemd naar ${backup.path}',
        );
      } catch (e2) {
        logWarning(
          'RecoveryService.loadAll: kon recovery map niet hernoemen',
          e2,
        );
      }
      return const [];
    }
  }

  /// Wis precies deze herstelbestanden, op sleutel.
  ///
  /// De aanroeper wéét welke van hem zijn — de tabbladen van dit venster, of de
  /// momentopnames die zojuist in de herstelvraag zijn getoond — en zegt dat
  /// hier. Dat is het verschil met [clearAll], dat de hele map leegde: draaide
  /// er een tweede venster, dan gooide een nette afsluiting van het ene de
  /// crashbescherming van het andere weg. Zonder melding, en pas merkbaar
  /// wanneer dat andere venster daarna alsnog vastliep.
  Future<void> discardEach(Iterable<String> ids) async {
    if (_unavailable) return;
    for (final id in ids) {
      await discard(id);
    }
  }

  /// Wis élk herstelbestand in de map, van welk venster ook. Alleen voor de
  /// uitdrukkelijke opruimknop in Instellingen → Privacy; een venster dat
  /// afsluit hoort [discardEach] te gebruiken.
  Future<void> clearAll() async {
    if (_unavailable) return;
    try {
      final dir = await _dir();
      for (final entry in dir.listSync()) {
        if (entry is File &&
            (entry.path.endsWith('.json') || entry.path.endsWith('.tmp'))) {
          try {
            await entry.delete();
          } catch (e) {
            logWarning('RecoveryService.clearAll: delete recovery file', e);
          }
        }
      }
    } catch (e) {
      logWarning('RecoveryService.clearAll: list recovery dir', e);
    }
  }
}

final recoveryServiceProvider = Provider<RecoveryService>(
  (_) => RecoveryService(),
);
