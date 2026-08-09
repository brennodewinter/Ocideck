import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../models/marp_style.dart';
import '../../../utils/marp_style_values.dart';

class MarpFilteredImage extends StatelessWidget {
  final List<String> filters;
  final Widget child;

  const MarpFilteredImage({
    super.key,
    required this.filters,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    Widget result = child;
    final renderedCount = math.min(
      filters.length,
      kMaxRenderedMarpImageFilters,
    );
    for (var i = renderedCount - 1; i >= 0; i--) {
      final raw = filters[i];
      final parts = raw.toLowerCase().split(':');
      final name = parts.first;
      final value = parts.length > 1 ? _marpFilterAmount(parts[1]) : null;
      result = switch (name) {
        'blur' => ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: value ?? 5,
            sigmaY: value ?? 5,
          ),
          child: result,
        ),
        'brightness' => ColorFiltered(
          colorFilter: ColorFilter.matrix(_brightnessMatrix(value ?? 1)),
          child: result,
        ),
        'saturate' => ColorFiltered(
          colorFilter: ColorFilter.matrix(_saturationMatrix(value ?? 1)),
          child: result,
        ),
        'grayscale' => ColorFiltered(
          colorFilter: ColorFilter.matrix(_saturationMatrix(0)),
          child: result,
        ),
        'sepia' => ColorFiltered(
          colorFilter: const ColorFilter.matrix(_sepiaMatrix),
          child: result,
        ),
        'invert' => ColorFiltered(
          colorFilter: const ColorFilter.matrix(_invertMatrix),
          child: result,
        ),
        _ => result,
      };
    }
    return result;
  }
}

double? _marpFilterAmount(String source) => double.tryParse(
  RegExp(r'^[-+]?(?:\d+\.?\d*|\.\d+)').firstMatch(source)?.group(0) ?? '',
);

List<double> _brightnessMatrix(double value) => <double>[
  value,
  0,
  0,
  0,
  0,
  0,
  value,
  0,
  0,
  0,
  0,
  0,
  value,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];

List<double> _saturationMatrix(double value) {
  const red = 0.213;
  const green = 0.715;
  const blue = 0.072;
  final inverse = 1 - value;
  return <double>[
    inverse * red + value,
    inverse * green,
    inverse * blue,
    0,
    0,
    inverse * red,
    inverse * green + value,
    inverse * blue,
    0,
    0,
    inverse * red,
    inverse * green,
    inverse * blue + value,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

const _sepiaMatrix = <double>[
  .393,
  .769,
  .189,
  0,
  0,
  .349,
  .686,
  .168,
  0,
  0,
  .272,
  .534,
  .131,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];

const _invertMatrix = <double>[
  -1,
  0,
  0,
  0,
  255,
  0,
  -1,
  0,
  0,
  255,
  0,
  0,
  -1,
  0,
  255,
  0,
  0,
  0,
  1,
  0,
];

/// Geeft de link-tap-handler door aan alle tekst in een slide, zonder die door
/// elke sub-widget heen te hoeven sleuren. Draagt ook of er een TLP-markering
/// rechtsonder staat, zodat bijschriften daarboven uitwijken.
class SlideLinkScope extends InheritedWidget {
  final void Function(String url)? onTapLink;
  final bool hasBottomTlp;

  /// Of online media (URL-afbeeldingen/-video's en embeds) live geladen mag
  /// worden. Standaard uit; de media-renderers tonen anders een placeholder met
  /// de URL i.p.v. naar buiten te bellen.
  final bool allowRemoteMedia;

  /// Of de media op deze slide door de privacyprojectie is weggehaald.
  ///
  /// Reist mee in de scope en niet als parameter langs de renderers, omdat het
  /// anders precies dáár misgaat waar het al eens misging: er zijn negen
  /// aanroepplekken van `_resolvedImage`, en een tiende die de vlag vergeet
  /// levert stilzwijgend weer een grijs "Afbeelding"-vak op een geredigeerde
  /// slide. Zie `Slide.mediaRedacted`.
  final bool mediaRedacted;

  /// Bovengrens voor de decodeerresolutie van een dia-afbeelding, of null voor
  /// de gewone cap.
  ///
  /// Reist mee in de scope om precies de reden die hierboven bij
  /// [mediaRedacted] staat: er zijn negen aanroepplekken van `_resolvedImage`,
  /// en een tiende die de parameter vergeet decodeert stilzwijgend weer op
  /// volle resolutie.
  ///
  /// Alleen de slidestrook zet hem. Een telefoonfoto van 4032×3024 kost
  /// gedecodeerd bijna 49 MiB; tien zichtbare thumbnails met verschillende
  /// foto's zijn een halve gigabyte aan levende bitmaps voor een strook van
  /// ~180 px breed. Op desktop is dat een geheugengrafiek die niemand ziet, op
  /// web valt de tab om — en web is de demo-route (#612).
  final int? decodeMaxEdge;
  final MarpStyle marpStyle;

  /// Wat er gebeurt als de gebruiker vanaf een geblokkeerde-online-media-
  /// placeholder online media wil aanzetten: een sprong naar de instelling.
  /// Alleen de editor-preview zet dit; in de presenter, thumbnails, export en de
  /// play-only-webdemo is het null en verschijnt er geen knop — daar zijn de
  /// instellingen niet te openen (#852).
  final VoidCallback? onEnableOnlineMedia;

  const SlideLinkScope({
    super.key,
    required this.onTapLink,
    this.hasBottomTlp = false,
    this.allowRemoteMedia = false,
    this.mediaRedacted = false,
    this.decodeMaxEdge,
    this.marpStyle = const MarpStyle(),
    this.onEnableOnlineMedia,
    required super.child,
  });

  static void Function(String url)? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SlideLinkScope>()?.onTapLink;

  static bool hasBottomTlpOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SlideLinkScope>()
          ?.hasBottomTlp ??
      false;

  static bool allowRemoteMediaOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SlideLinkScope>()
          ?.allowRemoteMedia ??
      false;

  static bool mediaRedactedOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SlideLinkScope>()
          ?.mediaRedacted ??
      false;

  static int? decodeMaxEdgeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SlideLinkScope>()
      ?.decodeMaxEdge;

  static MarpStyle marpStyleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SlideLinkScope>()?.marpStyle ??
      const MarpStyle();

  static VoidCallback? onEnableOnlineMediaOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SlideLinkScope>()
      ?.onEnableOnlineMedia;

  @override
  bool updateShouldNotify(SlideLinkScope oldWidget) =>
      oldWidget.onTapLink != onTapLink ||
      oldWidget.hasBottomTlp != hasBottomTlp ||
      oldWidget.allowRemoteMedia != allowRemoteMedia ||
      oldWidget.mediaRedacted != mediaRedacted ||
      oldWidget.decodeMaxEdge != decodeMaxEdge ||
      oldWidget.marpStyle != marpStyle ||
      oldWidget.onEnableOnlineMedia != onEnableOnlineMedia;
}
