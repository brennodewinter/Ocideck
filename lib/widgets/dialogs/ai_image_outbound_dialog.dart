// De bevestiging vóór een afbeelding naar een AI-model gaat.
//
// ── Waarom hier geen projectie staat, en wat er in de plaats komt ────────────
//
// Tekst die naar een extern model gaat, loopt eerst door
// `PrivacyProjection.forExternalProcessing`: alles wat de scanner vindt is er
// dan al uit, ook op een dia die de auteur bewust heeft geaccepteerd. Voor een
// afbeelding kán dat niet. De projectie vervangt tekens, en in een JPEG staan
// geen tekens — een gezicht wegpoetsen of een BSN uit een schermafdruk halen is
// een heel ander soort ingreep, en de gezichtsdetectie die we hebben mist
// aantoonbaar (van achteren, in profiel, met mondkapje, in HEIC).
//
// Wat overblijft is dus niet "strenger redigeren" maar eerlijk zijn: zeggen wát
// er weggaat en waarheen, vóórdat het weggaat. `docs/design/OCIWACHT.md` §6.1
// noemt dit kanaal daarom "geen projectie", en deze dialoog is de waarborg die
// er in de plaats van staat.
//
// De carrousel had zo'n bevestiging al voor de bulkactie; het losse alt-tekstveld
// niet. Daar stuurde één klik de hele afbeelding naar een derde partij zonder
// dat er ergens stond dat dat gebeurde — in een app waarvan de belofte begint
// met "het blijft op dit apparaat".

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_settings.dart';
import '../../theme/app_theme.dart';

/// Waar de afbeelding naartoe gaat, in mensentaal.
///
/// Bij een cloud-backend de werkelijke URL en niet "de cloud": de gebruiker moet
/// kunnen zien of dat zijn eigen server is of die van iemand anders.
String aiImageDestination(AppLocalizations l10n, AiSettings settings) =>
    settings.mode == AiBackendMode.cloud
    ? settings.baseUrl
    : l10n.d('een model op dit apparaat');

/// Vraagt toestemming om [imageCount] afbeelding(en) naar het model te sturen.
///
/// [faceCount] is het aantal herkenbare gezichten dat de beeldcontrole vond, of
/// 0 wanneer er niet is gekeken (web, uitgezette controle, onleesbaar bestand).
/// Nul betekent hier dus *niet* "er staat niemand op" — vandaar dat de regel bij
/// nul helemaal wegblijft in plaats van "geen gezichten gevonden" te beweren.
///
/// Geeft `false` bij afbreken, zodat een gesloten dialoog nooit als "ja" leest.
Future<bool> confirmAiImageOutbound(
  BuildContext context, {
  required String title,
  required AiSettings settings,
  required int imageCount,
  int faceCount = 0,
}) async {
  final l10n = context.l10n;
  final destination = aiImageDestination(l10n, settings);
  final answer = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            imageCount == 1
                ? '${ctx.l10n.d('De afbeelding gaat ongewijzigd naar')} '
                      '$destination.'
                : '$imageCount ${ctx.l10n.d('afbeeldingen gaan naar')} '
                      '$destination.',
          ),
          const SizedBox(height: 8),
          Text(
            ctx.l10n.d(
              'OciDeck lakt niets weg in een afbeelding: gezichten, tekst op een schermafdruk en gegevens in beeld gaan mee.',
            ),
            style: TextStyle(fontSize: 12, color: AppTheme.slate500),
          ),
          if (faceCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              ctx.l10n.d(
                'De beeldcontrole vond hier een of meer herkenbare gezichten.',
              ),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.warningFg,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.l10n.d('Annuleren')),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ctx.l10n.d('Doorgaan')),
        ),
      ],
    ),
  );
  return answer ?? false;
}
