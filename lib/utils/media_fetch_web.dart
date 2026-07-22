import 'package:flutter/widgets.dart';

import 'image_limits.dart';

/// De web-tak: de browser opent de verbinding, dus hier valt niets te pinnen.
///
/// Dat is geen gat dat hier open blijft staan maar een andere poort: de browser
/// dwingt CORS en mixed content af, en de pagina-CSP begrenst met `connect-src`
/// waar de app überhaupt heen mag. `dart:io` — en daarmee `connectPinned` —
/// bestaat op web niet. Zelfde afweging als in `file_service_net.dart`.
///
/// De decode-cap geldt onverkort: die beschermt tegen een decodebom en staat
/// los van waar de bytes vandaan komen.
ImageProvider guardedNetworkImage(String url) => ResizeImage(
  NetworkImage(url),
  width: kMaxImageDecodeDimension,
  height: kMaxImageDecodeDimension,
  policy: ResizeImagePolicy.fit,
  allowUpscaling: false,
);
