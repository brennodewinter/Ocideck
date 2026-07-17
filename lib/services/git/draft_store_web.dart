import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/git_settings.dart';
import '../../utils/log.dart';
import 'draft_store.dart';

/// De werkkopie op web: de sleutel/waarde-opslag van de browser.
///
/// §8.3 wilde hier eerst een IndexedDB-concept. Dat was het zwaarste mechanisme
/// kiezen zonder naar de lading te kijken, want **een deck-werkkopie is tekst,
/// alles ervan**: `deck.md` is markdown, en `AnnotationCodec.encode` en
/// `UserNotesCodec.encode` geven allebei een `String` (JSON). Er is geen binair
/// lid. Een objectdatabase om markdown te bewaren is niet gratis: via interop
/// zou hij bovendien het enige ongeteste stuk van dit backend zijn geweest, want
/// deze repo draait élke test op de VM en heeft geen browser-target.
/// `shared_preferences` heeft dat probleem niet — die wordt hier al overal
/// gemockt.
///
/// Assetbytes horen hier niet: een gepoolde asset staat op de forge, en een nog
/// niet gepushte nieuwe afbeelding leeft in de `WebAssetStore`, die al expliciet
/// vluchtig is. Deze store erft die beperking, hij voegt er geen toe — en is nog
/// altijd beter dan vandaag, waar op web niets een herlaad overleeft.
DraftStore createDraftStore() => PrefsDraftStore();

class PrefsDraftStore implements DraftStore {
  PrefsDraftStore({SharedPreferences? prefs}) : _injected = prefs;

  final SharedPreferences? _injected;
  SharedPreferences? _cached;

  static const String _prefix = 'git_draft::';

  /// Cap per deck. De browser geeft grofweg 5 MB per origin, gedeeld met álle
  /// andere instellingen — vandaar ruim eronder. Een `deck.md` van deze orde
  /// bestaat in de praktijk niet; `FileService.maxDeckMarkdownBytes` (32 MiB) is
  /// een grens tegen vijandige invoer, geen maat voor een presentatie. Wie er
  /// tóch overheen gaat krijgt een eerlijke melding in plaats van een stille
  /// afkap.
  static const int maxDraftBytes = 2 * 1024 * 1024;

  @override
  bool get isDurable => true;

  Future<SharedPreferences> _prefs() async =>
      _injected ?? (_cached ??= await SharedPreferences.getInstance());

  String _keyFor(String deckDir) => '$_prefix$deckDir';

  @override
  Future<void> writeDeck(String deckDir, Map<String, Uint8List> files) async {
    // De aanname "alles is tekst" wordt hier gecontroleerd in plaats van
    // aangenomen. Komt er ooit een binair lid bij, dan zegt deze fout dat — in
    // plaats van dat het stil als kapotte UTF-8 wordt weggeschreven.
    final text = <String, String>{};
    for (final entry in files.entries) {
      try {
        text[entry.key] = utf8.decode(entry.value);
      } on FormatException {
        throw DraftStoreUnsupported(
          'Dit lid is geen tekst en past niet in de webwerkkopie: ${entry.key}',
        );
      }
    }

    final encoded = jsonEncode(text);
    final size = utf8.encode(encoded).length;
    if (size > maxDraftBytes) {
      throw DraftStoreUnsupported(
        'Deze presentatie is te groot voor de webversie ($size bytes). '
        'Gebruik de desktopversie.',
      );
    }
    await (await _prefs()).setString(_keyFor(deckDir), encoded);
  }

  @override
  Future<Map<String, Uint8List>> readDeck(String deckDir) async {
    final raw = (await _prefs()).getString(_keyFor(deckDir));
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      return {
        for (final entry in decoded.entries)
          entry.key: Uint8List.fromList(utf8.encode(entry.value! as String)),
      };
    } catch (e) {
      // Een onleesbaar concept is geen reden om te gooien: de aanroeper ziet een
      // leeg deck en haalt het opnieuw uit de repo. Wel loggen — dit hoort niet
      // te kunnen.
      logError('PrefsDraftStore: concept onleesbaar ($deckDir)', e);
      return {};
    }
  }

  @override
  Future<bool> hasDeck(String deckDir) async =>
      (await _prefs()).containsKey(_keyFor(deckDir));

  @override
  Future<void> discardDeck(String deckDir) async {
    // Wist alléén deze sleutel, nooit het hele domein: hier staan ook de
    // instellingen van de gebruiker.
    await (await _prefs()).remove(_keyFor(deckDir));
  }

  @override
  Future<List<String>> deckDirs() async {
    final prefs = await _prefs();
    final dirs = <String>[
      for (final key in prefs.getKeys())
        if (key.startsWith(_prefix)) key.substring(_prefix.length),
    ]..sort();
    // Alleen wat de layout volgt: een sleutel die iets anders is geworden is
    // geen deck.
    return dirs.where((d) => GitRepoLayout.deckNameOf(d) != null).toList();
  }
}
