part of 'slide_list_panel.dart';

/// Lower-cased, concatenated text of a slide for searching. Kept broad on
/// purpose: everything you typed into the slide should make it findable.
String _slideText(Slide slide) {
  return [
    slide.title,
    slide.subtitle,
    ...slide.bullets,
    ...slide.bullets2,
    slide.quote,
    slide.quoteAuthor,
    slide.customMarkdown,
    slide.imageCaption,
    slide.imageCaption2,
    slide.notes,
    slide.imagePath,
    slide.imagePath2,
    slide.videoPath,
    slide.videoCaptions,
    slide.audioPath,
    slide.type.label,
  ].join(' ').toLowerCase();
}

/// Multi-word AND match: every term must appear somewhere in the slide.
bool _matches(Slide slide, String query) {
  final text = _slideText(slide);
  return query
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .every(text.contains);
}
