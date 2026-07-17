import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'privacy_provider.dart';

/// Houdt de van het deck afgeleide ketens warm zolang het tabblad leeft.
///
/// Riverpod berekent een afgeleide provider pas als iemand hem leest. Leest
/// níémand hem, dan raakt hij bij een deckwijziging wel vuil maar staat er geen
/// verversing gepland — en dan valt die verversing op de eerste lezer die langs
/// komt. Is dat een widget die net gemonteerd wordt (een thumbnail die in beeld
/// scrolt, of een net gesplitste slide), dan gebeurt de flush middenin de build:
/// de vuile tussenstap wordt herbouwd, meldt dat aan de provider eronder, die
/// zichzelf ongeldig verklaart en de scope om een rebuild vraagt. Flutter staat
/// dat niet toe tijdens een build en gooit "setState() or markNeedsBuild()
/// called during build".
///
/// Deze abonnee is er alleen om dat te voorkomen: hij houdt de keten aangesloten,
/// zodat een deckwijziging netjes een verversing plant die vóór het frame draait
/// in plaats van erin. De selector geeft altijd `null` terug, dus de widget die
/// dit aanroept rebuildt er zelf nooit van.
///
/// De privacyketen is de langste (deck → ruwe scan → scan → meldingen) en de
/// enige waar de fout in het wild is gezien; de rest wordt sowieso door de
/// thumbnails gelezen. Verdwijnt de aanroep uit het tabblad, dan valt
/// `provider_warmup_test.dart` om.
void warmTabDerivedProviders(WidgetRef ref) {
  ref.watch(privacyQualityIssuesProvider.select((_) => null));
}
