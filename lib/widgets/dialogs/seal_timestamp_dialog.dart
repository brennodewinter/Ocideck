import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/deck.dart';
import '../../services/rfc3161_timestamp.dart';
import '../../state/deck_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/atomic_file.dart';
import '../../utils/file_extension.dart';
import '../../utils/log.dart';

/// De RFC 3161-tijdstempelroute voor het documentzegel (PENTEST_MIAUW §8-A2).
/// OciDeck blijft een producent van hashes: het **exporteert** een `.tsq` voor
/// de huidige zegelhash, de gebruiker laat OpenKAT of een TSA die buiten de app
/// om tijdstempelen, en het teruggekomen `.tsr` wordt geïmporteerd zodra zijn
/// message imprint gelijk is aan de zegelhash.
///
/// Dat is ook alles wat er wordt gecontroleerd — de handtekening van de TSA en
/// haar certificaatketen niet (zie `rfc3161_timestamp.dart`). Deze dialoog
/// toont daarom nooit een groen "geverifieerd"-vinkje: het tijdstip staat er
/// als neutrale mededeling met de kanttekening eronder.
///
/// Neemt de [DeckNotifier] van het tabblad aan (dialoog op de root-navigator,
/// dus de scoped provider mag niet gelezen worden) en luistert erop, zodat de
/// status meebeweegt na een import.
class SealTimestampDialog extends StatefulWidget {
  const SealTimestampDialog({super.key, required this.notifier});

  final DeckNotifier notifier;

  static Future<void> show(BuildContext context, DeckNotifier notifier) =>
      showDialog<void>(
        context: context,
        builder: (_) => SealTimestampDialog(notifier: notifier),
      );

  @override
  State<SealTimestampDialog> createState() => _SealTimestampDialogState();
}

class _SealTimestampDialogState extends State<SealTimestampDialog> {
  Deck? _deck;
  VoidCallback? _removeListener;

  @override
  void initState() {
    super.initState();
    _deck = widget.notifier.currentState.deck;
    _removeListener = widget.notifier.addListener((state) {
      if (mounted) setState(() => _deck = state.deck);
    }, fireImmediately: false);
  }

  @override
  void dispose() {
    _removeListener?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final deck = _deck;
    final sealed = deck != null && deck.sealHash.isNotEmpty;
    return AlertDialog(
      title: Text(l10n.d('RFC3161-tijdstempel')),
      content: SizedBox(
        width: 480,
        child: !sealed
            ? Text(l10n.d('Verzegel het deck eerst.'))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // Afgekapt met een beletselteken, tenzij de hash korter is
                    // dan dat — substring(0, 24) op een beschadigde hash liet
                    // het hele scherm crashen op een RangeError.
                    '${l10n.d('SHA-512:')} ${_shortHash(deck.sealHash)}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: AppTheme.slate500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _exportTsq(deck),
                        icon: const Icon(Icons.download_outlined, size: 16),
                        label: Text(l10n.d('Verzoek (.tsq) exporteren')),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _importTsr(deck),
                        icon: const Icon(Icons.upload_file_outlined, size: 16),
                        label: Text(l10n.d('Token (.tsr) importeren')),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _status(l10n, deck),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Sluiten')),
        ),
      ],
    );
  }

  Widget _status(AppLocalizations l10n, Deck deck) {
    if (deck.sealTimestampToken.isEmpty) {
      return Text(
        l10n.d('Nog geen tijdstempel'),
        style: TextStyle(fontSize: 12, color: AppTheme.slate500),
      );
    }
    final token = _decodeToken(deck.sealTimestampToken);
    final parsed = token == null ? null : parseTimeStampToken(token);
    final matches =
        token != null && timeStampImprintMatchesHash(token, deck.sealHash);
    if (parsed == null || !matches) {
      return Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: AppTheme.danger800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.d('Tijdstempel komt niet overeen met de seal-hash'),
              style: TextStyle(fontSize: 12, color: AppTheme.danger800),
            ),
          ),
        ],
      );
    }
    // The token's message imprint matches this seal, but its CMS signature and
    // TSA certificate chain are deliberately NOT verified in-app (see
    // rfc3161_timestamp.dart, §8-A3). So genTime is the token's *claim*, not a
    // checked fact — whoever holds the deck can mint a token with an arbitrary
    // time and a matching imprint. Present it as neutral information, never a
    // green "verified" trust badge that would overstate what was checked.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.schedule, size: 16, color: AppTheme.slate600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${l10n.d('Getijdstempeld op')} '
                '${parsed.genTime.toIso8601String()}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          // Uitgelijnd onder de tekst (icoon 16 + 8 tussenruimte), zodat de
          // kanttekening bij het tijdstip hoort.
          padding: const EdgeInsets.only(left: 24),
          child: Text(
            l10n.d(
              'De TSA-handtekening is niet in-app geverifieerd; alleen de hash komt overeen.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate500),
          ),
        ),
      ],
    );
  }

  Future<void> _exportTsq(Deck deck) async {
    final l10n = context.l10n;
    // Een verse nonce per verzoek: zo bindt het token dat terugkomt zich aan
    // dít verzoek en niet aan een willekeurig eerder verzoek voor dezelfde
    // hash. Hij wordt bewaard in de zegel-sidecar, zodat [_importTsr] de echo
    // kán nakijken — het verzoek gaat buiten de app om naar de TSA, dus zonder
    // die opslag was de andere helft na een herstart weg.
    final nonce = newTimeStampNonce();
    final tsq = buildTimeStampRequestForSealHash(deck.sealHash, nonce: nonce);
    if (tsq == null) {
      // Een zegel dat geen SHA-512 is, is geen zegel. Eerder werd de hash
      // half ingelezen en alsnog een verzoek geëxporteerd — dan laat je een
      // TSA een document stempelen dat niet bestaat.
      _toast(l10n.d('Tijdstempel komt niet overeen met de seal-hash'));
      return;
    }
    try {
      if (kIsWeb) {
        await FilePicker.saveFile(
          dialogTitle: l10n.d('Verzoek (.tsq) exporteren'),
          fileName: 'ocideck-seal.tsq',
          bytes: tsq,
        );
      } else {
        final location = await getSaveLocation(
          suggestedName: 'ocideck-seal.tsq',
        );
        if (location == null) return;
        final target = withExtension(location.path, '.tsq');
        await writeBytesAtomic(File(target), tsq);
      }
      // Pas onthouden als het verzoek de deur uit is. Andersom zou een
      // afgebroken bestandskiezer een nonce achterlaten voor een verzoek dat
      // nooit verstuurd is, en dan weigert de volgende import terecht maar
      // onbegrijpelijk.
      widget.notifier.setSealTimestampNonce(timeStampNonceHex(nonce));
      _toast(l10n.d('Tijdstempelverzoek opgeslagen'));
    } catch (e, s) {
      logError('SealTimestampDialog._exportTsq', e, s);
    }
  }

  Future<void> _importTsr(Deck deck) async {
    final l10n = context.l10n;
    try {
      final file = await FilePicker.pickFile();
      if (file == null) return;
      final bytes = await file.readAsBytes();
      // De imprint zegt "dit token gaat over deze hash". De nonce zegt "en het
      // is het antwoord op mijn verzoek". Het oordeel zelf staat in
      // rfc3161_timestamp.dart, zodat het toetsbaar is zonder bestandskiezer.
      switch (judgeTimeStampImport(
        bytes,
        sealHash: deck.sealHash,
        expectedNonceHex: deck.sealTimestampNonce,
      )) {
        case TimeStampImportVerdict.imprintMismatch:
          _toast(l10n.d('Tijdstempel komt niet overeen met de seal-hash'));
        case TimeStampImportVerdict.wrongRequest:
          _toast(l10n.d('Deze tijdstempel hoort niet bij het laatste verzoek'));
        case TimeStampImportVerdict.accepted:
          widget.notifier.setSealTimestampToken(base64Url.encode(bytes));
          _toast(l10n.d('Tijdstempel geïmporteerd'));
      }
    } catch (e, s) {
      logError('SealTimestampDialog._importTsr', e, s);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static const _hashPreviewChars = 24;

  String _shortHash(String hash) => hash.length <= _hashPreviewChars
      ? hash
      : '${hash.substring(0, _hashPreviewChars)}…';

  Uint8List? _decodeToken(String base64Token) {
    try {
      return base64Url.decode(base64Token);
    } on FormatException {
      return null;
    }
  }
}
