[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $root
try {
    $revision = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify source revision.' }
    $dirty = & git status --porcelain --untracked-files=normal
    if ($dirty) { throw 'Commit the intended source changes before creating an identified package.' }
    & moon build --target native --release --deny-warn
    if ($LASTEXITCODE -ne 0) { throw 'Native release build failed.' }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $name = "RepoWayfinder-MB-windows-$stamp"
    $dist = Join-Path $root 'dist'
    if (-not (Test-Path -LiteralPath $dist)) { New-Item -ItemType Directory -Path $dist | Out-Null }
    $packageRoot = Join-Path $dist $name
    if (Test-Path -LiteralPath $packageRoot) { throw 'Package destination already exists.' }
    New-Item -ItemType Directory -Path $packageRoot | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $packageRoot 'scripts') | Out-Null
    Copy-Item -LiteralPath (Join-Path $root '_build/native/release/build/cmd/main/main.exe') -Destination (Join-Path $packageRoot 'RepoWayfinder-MB.exe')
    foreach ($file in @('README.md','LICENSE','点我启动RepoWayfinder-MB.bat','首次运行失败时点我修复环境.bat')) {
        Copy-Item -LiteralPath (Join-Path $root $file) -Destination $packageRoot
    }
    Copy-Item -LiteralPath (Join-Path $root 'scripts/bootstrap.ps1') -Destination (Join-Path $packageRoot 'scripts')
    foreach ($batch in Get-ChildItem -LiteralPath $packageRoot -Filter '*.bat' -File) {
        $text = [IO.File]::ReadAllText($batch.FullName)
        [IO.File]::WriteAllText($batch.FullName, ($text -replace "`r?`n", "`r`n"), [Text.UTF8Encoding]::new($false))
    }
    # Only tracked fixture files; never copy node_modules, virtualenvs or runtime reports.
    $fixtures = & git ls-files examples docs
    foreach ($relative in $fixtures) {
        $destination = Join-Path $packageRoot $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $root $relative) -Destination $destination
    }
    $manifest = [ordered]@{source_commit=$revision;platform='windows-native';files=@()}
    foreach ($file in Get-ChildItem -LiteralPath $packageRoot -File -Recurse) {
        $manifest.files += @{path=[IO.Path]::GetRelativePath($packageRoot,$file.FullName);sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $packageRoot 'manifest.json') -Encoding utf8
    $archive = Join-Path $dist ($name + '.zip')
    Compress-Archive -LiteralPath $packageRoot -DestinationPath $archive
    [pscustomobject]@{source_commit=$revision;zip=$archive;sha256=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash;package=$packageRoot} | ConvertTo-Json
} finally { Pop-Location }
