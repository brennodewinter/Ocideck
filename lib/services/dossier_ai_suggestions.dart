import 'dart:convert';
import 'dart:io';

import 'package:characters/characters.dart';

import '../models/deck.dart';
import '../models/document_dossier.dart';
import '../models/slide.dart';
import 'ai_client_service.dart';
import 'ai_security_gate.dart';
import 'document_dossier_store.dart';
import 'privacy/privacy_own_identity.dart';
import 'privacy/privacy_projection.dart';

/// A reviewable draft. The service never changes the dossier or its sources.
class DossierAiSuggestion {
  const DossierAiSuggestion({
    this.title = '',
    this.description = '',
    this.documentDate = '',
    this.author = '',
  });

  final String title;
  final String description;
  final String documentDate;
  final String author;

  bool get isEmpty =>
      title.isEmpty &&
      description.isEmpty &&
      documentDate.isEmpty &&
      author.isEmpty;
}

/// Reads at most this many UTF-8 bytes from one original Markdown document.
const kDossierAiMaxSourceBytes = 16000;

class DossierAiSuggestionsService {
  const DossierAiSuggestionsService(this._client, this._store);

  final AiClientService _client;
  final DocumentDossierStore _store;

  /// Called only for an explicit user request. The client gate is checked before
  /// reading the source; the same gate is checked again before network egress.
  Future<DossierAiSuggestion?> suggest(
    DossierEntry entry, {
    required String languageName,
    Set<String> disabledRules = const {},
    OwnIdentity ownIdentity = OwnIdentity.empty,
  }) async {
    final gate = _client.gate();
    if (gate is AiGateDeny) throw AiGateException(gate.reason);

    final sourcePath = await _store.resolvedPath(entry);
    if (sourcePath == null || !sourcePath.toLowerCase().endsWith('.md')) {
      throw const FileSystemException('Geen veilig Markdown-brondocument');
    }
    final file = File(sourcePath);
    if (await file.length() > kDossierAiMaxSourceBytes) {
      // Avoid silently summarising only the beginning as though it were the
      // whole document. The user can shorten the source explicitly.
      throw const FileSystemException(
        'Document is te groot voor AI-voorstellen',
      );
    }
    final source = await file.readAsString(encoding: utf8);
    final projected = PrivacyProjection.forExternalProcessing(
      Deck(
        title: '',
        slides: [
          Slide.create(SlideType.bullets).copyWith(customMarkdown: source),
        ],
      ),
      disabledRules: disabledRules,
      ownIdentity: ownIdentity,
    ).deck.slides.single.customMarkdown;
    if (projected.trim().isEmpty) return null;

    final raw = await _client.suggest(
      context: projected,
      instruction:
          'Suggest metadata for this Markdown document in $languageName. '
          'Return ONLY one JSON object with string keys title, description, '
          'documentDate, author. The description must be short (one sentence). '
          'Use an ISO calendar date YYYY-MM-DD only when explicitly present '
          'in the source. Use an author only when explicitly attributed in the '
          'source. Use an empty string for unknown values. Do not include '
          'redacted values or infer identities.',
      maxTokens: 320,
    );
    final suggestion = parseDossierAiSuggestion(raw, projected);
    return suggestion.isEmpty ? null : suggestion;
  }
}

/// Fail closed for unknown identity/date: only literal source evidence is kept.
DossierAiSuggestion parseDossierAiSuggestion(String raw, String source) {
  var value = raw.trim();
  if (value.startsWith('```')) {
    value = value.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
    value = value.replaceFirst(RegExp(r'\s*```$'), '');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(value);
  } on FormatException {
    return const DossierAiSuggestion();
  }
  if (decoded is! Map<String, dynamic>) return const DossierAiSuggestion();
  final data = decoded;
  String field(String key, int maxLength) {
    final candidate = data[key];
    if (candidate is! String) return '';
    return candidate
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .characters
        .take(maxLength)
        .toString();
  }

  final date = field('documentDate', 10);
  final parsedDate = DateTime.tryParse(date);
  final validDate =
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) &&
      parsedDate != null &&
      parsedDate.toIso8601String().startsWith(date) &&
      source.contains(date);
  final author = field('author', 120);
  return DossierAiSuggestion(
    title: field('title', 160),
    description: field('description', 360),
    documentDate: validDate ? date : '',
    author:
        author.isNotEmpty && source.contains(author) && !author.contains('█')
        ? author
        : '',
  );
}
