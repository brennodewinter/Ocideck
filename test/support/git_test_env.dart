import 'dart:io';

/// De omgeving waarin de echt-server-git-tests hun `git`-subproces draaien.
///
/// Waarom niet de omgeving van de ontwikkelaar meenemen: een `~/.gitconfig` met
/// een eigen `http.sslCAInfo`, een proxy of een credential-helper zou de
/// uitkomst kleuren, en dan bewijst de test niet wat hij beweert.
///
/// En waarom niet — zoals de tests dit eerder deden — een handjevol
/// POSIX-variabelen (`PATH` + wat hermetische sleutels): op Windows laadt zonder
/// `SystemRoot` de socket-DLL niet, en dan komt géén enkele verbinding tot
/// stand. Dat lieten de tests als "git op Windows bereikt de testserver niet"
/// lezen — waarna de echt-server-toetsen op Windows werden overgeslagen — terwijl
/// het de omgeving was die tekortschoot, niet git (#934). Zonder een
/// Windows-correcte omgeving is op de CI niet te toetsen of git zich daar aan de
/// pin houdt.
///
/// Dit spiegelt bewust `NativeGitCli._hardenedEnv`: dezelfde toelatingslijst per
/// platform en dezelfde hermetische afsluiting. [home] is een lege, wegwerpbare
/// map die als `HOME` (en op Windows `USERPROFILE`) dient, zodat er geen globale
/// git-config meespeelt.
Map<String, String> hermeticGitEnv({required String home}) {
  const carriedPosix = {'PATH', 'TMPDIR', 'SSL_CERT_FILE', 'SSL_CERT_DIR'};
  const carriedWindows = {
    'PATH',
    'PATHEXT',
    'SystemRoot',
    'SYSTEMROOT',
    'SystemDrive',
    'COMSPEC',
    'windir',
    'TEMP',
    'TMP',
    'USERPROFILE',
    'LOCALAPPDATA',
    'APPDATA',
    'ProgramData',
    'ProgramFiles',
    'ProgramFiles(x86)',
    'ProgramW6432',
  };
  final carried = Platform.isWindows ? carriedWindows : carriedPosix;
  return {
    for (final entry in Platform.environment.entries)
      if (carried.contains(entry.key)) entry.key: entry.value,
    'GIT_TERMINAL_PROMPT': '0',
    'GIT_CONFIG_NOSYSTEM': '1',
    'GIT_CONFIG_GLOBAL': Platform.isWindows ? 'NUL' : '/dev/null',
    'HOME': home,
    if (Platform.isWindows) 'USERPROFILE': home,
    // Git spreekt de taal van de schil; wij lezen zijn stderr. Vastzetten op C
    // houdt de foutteksten in het Engels, zodat de assertions ('certificate')
    // ook op een niet-Engelse machine kloppen.
    'LC_ALL': 'C',
    'LANGUAGE': '',
  };
}
