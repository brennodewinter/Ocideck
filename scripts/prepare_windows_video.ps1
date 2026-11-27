param([string]$EvidenceDirectory = (Join-Path $env:RUNNER_TEMP 'windows-video'))
$ErrorActionPreference = 'Stop'
$evidence = $EvidenceDirectory
New-Item -ItemType Directory -Force $evidence | Out-Null
$installer = Join-Path $evidence 'WebView2RuntimeInstaller.exe'
Invoke-WebRequest 'https://go.microsoft.com/fwlink/p/?LinkId=2124701' -OutFile $installer
$signature = Get-AuthenticodeSignature $installer
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
  throw 'The runtime installer must have a valid Microsoft Authenticode signature'
}
$installed = Start-Process $installer -ArgumentList '/silent', '/install' -PassThru -Wait
if ($installed.ExitCode -notin @(0, 3010)) { throw "Runtime installation failed: $($installed.ExitCode)" }
$runtimeRoot = Join-Path ${env:ProgramFiles(x86)} 'Microsoft/EdgeWebView/Application'
$versions = @(Get-ChildItem $runtimeRoot -Directory | Where-Object { $_.Name -match '^\d+\.' } | Select-Object -ExpandProperty Name)
@{ installer_sha256 = (Get-FileHash $installer -Algorithm SHA256).Hash; versions = $versions } |
  ConvertTo-Json | Set-Content (Join-Path $evidence 'runtime.json')
Remove-Item $installer
