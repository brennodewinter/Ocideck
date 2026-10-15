import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_evidence_item.dart';
import '../../models/ociserve_portfolio_import.dart';
import '../../services/ociserve/ociserve_http.dart';
import '../../state/ociserve_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';

/// De portefeuille-import — stap 1: credentials binnenhalen (via een publieke
/// verificatielink of een gedownload credential-bestand), stap 2: zelf kiezen
/// wat je deelt. Pas de aangevinkte items worden bewijsstuk in het dossier;
/// de rest van de import-sessie blijft ongedeeld.
///
/// Ontwerpregels uit #2040:
/// - Eerst alles ophalen, dan pas kiezen wat je deelt (minimalisatie).
/// - Nooit zoeken op e-mailadres — dat lekt persoonsgegevens naar de provider.
/// - De lokale ervaring is nergens afhankelijk van het slagen van de import.
class OciServePortfolioLink extends ConsumerStatefulWidget {
  const OciServePortfolioLink({
    super.key,
    required this.organizationId,
    required this.participantId,
    required this.evidenceTypes,
    required this.onShared,
    this.fetchDocument,
    this.pickFile,
  });

  final String organizationId;
  final String participantId;
  final List<OciServeEvidenceType> evidenceTypes;

  /// Wordt aangeroepen nadat de keuze is gedeeld, zodat het scherm ververst.
  final VoidCallback onShared;

  /// Vervangt de publieke-link-fetch en de bestandskiezer; bedoeld voor tests.
  final Future<Object?> Function(Uri url)? fetchDocument;
  final Future<({String name, Uint8List bytes})?> Function()? pickFile;

  @override
  ConsumerState<OciServePortfolioLink> createState() =>
      _OciServePortfolioLinkState();
}

enum _Phase { idle, fetching, choosing, sharing }

class _OciServePortfolioLinkState extends ConsumerState<OciServePortfolioLink> {
  _Phase _phase = _Phase.idle;
  final _linkController = TextEditingController();
  OciServePortfolioImport? _import;
  final Set<String> _selected = {};
  String? _typeId;
  String? _error;

  /// Eén sleutel per poging, zodat een herhaling na een netwerkfout nooit een
  /// tweede sessie of tweede selectie maakt. De sleutels resetten bij een
  /// nieuwe importronde.
  String _importKey = const Uuid().v4();
  String _shareKey = const Uuid().v4();

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return switch (_phase) {
      _Phase.idle => _idle(l10n, theme),
      _Phase.fetching => _fetching(l10n, theme),
      _Phase.choosing || _Phase.sharing => _choosing(l10n, theme),
    };
  }

  Widget _idle(AppLocalizations l10n, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d(
            'Haal bestaande badges en certificaten binnen uit een externe '
            'portefeuille en deel ze als bewijs. U kiest zelf wat u deelt.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.d('Publieke verificatielink'),
          style: theme.textTheme.labelMedium,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _linkController,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'https://…',
                  border: const OutlineInputBorder(),
                  errorText: _error == 'link_invalid'
                      ? l10n.d(
                          'Dat is geen geldige HTTPS-link naar een credential.',
                        )
                      : null,
                ),
                keyboardType: TextInputType.url,
                onSubmitted: (_) => _fetchLink(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _fetchLink,
              child: Text(l10n.d('Ophalen')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _pickCredentialFile,
          icon: const Icon(Icons.file_open_outlined),
          label: Text(l10n.d('Credential-bestand kiezen')),
        ),
        if (_error != null && _error != 'link_invalid') ...[
          const SizedBox(height: 12),
          Text(
            _errorText(l10n, _error!),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _fetching(AppLocalizations l10n, ThemeData theme) {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text(l10n.d('Credentials ophalen…')),
      ],
    );
  }

  Widget _choosing(AppLocalizations l10n, ThemeData theme) {
    final palette = AppPalette.of(theme);
    final items = _import?.items ?? const <OciServePortfolioImportItem>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Kies welke credentials u deelt als bewijs:'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Text(
            l10n.d('Geen credentials gevonden in deze bron.'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.accentInk.withValues(alpha: 0.6),
            ),
          )
        else
          for (final item in items)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _selected.contains(item.id),
              onChanged: _phase == _Phase.sharing
                  ? null
                  : (value) => setState(() {
                      if (value == true) {
                        _selected.add(item.id);
                      } else {
                        _selected.remove(item.id);
                      }
                    }),
              title: Text(item.title, style: theme.textTheme.bodyMedium),
              subtitle: item.issuerId.isEmpty
                  ? null
                  : Text(
                      item.issuerId,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.accentInk.withValues(alpha: 0.6),
                      ),
                    ),
            ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const ValueKey('portfolio-type'),
          initialValue: _typeId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.d('Soort bewijs'),
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final type in widget.evidenceTypes)
              DropdownMenuItem(value: type.id, child: Text(type.title)),
          ],
          onChanged: _phase == _Phase.sharing
              ? null
              : (value) => setState(() => _typeId = value),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.icon(
              onPressed:
                  _phase == _Phase.sharing ||
                      _selected.isEmpty ||
                      _typeId == null
                  ? null
                  : _share,
              icon: _phase == _Phase.sharing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share_outlined),
              label: Text(l10n.d('Delen als bewijs')),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _phase == _Phase.sharing ? null : _reset,
              child: Text(l10n.t('cancel')),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorText(l10n, _error!),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  String _errorText(AppLocalizations l10n, String error) => switch (error) {
    'no_credentials' => l10n.d('De bron bevat geen leesbare credentials.'),
    'share_failed' => l10n.d(
      'Het delen is mislukt. Controleer de soort bewijs en probeer opnieuw.',
    ),
    _ => l10n.d('Ophalen is mislukt. Controleer de link en probeer opnieuw.'),
  };

  Future<void> _fetchLink() async {
    final url = Uri.tryParse(_linkController.text.trim());
    if (url == null ||
        url.scheme.toLowerCase() != 'https' ||
        url.host.isEmpty) {
      setState(() => _error = 'link_invalid');
      return;
    }
    await _startImport(() async {
      final fetch = widget.fetchDocument;
      if (fetch != null) {
        return portfolioItemsFromJson(await fetch(url));
      }
      return ref.read(ociServeProvider.notifier).fetchPortfolioCredentials(url);
    });
  }

  Future<void> _pickCredentialFile() async {
    await _startImport(() async {
      final custom = widget.pickFile;
      final file = custom != null
          ? await custom()
          : await () async {
              final picked = await FilePicker.pickFiles(
                type: FileType.custom,
                allowedExtensions: const ['json'],
                dialogTitle: context.l10n.d('Credential-bestand kiezen'),
              );
              if (picked.isEmpty) return null;
              return (
                name: picked.first.name,
                bytes: await picked.first.readAsBytes(),
              );
            }();
      if (file == null) return null;
      try {
        return portfolioItemsFromJson(jsonDecode(utf8.decode(file.bytes)));
      } on Object {
        setState(() => _error = 'no_credentials');
        return null;
      }
    });
  }

  /// De import-sessie is het tussenstation: de credentials landen in het
  /// eigen beeld van de cursist, pas bij `select` worden ze gedeeld.
  Future<void> _startImport(
    Future<List<PortfolioImportItemInput>?> Function() load,
  ) async {
    setState(() {
      _phase = _Phase.fetching;
      _error = null;
      _import = null;
      _selected.clear();
      _typeId = null;
      _importKey = const Uuid().v4();
      _shareKey = const Uuid().v4();
    });
    try {
      final items = await load();
      if (!mounted) return;
      if (items == null) {
        setState(() => _phase = _Phase.idle);
        return;
      }
      if (items.isEmpty) {
        setState(() {
          _phase = _Phase.idle;
          _error = 'no_credentials';
        });
        return;
      }
      final notifier = ref.read(ociServeProvider.notifier);
      final importId = await notifier.createPortfolioImport(
        organizationId: widget.organizationId,
        participantId: widget.participantId,
        items: items,
        idempotencyKey: _importKey,
      );
      final session = await notifier.portfolioImport(
        organizationId: widget.organizationId,
        participantId: widget.participantId,
        importId: importId,
      );
      if (!mounted) return;
      setState(() {
        _import = session;
        _phase = _Phase.choosing;
      });
    } catch (error, stack) {
      logError('OciServe: portefeuille ophalen', error.runtimeType, stack);
      if (mounted) {
        setState(() {
          _phase = _Phase.idle;
          _error = 'fetch_failed';
        });
      }
    }
  }

  Future<void> _share() async {
    final session = _import;
    final typeId = _typeId;
    if (session == null || typeId == null || _selected.isEmpty) return;
    setState(() {
      _phase = _Phase.sharing;
      _error = null;
    });
    try {
      await ref
          .read(ociServeProvider.notifier)
          .sharePortfolioItems(
            organizationId: widget.organizationId,
            participantId: widget.participantId,
            importId: session.importId,
            selectedItemIds: _selected.toList(),
            evidenceTypeId: typeId,
            idempotencyKey: _shareKey,
          );
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _import = null;
        _selected.clear();
        _typeId = null;
      });
      widget.onShared();
    } on OciServeException {
      if (mounted) {
        setState(() {
          _phase = _Phase.choosing;
          _error = 'share_failed';
        });
      }
    } catch (error, stack) {
      logError('OciServe: portefeuille delen', error.runtimeType, stack);
      if (mounted) {
        setState(() {
          _phase = _Phase.choosing;
          _error = 'share_failed';
        });
      }
    }
  }

  void _reset() {
    setState(() {
      _phase = _Phase.idle;
      _import = null;
      _selected.clear();
      _typeId = null;
      _error = null;
      _linkController.clear();
    });
  }
}
