[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
foreach ($name in @('点我启动RepoWayfinder-MB.bat','首次运行失败时点我修复环境.bat')) {
    $batchText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot ('../' + $name)))
    if ($batchText -match '(?<!\r)\n') { throw "Windows BAT must use CRLF: $name" }
}

$bootstrap = Join-Path $PSScriptRoot 'bootstrap.ps1'
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("repowayfinder-bootstrap-test-" + [Guid]::NewGuid().ToString('N'))
$sandbox = [System.IO.Path]::GetFullPath($sandbox)
$expectedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
if (-not $sandbox.StartsWith($expectedTempRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing unsafe test directory: $sandbox"
}

$beforeUserPath = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::User)
$beforeUserMoonHome = [Environment]::GetEnvironmentVariable('MOON_HOME', [EnvironmentVariableTarget]::User)
$bootstrapSource = Get-Content -Raw -LiteralPath $bootstrap
if ($bootstrapSource -match '(?i)\$(?:env:)?HOME\b' -or
    $bootstrapSource -match '(?i)Set-Variable\s+-Name\s+HOME') {
    throw 'Bootstrap must not repurpose HOME; use task-specific variables and process-local MOON_HOME/PATH only.'
}

try {
    New-Item -ItemType Directory -Path $sandbox | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $sandbox 'mock-moon\bin') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $sandbox 'mock-bin') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $sandbox 'moon.mod') -Encoding UTF8 -Value 'name = "test/bootstrap"'

    $buildOutput = Join-Path $sandbox '_build\native\release\build\cmd\main'
    $moonLog = Join-Path $sandbox 'moon.log'
    $mockMoon = Join-Path $sandbox 'mock-moon\bin\moon.cmd'
    $moonBody = @"
@echo off
echo MOON_HOME=%MOON_HOME%>"$moonLog"
echo ARGS=%*>>"$moonLog"
if not exist "$buildOutput" mkdir "$buildOutput"
type nul >"$buildOutput\main.exe"
exit /b 0
"@
    Set-Content -LiteralPath $mockMoon -Encoding ASCII -Value $moonBody

    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $bootstrap `
        -ProjectRoot $sandbox -MoonPath $mockMoon -ForceBuild -BuildOnly
    if ($LASTEXITCODE -ne 0) {
        throw "Mock build bootstrap failed with exit code $LASTEXITCODE."
    }
    $buildLog = Get-Content -Raw -LiteralPath $moonLog
    if ($buildLog -notmatch 'ARGS=build --target native --release cmd/main') {
        throw "Bootstrap did not request a native release build. Log: $buildLog"
    }
    if ($buildLog -notmatch [regex]::Escape("MOON_HOME=$(Join-Path $sandbox 'mock-moon')")) {
        throw "Bootstrap did not inject MOON_HOME process-locally. Log: $buildLog"
    }

    $cliLog = Join-Path $sandbox 'cli.log'
    $mockCli = Join-Path $sandbox 'mock-bin\RepoWayfinder-MB.cmd'
    $cliBody = @"
@echo off
echo %*>"$cliLog"
exit /b 0
"@
    Set-Content -LiteralPath $mockCli -Encoding ASCII -Value $cliBody

    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $bootstrap `
        -ProjectRoot $sandbox -ExecutablePath $mockCli 'owner/repository' '--dry-run'
    if ($LASTEXITCODE -ne 0) {
        throw "Mock CLI bootstrap failed with exit code $LASTEXITCODE."
    }
    $cliArgs = (Get-Content -Raw -LiteralPath $cliLog).Trim()
    if ($cliArgs -ne 'deploy owner/repository --dry-run') {
        throw "Raw target was not routed through deploy. Actual: $cliArgs"
    }
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $bootstrap `
        -ProjectRoot $sandbox -ExecutablePath $mockCli 'scan' 'owner/repository'
    if ($LASTEXITCODE -ne 0) {
        throw "Mock scan forwarding failed with exit code $LASTEXITCODE."
    }
    $scanArgs = (Get-Content -Raw -LiteralPath $cliLog).Trim()
    if ($scanArgs -ne 'scan owner/repository') {
        throw "Known CLI command was incorrectly rewritten. Actual: $scanArgs"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $sandbox 'run.md') -PathType Leaf)) {
        throw 'Bootstrap did not write the supported latest-run diagnostic.'
    }
    $preservedRuns = @(Get-ChildItem -LiteralPath $sandbox -Filter 'run.previous.*.md' -File)
    if ($preservedRuns.Count -lt 1) {
        throw 'Bootstrap did not preserve the previous run.md before the next run.'
    }

    $afterUserPath = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::User)
    $afterUserMoonHome = [Environment]::GetEnvironmentVariable('MOON_HOME', [EnvironmentVariableTarget]::User)
    if ($beforeUserPath -ne $afterUserPath -or $beforeUserMoonHome -ne $afterUserMoonHome) {
        throw 'Bootstrap changed a persistent user PATH or MOON_HOME value.'
    }

    Write-Host 'bootstrap tests passed: native build request, process-local MoonBit environment, packaged CLI routing/forwarding, run.md preservation, no persistent environment changes.'
} finally {
    $resolvedSandbox = [System.IO.Path]::GetFullPath($sandbox)
    if ($resolvedSandbox.StartsWith($expectedTempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedSandbox) -like 'repowayfinder-bootstrap-test-*' -and
        (Test-Path -LiteralPath $resolvedSandbox)) {
        Remove-Item -LiteralPath $resolvedSandbox -Recurse -Force
    }
}
