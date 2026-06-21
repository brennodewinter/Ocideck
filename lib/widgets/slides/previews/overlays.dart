// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

class _LogoOverlay extends StatelessWidget {
  final String logoPath;
  final String? projectPath;
  final String position;
  final double size;

  const _LogoOverlay({
    required this.logoPath,
    required this.projectPath,
    required this.position,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final horizontalInset = size * 0.28;
    final topInset = size * 0.42;
    final bottomInset = size * 0.12;
    return Positioned(
      top: position.startsWith('top') ? topInset : null,
      bottom: position.startsWith('bottom') ? bottomInset : null,
      left: position.endsWith('left') ? horizontalInset : null,
      right: position.endsWith('right') ? horizontalInset : null,
      child: SizedBox(
        width: size,
        height: size,
        child: _resolvedImage(
          context,
          logoPath,
          projectPath,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

// ── TLP-markering: maten gedeeld door de badge en de footer-uitsparing ──────
const double _kTlpFont = 0.018; // × slidebreedte

const double _kTlpEdge = 0.025; // afstand tot de slidehoek (× breedte)

const double _kTlpHPad = 0.011;

const double _kTlpVPad = 0.005;

double _tlpBottomInset(double w) => w * 0.022;

/// Geschatte breedte van de TLP-badge, zodat de footer ervoor kan uitwijken.
double _tlpBadgeWidth(double w, TlpLevel tlp) =>
    tlp.label.length * w * _kTlpFont * 0.62 + 2 * (w * _kTlpHPad);

/// Verticale ruimte die een TLP-badge rechtsonder inneemt (voor bijschriften).
double _tlpVerticalReserve(double w) =>
    w * _kTlpFont + 2 * (w * _kTlpVPad) + _tlpBottomInset(w);

/// Hoogte van de classificatiebanner bovenaan de slide.
double _classificationBannerHeight(double w) => w * 0.038;

TextStyle _tlpMarkingTextStyle(double w, TlpLevel tlp, {double scale = 1}) =>
    TextStyle(
      color: Color(tlp.foreground),
      fontSize: w * _kTlpFont * scale,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
      height: 1.0,
    );

/// Volledige breedte bovenaan: de officiële TLP-markering als banner.
class _ClassificationBanner extends StatelessWidget {
  final TlpLevel tlp;
  final double w;

  const _ClassificationBanner({required this.tlp, required this.w});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: _classificationBannerHeight(w),
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            tlp.label,
            style: _tlpMarkingTextStyle(w, tlp, scale: 1.05),
          ),
        ),
      ),
    );
  }
}

/// Optioneel diagonaal watermerk over de slide-inhoud.
class _ClassificationWatermark extends StatelessWidget {
  final TlpLevel tlp;
  final double w;
  final String organization;

  const _ClassificationWatermark({
    required this.tlp,
    required this.w,
    this.organization = '',
  });

  String get _label {
    final org = organization.trim();
    return org.isEmpty ? tlp.label : '${tlp.label} · $org';
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Transform.rotate(
            angle: -0.35,
            child: Text(
              _label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(tlp.foreground).withValues(alpha: 0.12),
                fontSize: w * 0.105,
                fontWeight: FontWeight.w800,
                letterSpacing: w * 0.003,
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Officiële TLP 2.0-markering (FIRST): de gekleurde label op een zwart vlak,
/// rechtsonder. Wijkt uit naar linksonder als het logo rechtsonder staat.
class _TlpOverlay extends StatelessWidget {
  final TlpLevel tlp;
  final double w;
  final ThemeProfile profile;
  final bool hasLogo;

  const _TlpOverlay({
    required this.tlp,
    required this.w,
    required this.profile,
    required this.hasLogo,
  });

  @override
  Widget build(BuildContext context) {
    final toLeft = hasLogo && profile.logoPosition == 'bottom-right';
    return Positioned(
      bottom: _tlpBottomInset(w),
      left: toLeft ? w * _kTlpEdge : null,
      right: toLeft ? null : w * _kTlpEdge,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: w * _kTlpHPad,
          vertical: w * _kTlpVPad,
        ),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(w * 0.005),
        ),
        child: Text(tlp.label, style: _tlpMarkingTextStyle(w, tlp)),
      ),
    );
  }
}

class _FooterOverlay extends StatelessWidget {
  final Slide slide;
  final double w;
  final ThemeProfile profile;
  final int? slideNumber;
  final int? slideCount;
  final TlpLevel tlp;

  const _FooterOverlay({
    required this.slide,
    required this.w,
    required this.profile,
    this.slideNumber,
    this.slideCount,
    this.tlp = TlpLevel.none,
  });

  String _applyTokens(String s) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${two(now.day)}-${two(now.month)}-${now.year}';
    return s
        .replaceAll('{page}', slideNumber?.toString() ?? '')
        .replaceAll('{total}', slideCount?.toString() ?? '')
        .replaceAll('{date}', date)
        .replaceAll('{title}', slide.title);
  }

  @override
  Widget build(BuildContext context) {
    if (!slide.showFooter) return const SizedBox.shrink();
    if (slide.type == SlideType.title || slide.type == SlideType.section) {
      return const SizedBox.shrink();
    }

    final footerText = _applyTokens(profile.footerText).trim();
    final showPages = profile.footerShowPageNumbers && slideNumber != null;
    if (footerText.isEmpty && !showPages) return const SizedBox.shrink();

    // Iets kleiner dan voorheen, zodat 'ie niet tegen het logo aan drukt.
    final fontSize = w * 0.0145;
    final style = TextStyle(
      color: _hexColor(profile.textColor).withValues(alpha: 0.7),
      fontSize: fontSize,
      // Lichte schaduw zodat de footer ook over een afbeelding leesbaar blijft.
      shadows: [
        Shadow(
          color: Colors.white.withValues(alpha: 0.5),
          blurRadius: w * 0.003,
        ),
      ],
    );

    // Onderhoeken vrijhouden: de footer wijkt horizontaal uit voor het logo en
    // de TLP-badge, zodat ze netjes uitlijnen i.p.v. over elkaar te vallen.
    double mx(double a, double b) => a > b ? a : b;
    final hasLogo = profile.logoPath?.isNotEmpty == true && slide.showLogo;
    final logoBottom = hasLogo && profile.logoPosition.startsWith('bottom');
    final logoOnLeft = profile.logoPosition.endsWith('left');
    final logoSpan = w * (profile.logoSize / 1280) * 1.28 + w * 0.012;
    final logoLeftEdge = w * (profile.logoSize / 1280) * 0.28;
    final tlpOnRight = !(hasLogo && profile.logoPosition == 'bottom-right');
    final tlpSpan = tlp == TlpLevel.none
        ? 0.0
        : w * _kTlpEdge + _tlpBadgeWidth(w, tlp) + w * 0.012;
    final footerLeftAligned = profile.footerPosition == 'left';

    // Links uitgelijnd begint de footer waar het logo of de bullets beginnen,
    // voor een consistente linkermarge. Anders de standaardmarge.
    var left = footerLeftAligned
        ? (logoBottom && logoOnLeft
              ? logoLeftEdge
              : _contentLeftInset(slide, w))
        : w * 0.04;
    var right = w * 0.04;
    if (logoBottom) {
      if (logoOnLeft) {
        // Een links-uitgelijnde footer mag bewust met de logo-linkerkant
        // uitlijnen; anders schuift 'ie rechts van het logo om overlap te
        // voorkomen.
        if (!footerLeftAligned) left = mx(left, logoSpan);
      } else {
        right = mx(right, logoSpan);
      }
    }
    if (tlp != TlpLevel.none) {
      if (tlpOnRight) {
        right = mx(right, tlpSpan);
      } else {
        left = mx(left, tlpSpan);
      }
    }

    final alignment = switch (profile.footerPosition) {
      'left' => Alignment.centerLeft,
      'center' => Alignment.center,
      _ => Alignment.centerRight,
    };
    final textAlign = switch (profile.footerPosition) {
      'left' => TextAlign.left,
      'center' => TextAlign.center,
      _ => TextAlign.right,
    };

    return Positioned(
      left: left,
      right: right,
      bottom: w * 0.02,
      child: Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: w - left - right),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (footerText.isNotEmpty)
                Flexible(
                  child: Text(
                    footerText,
                    style: style,
                    textAlign: textAlign,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (footerText.isNotEmpty && showPages) SizedBox(width: w * 0.02),
              if (showPages)
                Text(
                  '$slideNumber / ${slideCount ?? slideNumber}',
                  style: style,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact page navigation, placed beside the slide logo (or bottom-right).
class _RichTextPageControlsOverlay extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;
  final TlpLevel tlp;
  final int pageIndex;
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _RichTextPageControlsOverlay({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
    this.tlp = TlpLevel.none,
    required this.pageIndex,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final hasLogo = profile.logoPath?.isNotEmpty == true && slide.showLogo;
    final logoSize = w * (profile.logoSize / 1280);
    final logoHInset = logoSize * 0.28;
    final logoTopInset = logoSize * 0.42;
    final logoBottomInset = logoSize * 0.12;
    final controlH = w * 0.022;
    final gap = w * 0.008;

    final controls = _RichTextPageControls(
      pageIndex: pageIndex,
      pageCount: pageCount,
      w: w,
      font: font,
      profile: profile,
      onPrevious: onPrevious,
      onNext: onNext,
    );

    if (hasLogo) {
      final pos = profile.logoPosition;
      final onRight = pos.endsWith('right');
      final onLeft = pos.endsWith('left');
      final onBottom = pos.startsWith('bottom');
      final onTop = pos.startsWith('top');
      final verticalOffset = onBottom
          ? logoBottomInset + (logoSize - controlH) / 2
          : logoTopInset + (logoSize - controlH) / 2;

      if (onRight) {
        return Positioned(
          right: logoHInset + logoSize + gap,
          bottom: onBottom ? verticalOffset : null,
          top: onTop ? verticalOffset : null,
          child: controls,
        );
      }
      if (onLeft) {
        return Positioned(
          left: logoHInset + logoSize + gap,
          bottom: onBottom ? verticalOffset : null,
          top: onTop ? verticalOffset : null,
          child: controls,
        );
      }
    }

    return Positioned(
      right:
          w * 0.04 +
          (tlp != TlpLevel.none
              ? w * _kTlpEdge + _tlpBadgeWidth(w, tlp) + w * 0.012
              : 0),
      bottom: w * 0.022,
      child: controls,
    );
  }
}

class _RichTextPageControls extends StatelessWidget {
  final int pageIndex;
  final int pageCount;
  final double w;
  final String font;
  final ThemeProfile profile;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _RichTextPageControls({
    required this.pageIndex,
    required this.pageCount,
    required this.w,
    required this.font,
    required this.profile,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = _hexColor(profile.textColor);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _hexColor(profile.slideBackgroundColor).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(w * 0.004),
        border: Border.all(color: textColor.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: w * 0.004),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _navButton(
              icon: Icons.chevron_left,
              enabled: onPrevious != null,
              onTap: onPrevious,
              textColor: textColor,
            ),
            Text(
              '${pageIndex + 1}/$pageCount',
              style: _applyFont(
                font,
                TextStyle(
                  fontSize: w * 0.013,
                  fontWeight: FontWeight.w500,
                  color: textColor.withValues(alpha: 0.6),
                  height: 1.0,
                ),
              ),
            ),
            _navButton(
              icon: Icons.chevron_right,
              enabled: onNext != null,
              onTap: onNext,
              textColor: textColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _navButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback? onTap,
    required Color textColor,
  }) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: w * 0.024,
        height: w * 0.022,
        child: Icon(
          icon,
          size: w * 0.014,
          color: enabled
              ? textColor.withValues(alpha: 0.5)
              : textColor.withValues(alpha: 0.18),
        ),
      ),
    );
  }
}
