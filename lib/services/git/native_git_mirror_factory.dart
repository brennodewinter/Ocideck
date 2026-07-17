// Kiest de native mirror-fabriek: de echte clone op desktop, een stub die
// `null` geeft op web (waar het native plane niet bestaat, §8.3). Web-veilig,
// zodat de state-laag hem overal mag importeren.
export 'native_git_mirror_stub.dart'
    if (dart.library.io) 'native_git_mirror_io.dart';
