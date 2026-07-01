import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// A small flag for a language code, for the language pickers. Most languages
/// use a flag emoji (rendered by the platform); Frisian has no country-flag
/// emoji, so it uses a bundled image of the Frisian flag.
Widget languageFlag(String code, {double size = 15}) {
  if (code == 'fy') {
    return Image.asset(
      'assets/images/flag_fy.png',
      height: size * 0.92,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
  final flag = AppLocalizations.languageFlags[code];
  if (flag == null) return const SizedBox.shrink();
  return Text(flag, style: TextStyle(fontSize: size));
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
