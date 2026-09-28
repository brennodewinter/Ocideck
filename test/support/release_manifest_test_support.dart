import 'dart:io';

/// Installs a hermetic stand-in for minisign.
///
/// The stand-in deliberately accepts only the production verification shape
/// (`-Vm … -x … -p …`) and treats a byte-identical copy of the manifest as the
/// test signature. This lets the packaging tests prove that verification is
/// mandatory and happens before a hash is consumed, without putting a private
/// release key in the repository or depending on minisign being installed on
/// every test runner.
File writeFakeMinisign(Directory temp) {
  final verifier = File('${temp.path}/minisign');
  verifier.writeAsStringSync(r'''#!/bin/sh
set -eu

[ "$#" -eq 7 ]
[ "$1" = "-Vm" ]
manifest="$2"
[ "$3" = "-x" ]
signature="$4"
[ "$5" = "-p" ]
public_key="$6"
[ "$7" = "-q" ]
[ -s "$public_key" ]
cmp -s "$manifest" "$signature"
''');
  Process.runSync('chmod', ['+x', verifier.path]);
  return verifier;
}

File signTestManifest(File manifest) =>
    File('${manifest.path}.minisig')
      ..writeAsBytesSync(manifest.readAsBytesSync());

File writeFakeCurl(Directory temp) {
  final curl = File('${temp.path}/curl');
  curl.writeAsStringSync(r'''#!/bin/sh
set -eu

output=''
previous=''
for argument in "$@"; do
  if [ "$previous" = '-o' ]; then output="$argument"; fi
  previous="$argument"
  url="$argument"
done
[ -n "$output" ]
case "$url" in
  */SHA256SUMS) source="$FAKE_RELEASE_DIR/SHA256SUMS" ;;
  */SHA256SUMS.minisig) source="$FAKE_RELEASE_DIR/SHA256SUMS.minisig" ;;
  *) exit 22 ;;
esac
cp "$source" "$output"
''');
  Process.runSync('chmod', ['+x', curl.path]);
  return curl;
}
