import 'page_size.dart';

/// De breedte/hoogte-verhouding waarin een dia is ontworpen.
///
/// Twee families bestaan naast elkaar:
///
/// - **Scherm** — de vaste 16:9 van beamer en laptopscherm. Een deck zonder
///   aanduiding is dit; zo rendert elk bestaand en handgeschreven Marp-deck
///   al sinds het begin.
/// - **Papier** — een ISO/DIN-vel uit [PageSizeSpec], staand of liggend, voor
///   presentaties die ook als document moeten kunnen doorleven (hand-outs,
///   exporters naar PDF/Pandoc). De keuze reist mee in de front matter als
///   `papersize:`/`geometry:` — hetzelfde vocabulaire dat Pandoc al kent
///   (`document_page_setup.dart`), dus een andere tool ziet een logische
///   paginamaat in plaats van een OciDeck-eigen sleutel.
///
/// Alles dat een dia tekent, meet of exporteert rekent met dit getal en niet
/// met een eigen `9 / 16`: een staand vel verandert de verhouding, en een
/// ergens vergeten factor zou inhoud laten afsnijden zonder dat iemand het
/// aan de uitkomst ziet.
const double kScreenSlideAspect = 16 / 9;

/// De logische breedte waarop dia-inhoud is geijkt. Alle metrieken
/// (lettergroottes, marges, pasruimte) zijn fracties hiervan, dus de hoogte
/// volgt altijd via [slideAspectRatio] — nooit als eigen constante.
const double kSlideDesignWidth = 1280.0;

/// De diaverhouding (breedte/hoogte) van [slideSize]: de schermstandaard voor
/// `null`, anders de verhouding van het gekozen vel.
double slideAspectRatio(PageSizeSpec? slideSize) {
  final size = slideSize;
  if (size == null) return kScreenSlideAspect;
  final (w, h) = size.dimensions;
  return w / h;
}

/// De logische diahoogte in ontwerp-pixels voor [slideSize] bij de vaste
/// ontwerpbreedte [kSlideDesignWidth]: `720` bij 16:9, meer bij een staand vel.
/// Gebruikt waar een fractie van de diahoogte als pixels nodig is
/// (merkstrook, exportbudget).
double slideDesignHeight(PageSizeSpec? slideSize) =>
    kSlideDesignWidth / slideAspectRatio(slideSize);

/// De Marp `@size`-regel voor een papierformaat, zodat `marp deck.md` dezelfde
/// diaverhouding toont als OciDeck; `null` schrijft niets — dan geldt de
/// Marp-standaard.
String marpSizeDirective(PageSizeSpec? slideSize) {
  if (slideSize == null) return '';
  final (w, h) = slideSize.dimensions;
  return '\n@size ${w.toStringAsFixed(0)}mm ${h.toStringAsFixed(0)}mm;\n';
}
