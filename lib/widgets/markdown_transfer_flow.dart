import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/markdown_transfer_bridge.dart';
import '../services/markdown_transfer_protocol.dart';
import '../state/tabs_provider.dart';
import 'dialogs/markdown_transfer_dialog.dart';

/// Beantwoord een aangeboden Markdown-overdracht van de
/// postMessage-browserkoppeling (#2827): weigeren stuurt `declined`;
/// openen gaat door exact dezelfde poort als geplakte tekst (#2825) en de
/// site krijgt alleen de uitkomst — `unsafe`/`invalid`, nooit inhoud.
///
/// Apart van `web_wiring.dart` omdat een `part of`-bestand niet los te
/// testen is; dit is het enige stuk van de koppeling dat zowel UI als de
/// openpoort raakt.
Future<void> answerMarkdownTransfer(
  BuildContext context,
  WidgetRef ref,
  InboundMarkdownRequest request,
  MarkdownTransferBridge? bridge,
) async {
  if (bridge == null || !context.mounted) return;
  final consent = await MarkdownTransferConsentDialog.show(
    context,
    origin: request.origin,
    name: request.name,
  );
  if (!context.mounted) return;
  if (!consent) {
    bridge.answer(request.id, kStatusDeclined);
    return;
  }
  ref.read(openFailureProvider.notifier).state = null;
  final result = await ref
      .read(tabsProvider.notifier)
      .openDeckFromBytes(
        Uint8List.fromList(utf8.encode(request.markdown)),
        request.name ?? 'overdracht.md',
      );
  if (result == OpenResult.opened) {
    bridge.answer(request.id, kStatusOpened);
  } else if (result == OpenResult.blocked) {
    bridge.answer(request.id, kStatusRejected, reason: kReasonUnsafe);
  } else {
    bridge.answer(request.id, kStatusRejected, reason: kReasonInvalid);
  }
}
