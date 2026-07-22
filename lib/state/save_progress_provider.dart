import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Waar het opslaan naartoe schrijft dat nu bezig is.
///
/// Het onderscheid zit erin omdat de wachttijd erdoor verklaard wordt. Lokaal
/// opslaan duurt een oogwenk; een WebDAV- of S3-opslag met platte media is één
/// upload per bestand, en een git-commit is drie tot zeven round-trips. "Bezig
/// met opslaan" zonder te zeggen waarheen laat de gebruiker raden of het aan
/// zijn schijf of aan zijn verbinding ligt.
enum SaveTarget { local, webdav, s3, git }

/// De opslag die op dit moment loopt, of `null` als er niets loopt.
///
/// Bestaat omdat opslaan naar een server tot dusver niets liet zien. Bladeren
/// had een spinner, de export een voortgangsbalk, maar de opslag zelf — de
/// handeling waar het werk van de gebruiker in zit — deed er tientallen seconden
/// het zwijgen toe. Op een trage verbinding is dat niet te onderscheiden van een
/// vastgelopen app, en dus klikt iemand nog eens, en nog eens.
///
/// App-breed en niet per tabblad: er is één gebruiker met één paar ogen, en de
/// balk die dit toont hoort bij het actieve tabblad. Een tweede opslag die
/// tegelijk zou lopen is precies wat we willen zien, niet verbergen.
final saveProgressProvider = StateProvider<SaveTarget?>((ref) => null);

/// Voer [body] uit met [target] zichtbaar in de statusbalk, en zet de melding
/// daarna altijd weer uit — ook als [body] gooit. Een vlag die blijft hangen na
/// een mislukte opslag is erger dan geen vlag: dan meldt de balk voor altijd
/// werk dat allang gestrand is.
Future<T> withSaveProgress<T>(
  WidgetRef ref,
  SaveTarget target,
  Future<T> Function() body,
) async {
  ref.read(saveProgressProvider.notifier).state = target;
  try {
    return await body();
  } finally {
    ref.read(saveProgressProvider.notifier).state = null;
  }
}
