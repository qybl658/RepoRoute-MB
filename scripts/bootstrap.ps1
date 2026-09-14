[CmdletBinding()]
param(
    [switch]$BuildOnly,
    [switch]$ForceBuild,
    [string]$MoonPath,
    [string]$ExecutablePath,
    [string]$ProjectRoot,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$CliArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

function Find-FirstFile {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and
            (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }
    return $null
}

function Find-PackagedExecutable {
    param([string]$Root)
    Find-FirstFile @(
        (Join-Path $Root 'RepoWayfinder-MB.exe'),
        (Join-Path $Root 'RepoWayfinder.exe'),
        (Join-Path $Root 'bin\RepoWayfinder-MB.exe'),
        (Join-Path $Root 'bin\RepoWayfinder.exe'),
        (Join-Path $Root 'dist\RepoWayfinder-MB.exe'),
        (Join-Path $Root 'dist\RepoWayfinder.exe')
    )
}

function Find-BuiltExecutable {
    param([string]$Root)
    Find-FirstFile @(
        (Join-Path $Root '_build\native\release\build\cmd\main\main.exe'),
        (Join-Path $Root '_build\native\release\build\cmd\main\RepoWayfinder-MB.exe')
    )
}

function Find-Moon {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $requested = Find-FirstFile @($RequestedPath)
        if ($null -eq $requested) {
            throw "指定的 MoonBit 可执行文件不存在：$RequestedPath"
        }
        return $requested
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($env:MOON_HOME)) {
        $candidates.Add((Join-Path $env:MOON_HOME 'bin\moon.exe'))
        $candidates.Add((Join-Path $env:MOON_HOME 'bin\moon.cmd'))
    }
    $candidates.Add((Join-Path $ProjectRoot '.repowayfinder-tools\moon\bin\moon.exe'))
    $candidates.Add((Join-Path $ProjectRoot '.repowayfinder-tools\moon\bin\moon.cmd'))
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $candidates.Add((Join-Path $env:USERPROFILE '.moon\bin\moon.exe'))
        $candidates.Add((Join-Path $env:USERPROFILE '.moon\bin\moon.cmd'))
    }

    $existing = Find-FirstFile $candidates.ToArray()
    if ($null -ne $existing) {
        return $existing
    }

    $fromPath = Get-Command moon.exe, moon.cmd, moon -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $fromPath) {
        return [System.IO.Path]::GetFullPath($fromPath.Source)
    }

    # Existing developer-tool fallback only. The launcher never creates or assumes D:.
    Find-FirstFile @('D:\Tools\MoonBit\bin\moon.exe')
}

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "项目根目录不存在：$ProjectRoot"
}

$runLog = Join-Path $ProjectRoot 'run.md'
$script:TranscriptStarted = $false

function Stop-RunTranscript {
    $script:TranscriptStarted = $false
}

trap {
    $message = $_.Exception.Message
    Write-Host "RepoWayfinder-MB 启动失败：$message" -ForegroundColor Red
    Stop-RunTranscript
    exit 1
}

if (Test-Path -LiteralPath $runLog -PathType Leaf) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $previousRun = Join-Path $ProjectRoot "run.previous.$stamp.md"
    Copy-Item -LiteralPath $runLog -Destination $previousRun
}
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
Set-Content -LiteralPath $runLog -Encoding UTF8 -Value ('# RepoWayfinder 运行记录' + "`r`n" + (Get-Date -Format o))
$script:TranscriptStarted = $true

$executable = $null
if (-not [string]::IsNullOrWhiteSpace($ExecutablePath)) {
    $executable = Find-FirstFile @($ExecutablePath)
    if ($null -eq $executable) {
        throw "指定的 RepoWayfinder 可执行文件不存在：$ExecutablePath"
    }
} elseif (-not $ForceBuild) {
    $executable = Find-PackagedExecutable -Root $ProjectRoot
}

if ($null -eq $executable) {
    $moon = Find-Moon -RequestedPath $MoonPath
    if ($null -eq $moon) {
        throw @'
未找到 MoonBit。若使用已打包的 RepoWayfinder-MB 可执行文件，则不需要编译器。
若当前是源码目录，请从 https://www.moonbitlang.com/download/ 安装 MoonBit，或查看 CLI 提示后运行环境修复流程。
本次操作没有修改 PATH 或任何机器设置。
'@
    }

    $moonBin = Split-Path -Parent $moon
    $detectedHome = Split-Path -Parent $moonBin
    $env:MOON_HOME = $detectedHome
    $pathParts = @($env:Path -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($pathParts -notcontains $moonBin) {
        $env:Path = "$moonBin;$env:Path"
    }

    Write-Host "正在使用以下 MoonBit 工具链构建 RepoWayfinder-MB 原生可执行文件：$moon"
    Push-Location $ProjectRoot
    try {
        & $moon build --target native --release cmd/main
        $buildExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($buildExitCode -ne 0) {
        throw "MoonBit 原生构建失败，退出代码：$buildExitCode。"
    }
    $executable = Find-BuiltExecutable -Root $ProjectRoot
    if ($null -eq $executable) {
        throw 'MoonBit 报告构建成功，但没有生成预期的原生可执行文件。'
    }
}

if ($BuildOnly) {
    Write-Host "原生可执行文件已就绪：$executable"
    Stop-RunTranscript
    exit 0
}

$effectiveArgs = @()
if ($null -ne $CliArgs -and $CliArgs.Count -gt 0) {
    $knownCommands = @(
        'deploy', 'scan', 'resume', 'search', 'config', 'ai-config',
        'analyze', 'diagnose', 'doctor', 'uninstall', 'help', '--help', '-h'
    )
    if ($knownCommands -contains $CliArgs[0].ToLowerInvariant()) {
        $effectiveArgs = @($CliArgs)
    } else {
        $effectiveArgs = @('deploy') + @($CliArgs)
    }
}

Push-Location $ProjectRoot
try {
    & $executable @effectiveArgs 2>&1 | ForEach-Object {
        $line = $_.ToString()
        Add-Content -LiteralPath $runLog -Value $line -Encoding UTF8
        [Console]::WriteLine($line)
    }
    $cliExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
Stop-RunTranscript
exit $cliExitCode
