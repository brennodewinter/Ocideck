import 'update_check_service.dart';
import 'update_check_fetch_io.dart'
    if (dart.library.html) 'update_check_fetch_web.dart'
    as implementation;

/// De platform-ophaalstap voor [UpdateCheckService]: gepind op desktop
/// (NetGuard + eigen TLS, zie update_check_fetch_io.dart), weigerend op web —
/// de webbouw draait de gedeployde versie en heeft geen check nodig.
const UpdateCheckFetch defaultUpdateCheckFetch =
    implementation.pinnedUpdateCheckFetch;
