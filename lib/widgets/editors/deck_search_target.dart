import 'package:flutter/widgets.dart';

import '../../utils/deck_text_search.dart';

/// De tijdelijke zoekselectie hoort bij deze werkruimte, niet bij het bestand.
class DeckSearchTarget extends InheritedWidget {
  const DeckSearchTarget({
    super.key,
    required this.match,
    required this.signal,
    required super.child,
  });

  final DeckTextMatch? match;
  final int signal;

  static DeckSearchTarget? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DeckSearchTarget>();

  bool matches(String? fieldId) => match != null && match!.fieldId == fieldId;

  @override
  bool updateShouldNotify(DeckSearchTarget oldWidget) =>
      signal != oldWidget.signal || match != oldWidget.match;
}

/// Ook formulier- en keuzegerichte editors geven het tekstveld een vaste naam.
class SearchFieldAnchor extends InheritedWidget {
  const SearchFieldAnchor({
    super.key,
    required this.fieldId,
    required super.child,
  });

  final String? fieldId;

  static String? fieldOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SearchFieldAnchor>()?.fieldId;

  @override
  bool updateShouldNotify(SearchFieldAnchor oldWidget) =>
      fieldId != oldWidget.fieldId;
}
