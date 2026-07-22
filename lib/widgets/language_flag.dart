import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Language codes shown as a neutral letter badge rather than a flag.
///
/// Klingon used to ship `assets/images/flag_tlh.png`: the Klingon trefoil, the
/// emblem of the Klingon Empire from the Star Trek franchise, carried in every
/// binary we distribute. Naming "Marp" or "Nextcloud" is nominative use of a
/// name; reproducing someone else's emblem as artwork is not. The language
/// stays — only the mark goes, replaced by its ISO 639-3 code in the same
/// footprint a flag occupies.
const _letterBadges = <String>{'tlh'};

/// A small flag for a language code, for the language pickers. Most languages
/// use a flag emoji (rendered by the platform); Frisian has no country-flag
/// emoji and uses a bundled image of the Frisian flag — a regional flag, not a
/// protected mark. See [_letterBadges] for the codes that get a letter badge.
Widget languageFlag(String code, {double size = 15}) {
  if (_letterBadges.contains(code)) return _letterBadge(code, size);
  const bundled = {'fy': 'assets/images/flag_fy.png'};
  final asset = bundled[code];
  if (asset != null) {
    return Image.asset(
      asset,
      height: size * 0.92,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
  final flag = AppLocalizations.languageFlags[code];
  if (flag == null) return const SizedBox.shrink();
  return Text(flag, style: TextStyle(fontSize: size));
}

/// The language code itself, set in a rounded slate chip roughly the size of a
/// flag emoji. The label is the [code] variable, never a literal, so it needs no
/// translation — an ISO 639-3 code is the same in every language.
Widget _letterBadge(String code, double size) {
  return Container(
    height: size * 0.92,
    padding: EdgeInsets.symmetric(horizontal: size * 0.18),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppTheme.slate500,
      borderRadius: BorderRadius.circular(size * 0.2),
    ),
    child: Text(
      code,
      style: TextStyle(
        fontSize: size * 0.52,
        height: 1.05,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: Colors.white,
      ),
    ),
  );
}

/// A dropdown row: the language's flag followed by its display name.
Widget languageOptionRow(String code, String name, {double fontSize = 14}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 24,
        child: Center(child: languageFlag(code, size: fontSize + 2)),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          name,
          style: TextStyle(fontSize: fontSize),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}
