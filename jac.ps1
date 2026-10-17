# Project-local launcher. Uses the verified WSL toolchain without changing PATH.
$ErrorActionPreference = 'Stop'
$distributionArgs = if ($env:JAC_WSL_DISTRO) { @('--distribution', $env:JAC_WSL_DISTRO) } else { @() }
$env:WSL_UTF8 = '1'
$linuxLauncher = & wsl.exe @distributionArgs --cd $PSScriptRoot --exec wslpath -a -u (Join-Path $PSScriptRoot 'scripts/jac.sh')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& wsl.exe @distributionArgs --cd $PSScriptRoot --exec bash -l $linuxLauncher.Trim() @args
exit $LASTEXITCODE
