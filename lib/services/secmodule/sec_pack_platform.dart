// Platform-selected factories for the module-pack transport + cache store.
//
// The provisioner core (sec_module_provisioner.dart) is pure Dart; the concrete
// network + filesystem live behind this conditional export so the pure core and
// the Riverpod provider both compile on web. On desktop the io implementation
// does the SSRF-hardened fetch + app-support caching; on web (where
// `supportsNetworkDeckSources` is false) both degrade gracefully.
export 'sec_pack_platform_io.dart'
    if (dart.library.html) 'sec_pack_platform_web.dart';
