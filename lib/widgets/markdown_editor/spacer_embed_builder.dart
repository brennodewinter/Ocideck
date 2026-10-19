import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/spacer_embed_syntax.dart';
import 'markdown_editor_theme.dart';
import '../../models/settings.dart' show documentBodyFontSizeToCssPx;
import '../reader/document_markdown_view.dart'
    show kDocumentBodyFontSize, kDocumentBodyLineHeight;

/// Tekent een `x-embed-spacer`-blok — de `<!-- spacer -->`-marker — in de
/// visuele (Quill) editor als de ruimte die hij is: ongeveer één tekstregel
/// hoog, met een subtiele aanduiding zodat je ziet dát er een bewust blok
/// staat en niet gewoon een lege regel.
///
/// De embed is één documentteken: selecteren en Backspace/Delete haalt het
/// hele blok weg, en Undo zet hem terug — geen losse tekens om bij te houden.
class SpacerEmbedBuilder extends EmbedBuilder {
  const SpacerEmbedBuilder();

  @override
  String get key => EmbeddableSpacer.spacerType;

  /// Een tussenruimte is een blok, geen inline-teken: hij vult de breedte.
  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final profile = DocumentStyleScope.maybeOf(context);
    // Één bodytekstregel: dezelfde maat als de documentweergave en de PDF,
    // zodat wat je invoegt is wat je exporteert.
    final lineHeight =
        documentBodyFontSizeToCssPx(
          profile?.documentBodyFontSize ?? kDocumentBodyFontSize,
        ) *
        kDocumentBodyLineHeight;
    return SizedBox(
      height: lineHeight,
      width: double.infinity,
      child: Center(
        child: Text(
          context.l10n.d('Extra ruimte'),
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
