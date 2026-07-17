// Kiest de platform-git: de gehardde dart:io-uitvoerder op desktop, een eerlijke
// stub op web (waar geen subproces bestaat, §8.3/§11).
//
// Spiegelt de git_transport/cve_transport conditional-export-naden.
export 'git_cli_web.dart' if (dart.library.io) 'git_cli_io.dart';
