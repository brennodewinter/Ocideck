import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/exchange_rate.dart';
import '../../models/presentation_cost.dart';
import '../../services/exchange_rate_service.dart';
import '../../utils/exchange_rate_label.dart';

/// Vraagt vóór de sessie één koers per benodigde vreemde valuta (#2438).
///
/// Drie routes voor dezelfde uitkomst: ophalen bij Frankfurter/ECB (alleen op
/// de knop — dat ís de toestemming voor het ene netwerkverzoek), zelf
/// invullen, of zonder koers doorgaan. `null` bij annuleren betekent: de
/// sessie start niet — hetzelfde contract als het aanwezigenscherm.
class CurrencyConversionDialog extends StatefulWidget {
  /// De vreemde valuta waarvoor een EUR-koers nodig is — kan de sessievaluta
  /// zelf zijn (voor de EUR-weergave) of de valuta van aanwezigen-regels.
  final List<CostCurrency> currencies;

  /// Haalt één koers op; in productie [fetchEurRate], in een test een
  /// stand-in zodat er geen netwerkverkeer nodig is.
  final Future<ExchangeRate?> Function(String code) fetchRate;

  const CurrencyConversionDialog({
    super.key,
    required this.currencies,
    this.fetchRate = _fetchFromService,
  });

  /// Toont het scherm; `null` bij annuleren. De map bevat alleen valuta met
  /// een geldige koers — 'zonder koers doorgaan' kan dus een lege of
  /// gedeeltelijke map geven; de roeper toont dan 'koers ontbreekt'.
  static Future<Map<String, ExchangeRate>?> show(
    BuildContext context, {
    required List<CostCurrency> currencies,
  }) {
    return showDialog<Map<String, ExchangeRate>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CurrencyConversionDialog(currencies: currencies),
    );
  }

  @override
  State<CurrencyConversionDialog> createState() =>
      _CurrencyConversionDialogState();
}

Future<ExchangeRate?> _fetchFromService(String code) => fetchEurRate(code);

class _CurrencyConversionDialogState extends State<CurrencyConversionDialog> {
  final Map<String, TextEditingController> _controllers = {};

  /// De per valuta opgehaalde koers; bewerkt de gebruiker het veld daarna,
  /// dan geldt die invoer als handmatig — de bron verandert mee.
  final Map<String, ExchangeRate> _fetched = {};
  bool _fetching = false;
  bool _fetchFailed = false;

  @override
  void initState() {
    super.initState();
    for (final c in widget.currencies) {
      _controllers[c.code] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// De koers zoals die nu voor [code] geldt: opgehaald en onaangeroerd, of
  /// handmatig ingevoerd met vandaag als peildatum. `null` bij leeg of rot.
  ExchangeRate? _rateFor(String code) {
    final micros = parseRateMicros(_controllers[code]!.text);
    if (micros == null) return null;
    final fetched = _fetched[code];
    if (fetched != null && fetched.eurMicros == micros) return fetched;
    return ExchangeRate(
      code: code,
      eurMicros: micros,
      source: '',
      date: _today(),
      manual: true,
    );
  }

  bool get _allFilled =>
      widget.currencies.every((c) => _rateFor(c.code) != null);

  Future<void> _fetch() async {
    setState(() {
      _fetching = true;
      _fetchFailed = false;
    });
    var failed = false;
    for (final c in widget.currencies) {
      final rate = await widget.fetchRate(c.code);
      if (!mounted) return;
      if (rate == null) {
        failed = true;
      } else {
        _fetched[c.code] = rate;
        _controllers[c.code]!.text = rate.microsLabel;
      }
    }
    setState(() {
      _fetching = false;
      _fetchFailed = failed;
    });
  }

  /// Levert de ingevulde geldige koersen — een lege map bij 'zonder koers'.
  void _confirm() {
    Navigator.of(
      context,
    ).pop({for (final c in widget.currencies) c.code: ?_rateFor(c.code)});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.currency_exchange_outlined, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.d('Omrekening naar euro'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          // Scrolt: met meerdere valuta en de bronregels is de inhoud hoger
          // dan een laag venster; afgeknipte knoppen zijn hier onacceptabel.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.d(
                    'Voor de EUR-weergave gebruikt OciDeck één koers per sessie. Vul de koers zelf in of haal de ECB-referentiekoers op.',
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                for (final c in widget.currencies)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(width: 70, child: Text('1 ${c.code} =')),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            key: ValueKey('rate-${c.code}'),
                            controller: _controllers[c.code],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]'),
                              ),
                            ],
                            decoration: InputDecoration(
                              prefixText: '€ ',
                              isDense: true,
                              errorText: _errorFor(c.code),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                for (final c in widget.currencies)
                  if (_rateFor(c.code) case final r?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${c.code}: ${exchangeRateProvenance(l10n, r)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                if (_fetchFailed)
                  Text(
                    l10n.d(
                      'Ophalen mislukt — vul de koers zelf in of ga zonder koers verder.',
                    ),
                    style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                  ),
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const ValueKey('rate-fetch'),
                  onPressed: _fetching ? null : _fetch,
                  icon: const Icon(Icons.cloud_download_outlined, size: 18),
                  label: Text(l10n.d('Koers ophalen bij Frankfurter (ECB)')),
                ),
                Text(
                  l10n.d(
                    'Eén verzoek per valuta naar api.frankfurter.dev met alleen de valutacode; de dienst ziet wel het IP-adres. Er worden geen presentatiegegevens verstuurd.',
                  ),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('rate-cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.d('Annuleren')),
          ),
          TextButton(
            key: const ValueKey('rate-skip'),
            onPressed: () => _confirm(),
            child: Text(l10n.d('Zonder koers doorgaan')),
          ),
          FilledButton(
            key: const ValueKey('rate-confirm'),
            onPressed: _allFilled ? () => _confirm() : null,
            child: Text(l10n.d('Bevestigen')),
          ),
        ],
      ),
    );
  }

  /// Foutmarkering: alleen bij tekst die niet parseert — een leeg veld is
  /// 'ontbreekt', geen fout. De melding is echte tekst: een rood veld zonder
  /// woorden zegt een schermlezer niets.
  String? _errorFor(String code) {
    final text = _controllers[code]!.text.trim();
    if (text.isEmpty) return null;
    return parseRateMicros(text) == null
        ? context.l10n.d('Geen geldige koers — gebruik bijvoorbeeld 0,92.')
        : null;
  }
}

String _today() {
  final n = DateTime.now();
  return '${n.year}-'
      '${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}
