import '../../models/deck.dart';
import '../../models/slide.dart';

typedef PrivacyMarpFragment = ({
  String field,
  int index,
  String text,
  String context,
});

/// De privacygevoelige Marp-velden in de documentmetadata.
Iterable<PrivacyMarpFragment> deckMarpPrivacyFragments(Deck deck) sync* {
  yield (
    field: 'marpHeader',
    index: 0,
    text: deck.marpStyle.header,
    context: '',
  );
  yield (
    field: 'marpFooter',
    index: 0,
    text: deck.marpStyle.footer,
    context: '',
  );
  yield (
    field: 'marpBackgroundImage',
    index: 0,
    text: deck.marpStyle.backgroundImage,
    context: '',
  );
}

/// De privacygevoelige Marp-velden van één dia.
Iterable<PrivacyMarpFragment> slideMarpPrivacyFragments(Slide slide) sync* {
  yield (
    field: 'marpHeader',
    index: 0,
    text: slide.marpStyle.header,
    context: '',
  );
  yield (
    field: 'marpFooter',
    index: 0,
    text: slide.marpStyle.footer,
    context: '',
  );
  yield (
    field: 'marpBackgroundImage',
    index: 0,
    text: slide.marpStyle.backgroundImage,
    context: '',
  );
  for (var i = 0; i < slide.preservedMarpLines.length; i++) {
    yield (
      field: 'preservedMarpLines',
      index: i,
      text: slide.preservedMarpLines[i],
      context: '',
    );
  }
}
