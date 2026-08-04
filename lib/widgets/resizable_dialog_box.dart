import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Een breedte-aanpasbare vervanger voor de vaste `SizedBox(width:, height:)`
/// die veel dialogen rond hun inhoud leggen.
///
/// Lange bestandspaden in dialoogvensters werden afgekapt met "…" omdat de
/// breedte vast stond (#1211, #1217). Hier kan de gebruiker de breedte
/// aanpassen door de handgreep te slepen; de hoogte blijft vast, want de
/// inhoud (lijsten, breadcrumbs) schaalt zelf met de beschikbare ruimte.
///
/// De [builder] krijgt een [DialogResizeHandle] mee die de aanroeler plaatst
/// waar het past — in de footer naast de actieknoppen, of als laatste regel
/// van de inhoud. De handgreep is een extra voor pointer-gebruikers; de
/// kerninhoud blijft zonder muis volledig bedienbaar en schermlezer-
/// bereikbaar.
///
/// `minWidth` standaard 420 (ruim voor een pad plus icoon); `maxWidth` standaard
/// de schermbreedte minus 80 px marge.
class ResizableDialogBox extends StatefulWidget {
  final double initialWidth;
  final double height;
  final double minWidth;
  final double? maxWidth;

  /// Bouwt de inhoud van de box. De [DialogResizeHandle] is de sleephandgreep
  /// die de aanroeler in de dialoog plaatst (footer, laatste regel, …).
  final Widget Function(BuildContext context, DialogResizeHandle resizeHandle)
  builder;

  const ResizableDialogBox({
    super.key,
    required this.initialWidth,
    required this.height,
    required this.builder,
    this.minWidth = 420,
    this.maxWidth,
  });

  @override
  State<ResizableDialogBox> createState() => _ResizableDialogBoxState();
}

class _ResizableDialogBoxState extends State<ResizableDialogBox> {
  late double _width = widget.initialWidth;

  @override
  Widget build(BuildContext context) {
    final max = widget.maxWidth ?? MediaQuery.sizeOf(context).width - 80;
    final handle = DialogResizeHandle(onDrag: _growBy);
    return SizedBox(
      width: _width.clamp(widget.minWidth, max),
      height: widget.height,
      child: widget.builder(context, handle),
    );
  }

  void _growBy(double dx) {
    final max = widget.maxWidth ?? MediaQuery.sizeOf(context).width - 80;
    setState(() {
      _width = (_width + dx).clamp(widget.minWidth, max);
    });
  }

  @override
  void didUpdateWidget(covariant ResizableDialogBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialWidth != widget.initialWidth) {
      _width = widget.initialWidth;
    }
  }
}

/// Sleephandgreep die bij [ResizableDialogBox] hoort. Slepen naar rechts
/// verbreedt, naar links vernauwt. De tooltip en het Semantics-label zijn
/// gelokaliseerd ("Breedte aanpassen"). Haalt de vertaling zelf uit de
/// context, dus de aanroeler hoeft niets mee te geven.
class DialogResizeHandle extends StatelessWidget {
  final void Function(double dx) onDrag;

  const DialogResizeHandle({super.key, required this.onDrag});

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.d('Breedte aanpassen');
    return Semantics(
      label: label,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) => onDrag(details.delta.dx),
          child: Tooltip(
            message: label,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.drag_indicator,
                size: 18,
                color: AppTheme.slate400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
