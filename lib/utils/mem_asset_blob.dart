/// Een `blob:`-URL voor een `mem:`-media-asset op web, of null.
///
/// Beeld tekent OciDeck op web rechtstreeks uit de bytes in de [WebAssetStore]
/// (`Image.memory`); video en audio hebben een URL nodig die de
/// `VideoPlayerController` kan openen. Deze helper maakt daarvoor eenmalig een
/// `blob:`-URL van de bytes (met het MIME-type uit de bestandsnaam) en
/// hergebruikt hem.
///
/// Op elke niet-web-build is er geen browser om een blob te maken — en komt een
/// `mem:`-pad ook nooit langs, want daar pakken pakketten naar schijf uit — dus
/// de stub levert null.
library;

export 'mem_asset_blob_stub.dart'
    if (dart.library.html) 'mem_asset_blob_web.dart';
