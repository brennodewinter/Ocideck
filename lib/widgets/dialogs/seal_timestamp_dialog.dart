import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/deck.dart';
import '../../services/rfc3161_timestamp.dart';
import '../../state/deck_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/atomic_file.dart';
import '../../utils/log.dart';

/// RFC 3161 trusted-timestamp workflow for the deck seal (PENTEST_MIAUW §8-A2).
/// OciDeck stays a producer of hashes: it **exports** a `.tsq` for the current
/// seal hash, the user has OpenKAT / a TSA timestamp it out-of-band, and the
/// returned `.tsr` is **imported and verified** — its message imprint must equal
/// the seal hash. Takes the tab's [DeckNotifier] (root-navigator dialog, so it
/// must not read the scoped provider) and subscribes to it so the status updates
/// after an import.
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
                    'SHA-512: ${deck.sealHash.substring(0, 24)}…',
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
    final matches = token != null && timeStampMatchesHash(token, deck.sealHash);
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
    final tsq = buildTimeStampRequest(_hexToBytes(deck.sealHash));
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: l10n.d('Verzoek (.tsq) exporteren'),
        fileName: 'ocideck-seal.tsq',
        bytes: kIsWeb ? tsq : null,
      );
      if (path == null || kIsWeb) return; // web already downloaded via bytes
      final target = path.endsWith('.tsq') ? path : '$path.tsq';
      await writeBytesAtomic(File(target), tsq);
      _toast(l10n.d('Tijdstempelverzoek opgeslagen'));
    } catch (e, s) {
      logError('SealTimestampDialog._exportTsq', e, s);
    }
  }

  Future<void> _importTsr(Deck deck) async {
    final l10n = context.l10n;
    try {
      final result = await FilePicker.pickFiles(withData: true);
      final bytes = result?.files.single.bytes;
      if (bytes == null) return;
      if (timeStampMatchesHash(bytes, deck.sealHash)) {
        widget.notifier.setSealTimestampToken(base64Url.encode(bytes));
        _toast(l10n.d('Tijdstempel geïmporteerd'));
      } else {
        _toast(l10n.d('Tijdstempel komt niet overeen met de seal-hash'));
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

  Uint8List _hexToBytes(String hex) => Uint8List.fromList([
    for (var i = 0; i + 1 < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);

  Uint8List? _decodeToken(String base64Token) {
    try {
      return base64Url.decode(base64Token);
    } on FormatException {
      return null;
    }
  }
}
