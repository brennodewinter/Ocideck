import 'package:flutter/material.dart';
import '../../models/slide.dart';
import '../../models/video_source.dart';
import '../../services/image_service.dart';
import '../../l10n/app_localizations.dart';
import '../slides/video_playhead_bus.dart';
import '_editor_field.dart';
import 'advanced_section.dart';
import 'audio_attachment_editor.dart';
import '../../theme/app_theme.dart';

class VideoSlideEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final ImageService imageService;
  final String? projectPath;
  final bool nestedInScrollView;

  /// Knip de video op het meegegeven tijdstip (ms) in twee slides. Null = de
  /// editor kan niet knippen (geen deck-context).
  final void Function(int atMs)? onSplit;

  const VideoSlideEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    required this.imageService,
    this.projectPath,
    this.nestedInScrollView = false,
    this.onSplit,
  });

  @override
  State<VideoSlideEditor> createState() => _VideoSlideEditorState();
}

class _VideoSlideEditorState extends State<VideoSlideEditor> {
  late final TextEditingController _title;
  late final TextEditingController _source;
  late final TextEditingController _start;
  late final TextEditingController _end;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.slide.title)
      ..addListener(_emitTitle);
    _source = TextEditingController(text: widget.slide.videoPath);
    _start = TextEditingController(text: _secText(widget.slide.videoStartMs));
    _end = TextEditingController(text: _secText(widget.slide.videoEndMs));
  }

  @override
  void didUpdateWidget(VideoSlideEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Houd de velden in sync als de slide van buitenaf wijzigt (bv. na knippen).
    if (oldWidget.slide.videoPath != widget.slide.videoPath &&
        _source.text != widget.slide.videoPath) {
      _source.text = widget.slide.videoPath;
    }
    if (oldWidget.slide.videoStartMs != widget.slide.videoStartMs &&
        _parseSec(_start.text) != widget.slide.videoStartMs) {
      _start.text = _secText(widget.slide.videoStartMs);
    }
    if (oldWidget.slide.videoEndMs != widget.slide.videoEndMs &&
        _parseSec(_end.text) != widget.slide.videoEndMs) {
      _end.text = _secText(widget.slide.videoEndMs);
    }
  }

  static String _secText(int ms) =>
      ms <= 0 ? '' : (ms / 1000).toStringAsFixed(0);
  static int _parseSec(String text) {
    final v = double.tryParse(text.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) return 0;
    return (v * 1000).round();
  }

  void _emitTitle() =>
      widget.onUpdate(widget.slide.copyWith(title: _title.text));

  void _emitSource() {
    widget.onUpdate(widget.slide.copyWith(videoPath: _source.text.trim()));
    setState(() {}); // werk de bron-chip bij
  }

  void _emitTrim() {
    widget.onUpdate(
      widget.slide.copyWith(
        videoStartMs: _parseSec(_start.text),
        videoEndMs: _parseSec(_end.text),
      ),
    );
  }

  Future<void> _pickVideo() async {
    final path = await widget.imageService.pickVideo(
      projectPath: widget.projectPath,
    );
    if (path != null) {
      _source.text = path;
      widget.onUpdate(widget.slide.copyWith(videoPath: path));
      setState(() {});
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _source.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final source = VideoSource.parse(widget.slide.videoPath);
    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(
          label: 'Titel (optioneel)',
          controller: _title,
          hint: 'Titel boven de video',
          maxLines: 2,
          qualityField: 'title',
        ),
        const SizedBox(height: 16),
        const SectionLabel('Video'),
        // Bron: lokaal bestand of een online URL (direct .mp4/.mov, of een
        // YouTube/Vimeo-link).
        TextField(
          controller: _source,
          onChanged: (_) => _emitSource(),
          decoration: InputDecoration(
            isDense: true,
            hintText: l10n.d('Bestandspad of URL (YouTube, Vimeo, .mp4 …)'),
            border: const OutlineInputBorder(),
          ),
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _SourceKindChip(source: source),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(Icons.movie_outlined, size: 16),
              label: Text(l10n.d('Bestand kiezen')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          child: CheckboxListTile(
            value: widget.slide.videoAutoplay,
            onChanged: (value) => widget.onUpdate(
              widget.slide.copyWith(videoAutoplay: value ?? false),
            ),
            title: Text(l10n.d('Video automatisch afspelen')),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
        const SizedBox(height: 16),
        // Knippen en audio-bijsluiting zijn verdieping; ingeklapt tenzij er
        // al een knippunt of audiobestand op deze slide staat.
        AdvancedSection(
          title: l10n.d('Knippen en audio'),
          initiallyExpanded:
              widget.slide.videoStartMs > 0 ||
              widget.slide.videoEndMs > 0 ||
              widget.slide.audioPath.isNotEmpty,
          children: [
            const SectionLabel('Knippen'),
            Text(
              // eén regel: de l10n-test leest de brontekst, niet de runtime-waarde.
              l10n.d(
                'Speel het segment van deze slide af in het voorbeeld en knip op het punt waar je wilt splitsen: het tweede deel komt op een nieuwe slide.',
              ),
              style: TextStyle(fontSize: 11, color: AppTheme.slate500),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _start,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _emitTrim(),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: l10n.d('Begin (sec)'),
                      border: const OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _end,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _emitTrim(),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: l10n.d('Einde (sec)'),
                      hintText: l10n.d('einde'),
                      border: const OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _CutHereButton(slideId: widget.slide.id, onSplit: widget.onSplit),
            const SizedBox(height: 16),
            AudioAttachmentEditor(
              slide: widget.slide,
              imageService: widget.imageService,
              onUpdate: widget.onUpdate,
            ),
          ],
        ),
      ],
    );
  }
}

/// Knop die op het live afspeelpunt (uit [VideoPlayheadBus]) de video knipt. Is
/// uitgeschakeld zolang er geen video speelt op deze slide; toont dan een hint.
class _CutHereButton extends StatelessWidget {
  final String slideId;
  final void Function(int atMs)? onSplit;

  const _CutHereButton({required this.slideId, required this.onSplit});

  static String _fmt(int ms) {
    final s = (ms / 1000).round();
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<VideoPlayhead?>(
      valueListenable: VideoPlayheadBus.current,
      builder: (context, playhead, _) {
        final posMs = (playhead != null && playhead.slideId == slideId)
            ? playhead.positionMs
            : null;
        final canCut = posMs != null && posMs > 0 && onSplit != null;
        return Tooltip(
          message: canCut
              ? l10n.d('Knip de video op het huidige afspeelpunt')
              : l10n.d('Speel de video eerst af in het voorbeeld'),
          child: ElevatedButton.icon(
            onPressed: canCut ? () => onSplit!(posMs) : null,
            icon: const Icon(Icons.content_cut, size: 16),
            label: Text(
              posMs != null && posMs > 0
                  ? '${l10n.d('Knip hier')} (${_fmt(posMs)})'
                  : l10n.d('Knip hier'),
            ),
          ),
        );
      },
    );
  }
}

class _SourceKindChip extends StatelessWidget {
  final VideoSource source;

  const _SourceKindChip({required this.source});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // De chip zegt wélke soort bron dit is, niet dat er iets mis is. YouTube
    // kreeg eerder het rode danger-token: een geldige YouTube-link zag er dan
    // uit als een fout, náást een kwaliteitspaneel waar rood écht "fout"
    // betekent. Een online bron is een online bron — teal, net als de andere.
    final (label, color) = switch (source.kind) {
      VideoSourceKind.youtube => ('YouTube', AppTheme.teal),
      VideoSourceKind.vimeo => ('Vimeo', AppTheme.cyan),
      VideoSourceKind.remoteFile => (l10n.d('Online'), AppTheme.teal),
      VideoSourceKind.localFile => (
        l10n.d('Lokaal bestand'),
        AppTheme.slate500,
      ),
      VideoSourceKind.none => (l10n.d('Geen video'), AppTheme.slate400),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
