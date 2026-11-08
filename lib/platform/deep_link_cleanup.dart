import 'deep_link_cleanup_io.dart'
    if (dart.library.js_interop) 'deep_link_cleanup_web.dart'
    as impl;

/// Zet de adresbalk van de browser op [uri] zonder te herladen
/// (`history.replaceState`). De shell roept dit nadat een `?deck=`-deeplink
/// is afgehandeld: de parameter bleef staan en een herlading opende stil
/// een tweede tabblad met hetzelfde deck (#2826).
///
/// Op desktop is dit een no-op — daar is geen adresbalk om bij te werken.
void replaceAddressBar(Uri uri) => impl.replaceAddressBar(uri);
