/// Wie gebruikt deze afbeelding, en hoe zet je die verwijzingen in één keer om.
///
/// De afbeeldingenbibliotheek stelt die twee vragen vóór ze iets onomkeerbaars
/// doet: "0 dia's gebruiken dit" is het antwoord waarop iemand een bestand
/// weggooit, en na het opruimen van een md5-duplicaat moeten de dia's naar het
/// behouden bestand wijzen. Beide vragen werden op twee plekken los
/// uitgeschreven — in de shell en vanuit een editorveld — en beide keken alleen
/// naar de afbeeldingsvelden. Een afbeelding die enkel in de vrije tekst stond,
/// telde dus niet als gebruiker en werd na het ontdubbelen niet meegenomen.
///
/// Hier staat het één keer. Wat de twee plekken écht onderscheidt is hóé een
/// pad wordt opgelost — met of zonder insluitingswacht — en dát komt er als
/// functie in.
library;

import '../models/deck.dart';
import '../models/slide.dart';
import 'slide_image_refs.dart';

/// Lost een verwijzing zoals die op de dia staat op naar een genormaliseerd
/// absoluut pad, of `null` wanneer dat niet kan of niet mag.
typedef ImagePathResolver = String? Function(String path);

/// De indexen van de dia's in [deck] die [target] (een genormaliseerd absoluut
/// pad) gebruiken, in diavolgorde.
///
/// Élke verwijzing telt mee — de afbeeldingsvelden én een `![…](…)` in de vrije
/// tekst. Een dia die de afbeelding twee keer aanhaalt staat er één keer in: de
/// vraag is welke dia's het treft, niet hoe vaak.
List<int> slideIndexesUsingImage(
  Deck deck,
  String target,
  ImagePathResolver resolve,
) => [
  for (var i = 0; i < deck.slides.length; i++)
    if (slideImagePaths(deck.slides[i]).any((p) => resolve(p) == target)) i,
];

/// [slide] met elke verwijzing die via [resolve] op [target] uitkomt vervangen
/// door wat [replacement] van dat pad maakt.
///
/// Geeft dezelfde dia terug wanneer er niets te vervangen valt, zodat de
/// aanroeper met `identical` kan zien of er werkelijk iets veranderde en geen
/// lege bewerking in de ongedaan-stapel zet.
Slide slideWithImageReplaced(
  Slide slide,
  String target,
  ImagePathResolver resolve,
  String Function(String path) replacement,
) => rewriteSlideImagePaths(
  slide,
  (path) => resolve(path) == target ? replacement(path) : null,
);
