import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../models/markdown_validation.dart';
import '../models/markdown_writing_suggestion.dart';
import '../models/marp_compatibility.dart';
import 'markdown_validator.dart';
import 'marp_compatibility.dart';

/// Invoer en uitvoer van [deckSourceChecks]. Eén [compatContext] `null` betekent
/// "de compatibiliteitscontrole staat uit" — hij kost dan ook niets.
typedef DeckCheckArgs = ({
  String source,
  MarpCompatContext? compatContext,
  bool deckScope,
});
typedef DeckCheckResult = ({
  MarkdownValidationResult validation,
  List<MarkdownWritingSuggestion> suggestions,
  MarpCompatReport? compat,
});

/// De debounced inspectieronde van de broneditor: validatie, schrijftips en —
/// wanneer de instelling aanstaat — de Marp-compatibiliteitscontrole.
///
/// Alledrie pure functies op de bronstring, zonder Flutter- of
/// BuildContext-afhankelijkheid, zodat [deckChecksRunner] de bundel native op
/// een achtergrond-isolate kan draaien: op een deck van honderdvijftig dia's
/// kostte deze serie ~42 ms op de UI-thread bij élke typ-pauze (#2713).
DeckCheckResult deckSourceChecks(DeckCheckArgs args) => (
  validation: MarkdownValidator().validate(args.source),
  suggestions: inspectMarkdownWriting(args.source),
  compat: args.compatContext == null
      ? null
      : MarpCompatibility().check(
          args.source,
          context: args.compatContext!,
          deckScope: args.deckScope,
        ),
);

/// Hoe de bundel draait. Native op een achtergrond-isolate, zodat de scans de
/// UI-thread niet blokkeren. Het web kent geen `Isolate.run` — het gooit daar
/// pas bij aanroep, ná de debounce (#2764) — en draait de bundel dus op de
/// main thread, zoals `ExportService._offload` het ook doet. Widgettests
/// vervangen de runner door een synchrone variant: een isolate-resultaat valt
/// niet binnen pump()-tijden.
var deckChecksRunner = (DeckCheckArgs args) => kIsWeb
    ? Future.sync(() => deckSourceChecks(args))
    : Isolate.run(() => deckSourceChecks(args));

/// Plant één debounced inspectieronde. Een ronde waarvan de bron onderweg is
/// gewijzigd — of waarvan de widget is verdwenen — levert niets af; [current]
/// bepaalt dat op de UI-isolate vlak vóór afgifte.
Timer scheduleDeckChecks({
  required DeckCheckArgs args,
  required bool Function() current,
  required void Function(DeckCheckResult) onResult,
}) {
  return Timer(const Duration(milliseconds: 350), () {
    unawaited(
      deckChecksRunner(args).then((bundle) {
        if (current()) onResult(bundle);
      }),
    );
  });
}
