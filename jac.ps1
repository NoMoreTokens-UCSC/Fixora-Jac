# Project-local launcher. Uses the verified WSL toolchain without changing PATH.
$ErrorActionPreference = 'Stop'
$distribution = if ($env:JAC_WSL_DISTRO) { $env:JAC_WSL_DISTRO } else { 'Ubuntu-24.04' }
$env:WSL_UTF8 = '1'
$linuxLauncher = & wsl.exe --distribution $distribution --cd $PSScriptRoot --exec wslpath -a -u (Join-Path $PSScriptRoot 'scripts/jac.sh')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& wsl.exe --distribution $distribution --cd (Get-Location).Path --exec bash $linuxLauncher.Trim() @args
exit $LASTEXITCODE
