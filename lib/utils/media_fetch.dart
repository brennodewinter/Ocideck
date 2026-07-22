// De afbeeldingsprovider voor een remote media-URL uit een deck.
//
// Waarom hier een eigen provider staat en niet gewoon `NetworkImage`: die
// resolvet de hostnaam zélf op het moment van ophalen. `NetGuard`-controles
// eromheen keuren dan een adres dat een fractie later opnieuw wordt opgezocht,
// en tussen die twee momenten kan een aanvaller met macht over DNS zijn
// hostnaam naar binnen laten wijzen (TOCTOU / DNS-rebind). De import van een
// deck-URL loste dat al op door de socket op het gekeurde adres vast te pinnen;
// de mediakant deed dat niet, en dat verschil was er geen dat iemand bedoeld
// had.
//
// Op web bestaat die pinning niet en kan ze er ook niet draaien: `dart:io`
// ontbreekt en de browser opent de verbinding. Daar zijn de browser (CORS,
// mixed content) en de pagina-CSP (`connect-src`) de poort — dezelfde
// redenering als in `file_service_net.dart`.
export 'media_fetch_web.dart'
    if (dart.library.io) 'media_fetch_io.dart'
    show guardedNetworkImage;
