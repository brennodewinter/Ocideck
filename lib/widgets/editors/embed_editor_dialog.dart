import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// De gedeelde dialoogschil voor het bewerken van een ingebedde kaart (grafiek
/// of tabel): de volwaardige editor in een venster met Annuleren/Toepassen
/// (bestaande l10n). Het venster mikt op 760×560 maar klemt op de
/// kijkvenstermaat, zodat het ook op een klein of laag scherm past in plaats van
/// horizontaal over te lopen (de vaste maat kromp zelf niet mee). Geeft `true`
/// terug bij Toepassen.
///
/// Gedeeld door de bron-preview (dubbelklik-embeds in de documenteditor) én de
/// visuele editor (tabel-embed in de Quill-laag), zodat beide bewerkroutes exact
/// dezelfde schil en maatregels gebruiken — geen tweede dialoog om uit de pas te
/// laten lopen.
Future<bool?> showEmbedEditorDialog(BuildContext context, Widget editor) {
  final l10n = context.l10n;
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final media = MediaQuery.of(ctx).size;
      final width = math.max(280.0, math.min(760.0, media.width - 96));
      final height = math.max(320.0, math.min(560.0, media.height - 160));
      return AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        content: SizedBox(
          width: width,
          height: height,
          child: SingleChildScrollView(child: editor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.d('Annuleren')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.d('Toepassen')),
          ),
        ],
      );
    },
  );
}
