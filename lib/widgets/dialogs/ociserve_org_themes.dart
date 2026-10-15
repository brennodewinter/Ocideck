import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_theme.dart';
import '../../models/settings.dart';
import '../../services/ociserve/ociserve_http.dart';
import '../../state/ociserve_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_snackbar.dart';
import '../../utils/log.dart';

/// Het themaregister van de organisatie (#2429): het huidige stijlprofiel
/// delen en profielen van de organisatie ophalen als lokale kopie. Alles
/// hier is een bewuste handeling — OciDeck deelt nooit zelfstandig.
///
/// De `definition` is ondoorzichtige ThemeProfile-JSON: we tonen hem
/// letterlijk voor bevestiging, want precies dát stuurt de server door naar
/// Keiko's themakiezer.
class OciServeOrgThemes extends ConsumerStatefulWidget {
  const OciServeOrgThemes({
    super.key,
    required this.current,
    required this.onAdopt,
  });

  /// Het profiel zoals het nu in de stijleditor staat.
  final ThemeProfile current;

  /// Neemt een server-definitie over als lokale werkkopie in de editor.
  final void Function(ThemeProfile profile) onAdopt;

  static Future<void> show(
    BuildContext context, {
    required ThemeProfile current,
    required void Function(ThemeProfile profile) onAdopt,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
          child: OciServeOrgThemes(current: current, onAdopt: onAdopt),
        ),
      ),
    );
  }

  @override
  ConsumerState<OciServeOrgThemes> createState() => _OciServeOrgThemesState();
}

class _OciServeOrgThemesState extends ConsumerState<OciServeOrgThemes> {
  /// Defensieve begrenzing op de definitie die we versturen; een profiel is
  /// normaal enkele kB, dus dit raakt geen echte invoer.
  static const _definitionCap = 256 * 1024;

  String? _organizationId;
  List<OciServeTheme>? _themes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final memberships = ref.read(ociServeProvider).memberships;
    _organizationId = memberships.isEmpty
        ? null
        : memberships.first.organizationId;
    Future<void>.microtask(_load);
  }

  String? _definition() {
    final encoded = utf8.encode(jsonEncode(widget.current.toJson()));
    if (encoded.length > _definitionCap) return null;
    return jsonEncode(widget.current.toJson());
  }

  Future<void> _load() async {
    final org = _organizationId;
    if (org == null) return;
    try {
      final themes = await ref
          .read(ociServeProvider.notifier)
          .organizationThemes(org);
      if (!mounted) return;
      setState(() => _themes = themes);
    } catch (error, stack) {
      logError('OciServe: themas laden', error.runtimeType, stack);
      if (mounted) {
        showErrorSnackBar(
          ScaffoldMessenger.of(context),
          context.l10n,
          context.l10n.d(
            'De thema’s van de organisatie konden niet worden opgehaald.',
          ),
        );
      }
    }
  }

  /// Bevestigt wat er naartoe gaat (naam + volledige definitie) en deelt het
  /// profiel. Een naam-conflict wordt een bijwerk-voorstel; een ETag-conflict
  /// wordt een keuze tussen overschrijven en overnemen — nooit stil.
  Future<void> _share() async {
    final l10n = context.l10n;
    final org = _organizationId;
    final definition = _definition();
    if (org == null) return;
    if (definition == null) {
      showErrorSnackBar(
        ScaffoldMessenger.of(context),
        l10n,
        l10n.d('Dit stijlprofiel is te groot om te delen.'),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.d('Stijlprofiel delen met de organisatie?')),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n
                      .d('“{naam}” wordt zichtbaar voor uw organisatie.')
                      .replaceAll('{naam}', widget.current.name),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.d('Dit is de volledige definitie die meegaat:'),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      dialogContext,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    const JsonEncoder.withIndent(
                      '  ',
                    ).convert(widget.current.toJson()),
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.d('Delen')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(ociServeProvider.notifier)
          .shareTheme(
            organizationId: org,
            name: widget.current.name,
            definition: widget.current.toJson(),
          );
      if (!mounted) return;
      unawaited(_load());
    } on OciServeException catch (e) {
      if (e.statusCode == 409) {
        // De naam bestaat al op de server: bied bijwerken aan.
        await _resolveNameConflict(org, definition);
      } else if (mounted) {
        showErrorSnackBar(
          ScaffoldMessenger.of(context),
          context.l10n,
          _errorText(context.l10n, e),
        );
      }
    } catch (error, stack) {
      logError('OciServe: thema delen', error.runtimeType, stack);
      if (mounted) {
        showErrorSnackBar(
          ScaffoldMessenger.of(context),
          context.l10n,
          context.l10n.d('Delen is niet gelukt. Probeer het opnieuw.'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Naam-conflict op de POST: haal dat server-thema met ETag op en werk het
  /// bij met `If-Match`. Een 409 daarop betekent dat iemand anders intussen
  /// schreef — dan kiest de gebruiker expliciet.
  Future<void> _resolveNameConflict(String org, String definition) async {
    final l10n = context.l10n;
    final name = widget.current.name;
    final themes =
        _themes ??
        await ref.read(ociServeProvider.notifier).organizationThemes(org);
    OciServeTheme? existing;
    for (final theme in themes) {
      if (theme.name == name) existing = theme;
    }
    if (!mounted || existing == null) {
      if (mounted) {
        showErrorSnackBar(
          ScaffoldMessenger.of(context),
          l10n,
          l10n.d('Er bestaat al een thema met deze naam bij de organisatie.'),
        );
      }
      return;
    }
    final overwrite = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.d('Naam is al in gebruik')),
        content: Text(
          l10n
              .d(
                'Uw organisatie heeft al een thema “{naam}”. Wilt u dat thema bijwerken met uw versie?',
              )
              .replaceAll('{naam}', name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.d('Bijwerken')),
          ),
        ],
      ),
    );
    if (overwrite != true || !mounted) return;
    try {
      final detail = await ref
          .read(ociServeProvider.notifier)
          .organizationTheme(organizationId: org, themeId: existing.id);
      await ref
          .read(ociServeProvider.notifier)
          .updateOrganizationTheme(
            organizationId: org,
            themeId: existing.id,
            name: name,
            definition: widget.current.toJson(),
            ifMatch: detail.etag ?? '*',
          );
      if (mounted) unawaited(_load());
    } on OciServeException catch (e) {
      if (e.statusCode == 409 && mounted) {
        await _resolveEtagConflict(org, existing.id);
      } else if (mounted) {
        showErrorSnackBar(
          ScaffoldMessenger.of(context),
          l10n,
          _errorText(l10n, e),
        );
      }
    } catch (error, stack) {
      logError('OciServe: thema bijwerken', error.runtimeType, stack);
      if (mounted) {
        showErrorSnackBar(
          ScaffoldMessenger.of(context),
          context.l10n,
          context.l10n.d('Bijwerken is niet gelukt. Probeer het opnieuw.'),
        );
      }
    }
  }

  /// De serverversie veranderde onder de hand: overschrijven (`If-Match: *`)
  /// of de serverversie als lokale kopie overnemen.
  Future<void> _resolveEtagConflict(String org, String themeId) async {
    final l10n = context.l10n;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.d('Tussendoor gewijzigd')),
        content: Text(
          l10n.d(
            'Iemand anders heeft dit thema net aangepast. Overschrijven, of de versie van de organisatie overnemen?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'adopt'),
            child: Text(l10n.d('Serverversie overnemen')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'overwrite'),
            child: Text(l10n.d('Overschrijven')),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    try {
      final detail = await ref
          .read(ociServeProvider.notifier)
          .organizationTheme(organizationId: org, themeId: themeId);
      if (choice == 'adopt') {
        widget.onAdopt(ThemeProfile.fromJson(detail.theme.definition));
        if (mounted) Navigator.pop(context);
        return;
      }
      await ref
          .read(ociServeProvider.notifier)
          .updateOrganizationTheme(
            organizationId: org,
            themeId: themeId,
            name: widget.current.name,
            definition: widget.current.toJson(),
            ifMatch: '*',
          );
      if (mounted) unawaited(_load());
    } catch (error, stack) {
      logError('OciServe: thema-conflict oplossen', error.runtimeType, stack);
      if (mounted) {
        showErrorSnackBar(
          ScaffoldMessenger.of(context),
          context.l10n,
          context.l10n.d('De wijziging is niet gelukt. Probeer het opnieuw.'),
        );
      }
    }
  }

  Future<void> _adopt(OciServeTheme theme) async {
    try {
      widget.onAdopt(ThemeProfile.fromJson(theme.definition));
      if (mounted) Navigator.pop(context);
    } catch (error, stack) {
      logError('OciServe: thema overnemen', error.runtimeType, stack);
      if (mounted) {
        showErrorSnackBar(
          ScaffoldMessenger.of(context),
          context.l10n,
          context.l10n.d(
            'Dit thema kon niet worden overgenomen — het formaat klopt niet.',
          ),
        );
      }
    }
  }

  Future<void> _delete(OciServeTheme theme) async {
    final l10n = context.l10n;
    final org = _organizationId;
    if (org == null) return;
    try {
      await ref
          .read(ociServeProvider.notifier)
          .deleteOrganizationTheme(organizationId: org, themeId: theme.id);
      if (mounted) unawaited(_load());
    } on OciServeException catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        ScaffoldMessenger.of(context),
        l10n,
        e.statusCode == 409
            ? l10n.d(
                'Dit thema is ingebouwd of in gebruik door een cursus en kan niet worden verwijderd.',
              )
            : _errorText(l10n, e),
      );
    } catch (error, stack) {
      logError('OciServe: thema verwijderen', error.runtimeType, stack);
      if (mounted) {
        showErrorSnackBar(
          ScaffoldMessenger.of(context),
          context.l10n,
          context.l10n.d('Verwijderen is niet gelukt. Probeer het opnieuw.'),
        );
      }
    }
  }

  String _errorText(AppLocalizations l10n, OciServeException e) =>
      e.statusCode == 403
      ? l10n.d('Uw account mag geen thema’s beheren bij deze organisatie.')
      : l10n.d('De actie is niet gelukt. Probeer het opnieuw.');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = AppPalette.of(Theme.of(context));
    final memberships = ref.watch(ociServeProvider).memberships;
    final themes = _themes;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.style_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.d('Thema’s van de organisatie'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.t('cancel'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (memberships.length > 1) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _organizationId,
              decoration: InputDecoration(
                labelText: l10n.d('Organisatie'),
                isDense: true,
              ),
              items: [
                for (final membership in memberships)
                  DropdownMenuItem(
                    value: membership.organizationId,
                    child: Text(membership.name),
                  ),
              ],
              onChanged: (value) => setState(() {
                _organizationId = value;
                _themes = null;
                _load();
              }),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _share,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_outlined, size: 18),
            label: Text(
              l10n
                  .d('“{naam}” delen met de organisatie')
                  .replaceAll('{naam}', widget.current.name),
            ),
          ),
          const SizedBox(height: 14),
          if (themes == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (themes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                l10n.d('De organisatie heeft nog geen eigen thema’s.'),
                style: TextStyle(color: palette.mutedText, fontSize: 12.5),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: themes.length,
                itemBuilder: (context, index) {
                  final theme = themes[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(theme.name),
                    subtitle: theme.isBuiltin
                        ? Text(
                            l10n.d('Ingebouwd'),
                            style: const TextStyle(fontSize: 11),
                          )
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => _adopt(theme),
                          child: Text(l10n.d('Overnemen')),
                        ),
                        if (!theme.isBuiltin)
                          IconButton(
                            tooltip: l10n.d('Verwijderen bij de organisatie'),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => _delete(theme),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
