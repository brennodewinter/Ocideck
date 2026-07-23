import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/app_shell.dart';

/// De bestemmingsdialoog verschijnt niet altijd, en dat is de reparatie uit
/// #646: zonder ingerichte bibliotheek heeft hij geen enkele optie te tonen.
///
/// De melding sprak van "drie dialogen diep om een bestand op te slaan". Dat
/// klopte, maar alleen op het pad waar iedereen begint — bij een eerste start
/// is er nog geen bibliotheek, dus zag elke nieuwe gebruiker een lege lijst met
/// twee knoppen die allebei naar hetzelfde systeemvenster leidden.
///
/// De dialoog zelf is blijven staan: mét bibliotheken kies je er één en zie je
/// vooraf waar de presentatie, afbeeldingen en media landen. Dat is precies het
/// verschil dat deze toetsen vasthouden.
void main() {
  group('shouldAskDestination', () {
    test('met bibliotheken valt er iets te kiezen', () {
      expect(
        shouldAskDestination(
          isNewDeck: true,
          supportsFolders: true,
          hasLibraries: true,
        ),
        isTrue,
      );
    });

    test('zonder bibliotheken niet — dit is de reparatie', () {
      expect(
        shouldAskDestination(
          isNewDeck: true,
          supportsFolders: true,
          hasLibraries: false,
        ),
        isFalse,
      );
    });

    test('een bestaand deck heeft al een plek', () {
      expect(
        shouldAskDestination(
          isNewDeck: false,
          supportsFolders: true,
          hasLibraries: true,
        ),
        isFalse,
      );
    });

    test('op het web is opslaan een download, geen mapkeuze', () {
      expect(
        shouldAskDestination(
          isNewDeck: true,
          supportsFolders: false,
          hasLibraries: true,
        ),
        isFalse,
      );
    });
  });
}
