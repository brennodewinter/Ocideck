// Kiest de platformhelft van de OpenKAT-import (#767): echte mapscan op
// desktop, een lege romp op web — zelfde patroon als draft_store_factory.
export 'openkat_import_action_web.dart'
    if (dart.library.io) 'openkat_import_action_io.dart';
