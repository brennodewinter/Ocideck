/// Built-in document starting points. Forms use the ordinary fill and export flow.
enum DocumentTemplate {
  empty('Leeg document'),
  cpe('PE-bewijs'),
  recipe('Receptinzending');

  const DocumentTemplate(this.label);
  final String label;

  static const languages = ['nl', 'en'];
}
