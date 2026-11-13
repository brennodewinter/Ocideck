import 'package:flutter/services.dart';

import '../models/document_template.dart';

/// Loads a document template in an explicitly selected content language.
class DocumentTemplateService {
  DocumentTemplateService({Future<String> Function(String)? loadAsset})
    : _loadAsset = loadAsset ?? rootBundle.loadString;

  final Future<String> Function(String) _loadAsset;

  Future<String> load(DocumentTemplate template, String language) async {
    if (template == DocumentTemplate.empty) return '';
    final lang = DocumentTemplate.languages.contains(language)
        ? language
        : 'en';
    return _loadAsset('assets/document_templates/${template.name}.$lang.md');
  }
}
