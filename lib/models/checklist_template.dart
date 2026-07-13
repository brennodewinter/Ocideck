import 'dart:convert';

import '../utils/log.dart';

/// One test entry in a reusable [ChecklistTemplate]: a stable [id]
/// (e.g. `WSTG-ATHN-07` or a custom code), the [title] shown in the checklist,
/// and an optional [category] for grouping. Mirrors [WstgTest] but is
/// user-authored and stored in the settings, not bundled.
class ChecklistTemplateItem {
  final String id;
  final String title;
  final String category;

  const ChecklistTemplateItem({
    required this.id,
    required this.title,
    this.category = '',
  });

  ChecklistTemplateItem copyWith({
    String? id,
    String? title,
    String? category,
  }) => ChecklistTemplateItem(
    id: id ?? this.id,
    title: title ?? this.title,
    category: category ?? this.category,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    if (category.isNotEmpty) 'category': category,
  };

  factory ChecklistTemplateItem.fromJson(Map<String, Object?> json) =>
      ChecklistTemplateItem(
        id: (json['id'] as String?)?.trim() ?? '',
        title: (json['title'] as String?)?.trim() ?? '',
        category: (json['category'] as String?)?.trim() ?? '',
      );
}

/// A user-created, reusable checklist (feedback #9): a [name] the user picks it
/// by, an optional [standardLabel] that lands on the checklist slide when the
/// template is applied, and its [items]. Stored in the app settings as JSON (one
/// `customChecklists` prefs key), so it can be loaded into any `checklist` slide
/// — like the bundled WSTG list — and selected per scope object.
///
/// Kept Flutter-free (like [LibraryFolder]) so the persisted form is decoupled
/// from the UI: the model round-trips through `toJson`/`fromJson` and the
/// `encodeList`/`decodeList` prefs helpers.
class ChecklistTemplate {
  final String name;
  final String standardLabel;
  final List<ChecklistTemplateItem> items;

  const ChecklistTemplate({
    required this.name,
    this.standardLabel = '',
    this.items = const [],
  });

  ChecklistTemplate copyWith({
    String? name,
    String? standardLabel,
    List<ChecklistTemplateItem>? items,
  }) => ChecklistTemplate(
    name: name ?? this.name,
    standardLabel: standardLabel ?? this.standardLabel,
    items: items ?? this.items,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'standardLabel': standardLabel,
    'items': [for (final i in items) i.toJson()],
  };

  factory ChecklistTemplate.fromJson(Map<String, Object?> json) {
    final rawItems = json['items'];
    return ChecklistTemplate(
      name: (json['name'] as String?)?.trim() ?? '',
      standardLabel: (json['standardLabel'] as String?)?.trim() ?? '',
      items: [
        if (rawItems is List)
          for (final item in rawItems)
            if (item is Map)
              ChecklistTemplateItem.fromJson(Map<String, Object?>.from(item)),
      ].where((i) => i.id.isNotEmpty || i.title.isNotEmpty).toList(),
    );
  }

  /// Serialise a list for the prefs domain.
  static String encodeList(List<ChecklistTemplate> templates) =>
      jsonEncode([for (final t in templates) t.toJson()]);

  /// Read a list back; an unreadable value yields an empty list, and templates
  /// without a name drop out (a nameless template cannot be selected).
  static List<ChecklistTemplate> decodeList(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map)
            ChecklistTemplate.fromJson(Map<String, Object?>.from(item)),
      ].where((t) => t.name.isNotEmpty).toList();
    } catch (e) {
      logWarning('ChecklistTemplate.decodeList: onleesbare sjablonenlijst', e);
      return const [];
    }
  }
}
