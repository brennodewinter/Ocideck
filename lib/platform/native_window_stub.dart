Future<void> configureNativeWindow() async {}

/// Op web bestaat de vensterval van [quitApp] niet: een browsertabblad sluiten
/// werkt altijd, en een pagina kan zichzelf niet betrouwbaar sluiten. Daarom
/// een no-op — de afsluitknop wordt op web ook niet getoond.
Future<void> quitApp() async {}
