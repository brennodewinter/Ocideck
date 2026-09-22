import 'dart:async';

import 'package:flutter/widgets.dart';

/// Een [Image] die na een mislukte lading zichzelf opnieuw probeert.
///
/// Dia-afbeeldingen falen soms transiënt: een sync-map (iCloud, OneDrive,
/// Nextcloud) schrijft het bestand net opnieuw, een netwerkschijf hikt, of het
/// bestand arriveert pas nadat de dia al staat. Zonder retry toont de dia de
/// placeholder tot de gebruiker heen-en-weer navigeert — in de presentatiemodus
/// bleef de presentator dan naar een grijs vlak kijken terwijl de beamer het
/// beeld al had (#2159).
///
/// Bij elke fout wordt de provider-key uit de image-cache gegooid en na een
/// korte pauze opnieuw opgebouwd. Een blijvende fout (weggegooid of corrupt
/// bestand) blijft de placeholder tonen; een transiënte fout herstelt vanzelf.
/// De pauze groeit van [firstRetry] naar [retryInterval] zodat de eerste hik
/// vrijwel onzichtbaar is en een aanhoudende fout niet elke frame probeert.
class RetryingImage extends StatefulWidget {
  const RetryingImage({
    super.key,
    required this.image,
    this.fit,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.semanticLabel,
    this.gaplessPlayback = false,
    this.filterQuality = FilterQuality.low,
    this.errorBuilder,
  });

  final ImageProvider image;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final double? width;
  final double? height;
  final String? semanticLabel;
  final bool gaplessPlayback;
  final FilterQuality filterQuality;
  final ImageErrorWidgetBuilder? errorBuilder;

  /// Eerste nieuwe poging na een fout; daarna [retryInterval].
  static const Duration firstRetry = Duration(milliseconds: 250);

  /// Pauze tussen latere pogingen — traag genoeg dat een permanent
  /// ontbrekend bestand slechts één mislukte lezing per seconde kost.
  static const Duration retryInterval = Duration(seconds: 1);

  @override
  State<RetryingImage> createState() => _RetryingImageState();
}

class _RetryingImageState extends State<RetryingImage> {
  /// Verandert bij elke poging, zodat de [Image] opnieuw mount en resolve.
  int _attempt = 0;
  Timer? _retry;

  @override
  void didUpdateWidget(RetryingImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _retry?.cancel();
      _retry = null;
      _attempt = 0;
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  Future<void> _retryNow() async {
    _retry = null;
    // De mislukte lading uit de cache gooien voordat de nieuwe resolve
    // dezelfde key pakt — anders komt de vorige fout meteen terug.
    await widget.image.evict();
    if (!mounted) {
      return;
    }
    setState(() => _attempt++);
  }

  void _scheduleRetry() {
    _retry ??= Timer(
      _attempt == 0 ? RetryingImage.firstRetry : RetryingImage.retryInterval,
      _retryNow,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Image(
      key: ValueKey<int>(_attempt),
      image: widget.image,
      fit: widget.fit,
      alignment: widget.alignment,
      width: widget.width,
      height: widget.height,
      semanticLabel: widget.semanticLabel,
      gaplessPlayback: widget.gaplessPlayback,
      filterQuality: widget.filterQuality,
      errorBuilder: (context, error, stackTrace) {
        _scheduleRetry();
        return widget.errorBuilder?.call(context, error, stackTrace) ??
            const SizedBox.shrink();
      },
    );
  }
}
