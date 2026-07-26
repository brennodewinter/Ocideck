import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:ocideck/utils/display_path.dart';

void main() {
  test('displayFolder zet paden onder de thuismap af tegen haar anker', () {
    expect(
      displayFolder(
        '/home/u/Pres/OciDeck/Demo (2)/Demo.md',
        homeDir: '/home/u/Pres/OciDeck',
      ),
      'OciDeck › Demo (2)',
    );
    expect(
      displayFolder(
        '/home/u/Pres/OciDeck/Demo.md',
        homeDir: '/home/u/Pres/OciDeck',
      ),
      'OciDeck',
    );
  });

  test('displayFolder kort de OS-thuismap af tot ~', () {
    expect(
      displayFolder('/Users/u/Docs/deck.md', osHome: '/Users/u'),
      p.normalize('~/Docs'),
    );
    expect(displayFolder('/Users/u/deck.md', osHome: '/Users/u'), '~');
  });

  test('displayFolder valt terug op het volledige mappad', () {
    expect(displayFolder('/srv/decks/deck.md'), p.normalize('/srv/decks'));
  });

  test('de presentatie-thuismap gaat vóór de OS-thuismap', () {
    expect(
      displayFolder(
        '/Users/u/Pres/deck.md',
        homeDir: '/Users/u/Pres',
        osHome: '/Users/u',
      ),
      'Pres',
    );
  });

  test('een lege of witruimte-thuismap wordt genegeerd', () {
    expect(
      displayFolder('/srv/decks/deck.md', homeDir: '  '),
      p.normalize('/srv/decks'),
    );
    expect(
      displayFolder('/srv/decks/deck.md', osHome: ''),
      p.normalize('/srv/decks'),
    );
  });
}
