import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform, visibleForTesting;
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../services/web_asset_store.dart';
import '../../services/website_style/website_style_proposal.dart';
import '../../services/website_style/website_style_source.dart';
import '../../theme/app_theme.dart';
import '../slides/slide_preview.dart';
import 'hex_color_dialog.dart';
import 'website_style_renderer.dart';

typedef WebsiteStyleSelection = ({
  ThemeProfile profile,
  Map<WebsiteStyleImage, Uint8List> images,
});

typedef WebsiteStyleSave =
    Future<ThemeProfile> Function(WebsiteStyleSelection selection);

class WebsiteStyleDialog extends StatefulWidget {
  const WebsiteStyleDialog({super.key, required this.save, this.lookup});

  final WebsiteStyleSave save;

  @visibleForTesting
  final Future<WebsiteStyleProposal> Function(Uri url)? lookup;

  static bool get supported =>
      !kIsWeb &&
      const {
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.iOS,
        TargetPlatform.android,
      }.contains(defaultTargetPlatform);

  static Future<ThemeProfile?> show(
    BuildContext context, {
    required WebsiteStyleSave save,
  }) => showDialog<ThemeProfile>(
    context: context,
    barrierDismissible: false,
    builder: (_) => WebsiteStyleDialog(save: save),
  );

  @override
  State<WebsiteStyleDialog> createState() => _WebsiteStyleDialogState();
}

class _WebsiteStyleDialogState extends State<WebsiteStyleDialog> {
  final _address = TextEditingController();
  final _name = TextEditingController();
  var _lease = WebAssetStore.lease([]);
  final _assets = <WebsiteStyleImage, ({Uint8List bytes, String path})>{};
  WebsiteStyleSnapshot? _snapshot;
  WebsiteStyleProposal? _proposal;
  ThemeProfile? _profile;
  WebsiteStyleImage? _loadingImage;
  String? _error;
  String? _imageError;
  bool _busy = false;
  bool _saving = false;
  String? _saveError;
  bool _titlePreview = true;
  bool _missingStylesheets = false;

  @override
  void dispose() {
    _address.dispose();
    _name.dispose();
    _lease.release();
    super.dispose();
  }

  Future<void> _analyse() async {
    if (_busy || _saving || _loadingImage != null) return;
    final url = websiteStyleUrl(_address.text);
    if (url == null) {
      setState(() => _error = 'Vul een geldig HTTPS-webadres in.');
      return;
    }
    _lease.release();
    _lease = WebAssetStore.lease([]);
    setState(() {
      _saveError = null;
      _busy = true;
      _error = null;
      _imageError = null;
      _proposal = null;
      _profile = null;
      _assets.clear();
    });
    try {
      if (widget.lookup case final lookup?) {
        final proposal = await lookup(url);
        if (mounted) _showProposal(proposal);
        return;
      }
      final snapshot = await loadWebsiteStyleSnapshot(
        url,
      ).timeout(const Duration(seconds: 26));
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _missingStylesheets = snapshot.incompleteStylesheets;
      });
    } on Exception {
      _analysisFailed();
    }
  }

  void _analysisFailed() {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _snapshot = null;
      _error =
          'De pagina kon niet worden geanalyseerd. Probeer een openbare pagina met zichtbare tekst.';
    });
  }

  void _showProposal(WebsiteStyleProposal proposal) {
    setState(() {
      _busy = false;
      _snapshot = null;
      _proposal = proposal;
      _profile = proposal.profile;
      _name.text = proposal.profile.name;
      _titlePreview = true;
    });
  }

  Future<void> _toggleImage(
    WebsiteStyleImage kind,
    Uri url,
    bool include,
  ) async {
    if (!include) {
      setState(() => _assets.remove(kind));
      return;
    }
    setState(() {
      _loadingImage = kind;
      _imageError = null;
    });
    try {
      final bytes = await loadWebsiteStyleImage(
        url,
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      final path = WebAssetStore.put(bytes, name: 'website-${kind.name}');
      _lease.add(path);
      setState(() {
        _assets[kind] = (bytes: bytes, path: path);
        if (kind != WebsiteStyleImage.logo) {
          _titlePreview = kind == WebsiteStyleImage.title;
        }
      });
    } on Exception {
      if (mounted) {
        setState(
          () => _imageError = 'Deze afbeelding kan niet worden overgenomen.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingImage = null);
    }
  }

  ThemeProfile _previewProfile(ThemeProfile profile) => profile.copyWith(
    logoPath: _assets[WebsiteStyleImage.logo]?.path,
    slideBackgroundImages: {
      'title': ?_assets[WebsiteStyleImage.title]?.path,
      'content': ?_assets[WebsiteStyleImage.content]?.path,
    },
  );

  Future<void> _finish() async {
    final name = _name.text.trim();
    final profile = _profile;
    if (name.isEmpty || profile == null || _loadingImage != null || _saving) {
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final saved = await widget.save((
        profile: profile.copyWith(name: name),
        images: {
          for (final entry in _assets.entries) entry.key: entry.value.bytes,
        },
      ));
      if (mounted) Navigator.pop<ThemeProfile>(context, saved);
    } on Exception {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError =
              'De afbeeldingen konden niet worden bewaard. Probeer opnieuw of laat de afbeeldingen weg.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final snapshot = _snapshot;
    final profile = _profile;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(l10n.d('Stijl overnemen van website')),
        content: SizedBox(
          width: 740,
          child: Stack(
            children: [
              SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.d(
                        'OciDeck leest de CSS en bekijkt hoe de pagina is opgemaakt. Je kunt het voorstel daarna aanpassen.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _address,
                      autofocus: true,
                      enabled: !_busy && !_saving && _loadingImage == null,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _analyse(),
                      decoration: InputDecoration(
                        labelText: l10n.d('Website-URL'),
                        hintText: l10n.d('https://…'),
                        prefixIcon: const Icon(Icons.language),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _busy || _saving || _loadingImage != null
                            ? null
                            : _analyse,
                        icon: const Icon(Icons.search),
                        label: Text(l10n.d('Website analyseren')),
                      ),
                    ),
                    if (_busy) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(
                        l10n.d(
                          snapshot == null
                              ? 'Pagina en stylesheets ophalen…'
                              : 'Toegepaste opmaak uitlezen…',
                        ),
                      ),
                    ],
                    if (_error case final error?)
                      _notice(context, l10n.d(error), isError: true),
                    if (_proposal case final proposal? when profile != null)
                      IgnorePointer(
                        ignoring: _saving,
                        child: _editor(context, profile, proposal),
                      ),
                    if (_saving) const LinearProgressIndicator(),
                    if (_saveError case final error?)
                      _notice(context, l10n.d(error), isError: true),
                  ],
                ),
              ),
              if (snapshot != null)
                Positioned.fill(
                  child: WebsiteStyleRenderer(
                    key: ObjectKey(snapshot),
                    snapshot: snapshot,
                    onResult: _showProposal,
                    onError: _analysisFailed,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(l10n.d('Annuleren')),
          ),
          if (profile != null)
            FilledButton(
              onPressed: _name.text.trim().isEmpty || _loadingImage != null
                  ? null
                  : _finish,
              child: Text(l10n.d('Profiel overnemen')),
            ),
        ],
      ),
    );
  }

  Widget _editor(
    BuildContext context,
    ThemeProfile profile,
    WebsiteStyleProposal proposal,
  ) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        TextField(
          controller: _name,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l10n.d('Naam van stijl'),
            border: const OutlineInputBorder(),
          ),
        ),
        if (_missingStylesheets)
          _notice(
            context,
            l10n.d(
              'Een deel van de CSS was niet beschikbaar. Controleer het voorstel in de voorbeelddia.',
            ),
          ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final preview = _preview(context, profile);
            final controls = _controls(context, profile, proposal);
            return constraints.maxWidth < 620
                ? Column(
                    children: [preview, const SizedBox(height: 16), controls],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: preview),
                      const SizedBox(width: 20),
                      SizedBox(width: 255, child: controls),
                    ],
                  );
          },
        ),
      ],
    );
  }

  Widget _preview(BuildContext context, ThemeProfile profile) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text(l10n.d('Titeldia')),
              selected: _titlePreview,
              onSelected: (_) => setState(() => _titlePreview = true),
            ),
            ChoiceChip(
              label: Text(l10n.d('Inhoudsdia')),
              selected: !_titlePreview,
              onSelected: (_) => setState(() => _titlePreview = false),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SlidePreviewWidget(
            themeProfile: _previewProfile(profile),
            slide: _titlePreview
                ? Slide.create(SlideType.title).copyWith(
                    title: l10n.d('Jouw presentatie'),
                    subtitle: l10n.d('Voorbeeld van de OciDeck-stijl'),
                  )
                : Slide.create(SlideType.bullets).copyWith(
                    title: l10n.d('Voorbeelddia'),
                    bullets: [
                      l10n.d('Kleuren en lettertype'),
                      l10n.d('Ruimte voor je eigen inhoud'),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _controls(
    BuildContext context,
    ThemeProfile profile,
    WebsiteStyleProposal proposal,
  ) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _colorButton(
          'Accentkleur',
          profile.accentColor,
          (value) => profile.copyWith(accentColor: value),
        ),
        if (_accentEvidence(proposal, l10n) case final evidence?)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(evidence, style: Theme.of(context).textTheme.bodySmall),
          ),
        _colorButton(
          'Titeltekstkleur',
          profile.titleTextColor,
          (value) => profile.copyWith(titleTextColor: value),
        ),
        _colorButton(
          'Titelachtergrond',
          profile.titleBackgroundColor,
          (value) => profile.copyWith(
            titleBackgroundColor: value,
            sectionBackgroundColor: value,
          ),
        ),
        _colorButton(
          'Tekstkleur',
          profile.textColor,
          (value) => profile.copyWith(textColor: value, tableTextColor: value),
        ),
        _colorButton(
          'Dia-achtergrond',
          profile.slideBackgroundColor,
          (value) => profile.copyWith(slideBackgroundColor: value),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: profile.fontFamily,
          isExpanded: true,
          decoration: InputDecoration(labelText: l10n.d('Lettertype')),
          items: [
            for (final font in AppSettings.availableFonts)
              DropdownMenuItem(value: font, child: Text(font)),
          ],
          onChanged: (font) => setState(() {
            _profile = profile.copyWith(
              fontFamily: font,
              clearPreferredFontFamily: true,
            );
          }),
        ),
        if (profile.preferredFontFamily case final detected?)
          _notice(
            context,
            l10n
                .d(
                  'Websitelettertype: {font}. De dia toont het gekozen vervangende lettertype.',
                )
                .replaceAll('{font}', detected),
          ),
        if (proposal.images.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final entry in proposal.images.entries)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                l10n.d(switch (entry.key) {
                  WebsiteStyleImage.title => 'Titelachtergrond overnemen',
                  WebsiteStyleImage.content => 'Dia-achtergrond overnemen',
                  WebsiteStyleImage.logo => 'Websitelogo overnemen',
                }),
              ),
              value: _assets.containsKey(entry.key),
              onChanged: _loadingImage == null
                  ? (checked) =>
                        _toggleImage(entry.key, entry.value, checked == true)
                  : null,
            ),
          if (_loadingImage != null) const LinearProgressIndicator(),
          if (_imageError case final error?)
            _notice(context, l10n.d(error), isError: true),
        ],
      ],
    );
  }

  Widget _colorButton(
    String name,
    String value,
    ThemeProfile Function(String) update,
  ) {
    final label = context.l10n.d(name);
    return OutlinedButton.icon(
      onPressed: () async {
        final selected = await HexColorDialog.show(
          context,
          value,
          palette: _proposal?.palette ?? const [],
        );
        if (mounted && selected != null) {
          setState(() => _profile = update(selected));
        }
      },
      icon: Container(
        height: 16,
        width: 16,
        decoration: BoxDecoration(
          color: AppTheme.parseHexColor(value),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      label: Text('$label · $value'),
      style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
    );
  }

  String? _accentEvidence(
    WebsiteStyleProposal proposal,
    AppLocalizations l10n,
  ) {
    if (_profile?.accentColor != proposal.profile.accentColor) return null;
    if (proposal.accentToken case final token?) {
      return l10n
          .d('Komt overeen met CSS-variabele {naam}.')
          .replaceAll('{naam}', token);
    }
    if (proposal.accentRoles.contains('buttons')) {
      return l10n.d('Gebaseerd op de kleuren van knoppen.');
    }
    if (proposal.accentRoles.contains('links')) {
      return l10n.d('Gebaseerd op de kleuren van links.');
    }
    if (proposal.accentRoles.contains('heading')) {
      return l10n.d('Gebaseerd op de kleur van de paginakop.');
    }
    return null;
  }

  Widget _notice(BuildContext context, String text, {bool isError = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Semantics(
          liveRegion: isError,
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isError ? Theme.of(context).colorScheme.error : null,
            ),
          ),
        ),
      );
}
