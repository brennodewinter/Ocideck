import '../../models/deck.dart';
import '../../models/privacy_disposition.dart';
import '../../models/slide.dart';
import 'privacy_own_identity.dart';
import 'privacy_projection.dart';

/// De projectie van één dia, voor de auteur zelf.
///
/// Redactie was tot nu toe onzichtbaar tot ná verzending. Het label in de
/// editor belooft "weglaten uit tonen en exporteren", maar het scherm veranderde
/// niets: de preview toont het rauwe deck, en de projectie draaide alleen bij
/// presenteren en exporteren. Pas in de PDF zag iemand of het klopte — en dan is
/// het bestand er al.
///
/// Vandaar deze functie. Hij projecteert **één** dia in plaats van het hele
/// deck, en dat is met opzet: de projectie scant zelf, en het hele deck scannen
/// bij elke toetsaanslag in de editor ernaast zou de preview onbruikbaar traag
/// maken. Voor wat de preview toont maakt het niets uit — de scanner escaleert
/// binnen een dia, niet eroverheen, en de deckvelden (titel, auteur) staan niet
/// op de dia.
///
/// [deck] gaat mee omdat de effectieve stand van de dia van het deck erft
/// ([effectivePrivacyDisposition]) en het thema en de projectmap uit het deck
/// komen. De bron blijft onaangeroerd; deze functie geeft een kopie.
Slide audiencePreviewSlide(
  Deck deck,
  Slide slide, {
  Set<String> disabledRules = const {},
  OwnIdentity ownIdentity = OwnIdentity.empty,
}) {
  final projected = PrivacyProjection.forAudience(
    deck.copyWith(slides: [slide]),
    disabledRules: disabledRules,
    ownIdentity: ownIdentity,
  );
  return projected.slides.first;
}

/// Of deze dia bij tonen en exporteren wordt weggelakt.
///
/// De stand van de dia wint van die van het deck (anders dan bij TLP, waar de
/// strengste wint) — zie [effectivePrivacyDisposition].
bool slideIsRedacted(Deck deck, Slide slide) =>
    effectivePrivacyDisposition(deck: deck.privacy, slide: slide.privacy) ==
    PrivacyDisposition.redact;
