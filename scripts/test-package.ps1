[CmdletBinding()]
param([Parameter(Mandatory)][string]$Archive)
$ErrorActionPreference = 'Stop'
$archivePath = [IO.Path]::GetFullPath($Archive)
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('RepoWayfinder 包验收 ' + [guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $archivePath -DestinationPath $testRoot
$directories = @(Get-ChildItem -LiteralPath $testRoot -Directory)
if ($directories.Count -ne 1) { throw 'Expected one package root.' }
$packageRoot = $directories[0].FullName
$manifest = Get-Content -LiteralPath (Join-Path $packageRoot 'manifest.json') -Raw | ConvertFrom-Json
foreach ($item in $manifest.files) {
    $target = [IO.Path]::GetFullPath((Join-Path $packageRoot $item.path))
    if (-not $target.StartsWith($packageRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid manifest path.' }
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $item.sha256) { throw ('Package hash mismatch: ' + $item.path) }
}
$savedPause = $env:REPOWAYFINDER_NO_PAUSE
try {
    $env:REPOWAYFINDER_NO_PAUSE = '1'
    $output = & (Join-Path $packageRoot '点我启动RepoWayfinder-MB.bat') --help 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $output -notmatch 'deploy TARGET' -or $output -match 'not recognized|Building the native') {
        throw "Packaged launcher did not directly run the native program: $output"
    }
    & (Join-Path $PSScriptRoot 'test-deployment.ps1') -Executable (Join-Path $packageRoot 'RepoWayfinder-MB.exe')
    [pscustomobject]@{status='passed'; source_commit=$manifest.source_commit; zip=$archivePath; sha256=(Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash; evidence=$testRoot} | ConvertTo-Json
} finally { $env:REPOWAYFINDER_NO_PAUSE = $savedPause }
