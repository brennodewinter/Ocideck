import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/ai_client_service.dart';
import '../../services/ai_security_gate.dart';
import '../../services/image_alt_ai_service.dart';
import '../../services/secret_store.dart';
import '../../state/consent_provider.dart';
import '../../state/deck_provider.dart';
import '../../state/image_privacy_provider.dart';
import '../../state/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';
import '../dialogs/ai_image_outbound_dialog.dart';
import 'editor_text_controller.dart';

/// A per-usage alt-text field (WCAG 1.1.1). The value lives on the slide
/// ([Slide.imageAltText]) and travels in the `.md` — no sidecar. When
/// [onSuggested] is set and the optional AI backend is on, a **Suggest alt-text**
/// button drafts one via a local vision model (AI_ASSIST §6): draft-only, never
/// overwriting a non-empty human alt without a confirm.
class AltTextField extends ConsumerStatefulWidget {
  final String altText;
  final String imagePath;
  final String? captionBasePath;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSuggested;

  /// Whether the current alt-text is an unreviewed AI draft (its provenance
  /// marker is set). Shows a badge + a "reviewed" action.
  final bool isAiDraft;

  /// Marks the current AI draft as reviewed — clears the provenance marker
  /// without changing the text (so it survives "clear AI alt-texts" and no longer
  /// blocks sealing).
  final VoidCallback? onAccepted;

  const AltTextField({
    super.key,
    required this.altText,
    required this.imagePath,
    required this.captionBasePath,
    required this.onChanged,
    this.onSuggested,
    this.isAiDraft = false,
    this.onAccepted,
  });

  @override
  ConsumerState<AltTextField> createState() => _AltTextFieldState();
}

class _AltTextFieldState extends ConsumerState<AltTextField> {
  late final EditorTextController _ctrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctrl = EditorTextController(text: widget.altText)
      ..addTextListener(_onEdited);
  }

  // Only user keystrokes reach this: external changes resync with the listener
  // detached (see [didUpdateWidget]), so an AI draft never looks like a manual
  // edit (which would clear the AI-provenance marker).
  void _onEdited() => widget.onChanged(_ctrl.text);

  @override
  void didUpdateWidget(AltTextField old) {
    super.didUpdateWidget(old);
    if (widget.altText != _ctrl.text) {
      _ctrl.removeTextListener(_onEdited);
      _ctrl.text = widget.altText;
      _ctrl.addTextListener(_onEdited);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _aiAvailable {
    if (widget.onSuggested == null) return false;
    final ai = ref.watch(settingsProvider).aiSettings;
    return ai.enabled && ai.isConfigured;
  }

  Future<void> _suggest() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    void toast(String msg) =>
        messenger.showSnackBar(SnackBar(content: Text(msg)));
    setState(() => _busy = true);
    try {
      final bytes = await ref
          .read(imageServiceProvider)
          .readSlideImageBytes(
            widget.imagePath,
            projectPath: widget.captionBasePath,
          );
      if (bytes == null) {
        toast(l10n.d('Kon de afbeelding niet lezen voor AI-analyse.'));
        return;
      }
      final settings = ref.read(settingsProvider).aiSettings;
      // Vóór de bytes het apparaat verlaten: zeggen wát er weggaat en waarheen.
      // Een afbeelding kan niet door de projectie — die vervangt tekens, en in
      // een JPEG staan er geen. Wat overblijft is toestemming met kennis van
      // zaken, per beeld. Zonder dit stuurde één klik een schermafdruk van een
      // beheerpaneel of een groepsfoto naar een derde partij, in een app
      // waarvan de belofte begint met "het blijft op dit apparaat".
      final faces = await _countFaces(bytes);
      if (!mounted) return;
      final go = await confirmAiImageOutbound(
        context,
        title: l10n.d('Deze afbeelding naar het AI-model sturen?'),
        settings: settings,
        imageCount: 1,
        faceCount: faces,
      );
      if (!go || !mounted) return;
      final client = AiClientService(
        settings: settings,
        hasOutboundConsent: ref.read(consentProvider).hasAccepted,
        apiKey: await SecretStore().readAiApiKey(settings.baseUrl),
      );
      final draft = await ImageAltAiService(client).suggestAltText(
        imageBytes: bytes,
        languageName:
            AppLocalizations.languageNames[l10n.languageCode] ?? 'English',
      );
      if (!mounted) return;
      if (draft.isEmpty) {
        toast(l10n.d('Het model gaf geen alt-tekst terug.'));
        return;
      }
      if (_ctrl.text.trim().isNotEmpty) {
        final ok = await _confirmReplace(l10n);
        if (ok != true || !mounted) return;
      }
      widget.onSuggested!(draft);
    } on AiGateException {
      toast(
        l10n.d(
          'AI-assistentie is niet beschikbaar. Controleer de instellingen.',
        ),
      );
    } on AiRequestException {
      toast(
        l10n.d(
          'De AI-aanroep is mislukt (model niet geladen of server onbereikbaar).',
        ),
      );
    } catch (e, s) {
      logError('AltTextField._suggest', e, s);
      toast(
        l10n.d(
          'De AI-aanroep is mislukt (model niet geladen of server onbereikbaar).',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Hoeveel herkenbare gezichten de beeldcontrole hier ziet, of 0 wanneer er
  /// niet gekeken kon worden.
  ///
  /// Nul betekent dus twee dingen tegelijk, en dat is met opzet niet weggepoetst:
  /// de dialoog toont bij nul géén regel over gezichten, in plaats van te
  /// beweren dat er niemand op staat. "Wij vonden niets" en "hier is niet
  /// gekeken" mogen nooit hetzelfde lezen — dezelfde regel als in
  /// `image_face_scan.dart`.
  ///
  /// Faalt de controle, dan gaat de bevestiging gewoon door zónder de
  /// gezichtsregel: een kapotte detector mag de gebruiker niet blokkeren, en de
  /// hoofdwaarschuwing (er gaat een ongewijzigde afbeelding naar buiten) staat
  /// er hoe dan ook.
  Future<int> _countFaces(Uint8List bytes) async {
    try {
      final scanner = await ref.read(imageFaceScannerProvider);
      if (!scanner.isSupported) return 0;
      final result = await scanner.countFaces(bytes);
      return result.readable ? result.faces : 0;
    } catch (e, s) {
      logError('AltTextField._countFaces', e, s);
      return 0;
    }
  }

  Future<bool?> _confirmReplace(AppLocalizations l10n) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(
        l10n.d('Er staat al alt-tekst. Vervangen door het AI-concept?'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.d('Vervangen')),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _ctrl,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: l10n.d('Alt-tekst (beschrijving voor schermlezers)'),
            hintStyle: const TextStyle(fontSize: 12, color: AppTheme.blueGray2),
            prefixIcon: Icon(
              Icons.accessibility_new_outlined,
              size: 16,
              color: AppTheme.slate500,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 10,
            ),
            filled: true,
            fillColor: AppTheme.slate50,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: AppTheme.slate300),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: AppTheme.slate300),
            ),
          ),
          style: const TextStyle(fontSize: 12),
        ),
        if (widget.isAiDraft) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 12,
                      color: AppTheme.accentFg,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.d('AI-concept'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accentFg,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (widget.onAccepted != null)
                TextButton.icon(
                  onPressed: widget.onAccepted,
                  icon: const Icon(Icons.check, size: 15),
                  label: Text(
                    l10n.d('Nagekeken'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
        if (_aiAvailable) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _suggest,
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_outlined, size: 16),
              label: Text(
                _busy
                    ? l10n.d('Bezig met AI-analyse…')
                    : l10n.d('Stel alt-tekst voor (AI)'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
