[CmdletBinding()]
param([string]$Executable = (Join-Path $PSScriptRoot '..\_build\native\debug\build\cmd\main\main.exe'))
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$exePath = [IO.Path]::GetFullPath($Executable)
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('RepoWayfinder MB 中文 ' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$savedHome = $env:REPOWAYFINDER_HOME
$env:REPOWAYFINDER_HOME = $testRoot
$results = [Collections.Generic.List[object]]::new()
function Invoke-Case {
    param([string]$Name, [string[]]$Arguments, [int]$ExpectedExit, [string]$ExpectedStatus)
    $output = (& $exePath @Arguments 2>&1 | Out-String)
    $code = $LASTEXITCODE
    if (($ExpectedExit -ge 0 -and $code -ne $ExpectedExit) -or ($ExpectedExit -lt 0 -and $code -eq 0)) { throw "$Name returned $code, expected $ExpectedExit. $output" }
    if ($ExpectedStatus -and $output -notmatch ('"status":\s*"' + [regex]::Escape($ExpectedStatus) + '"')) { throw "$Name status mismatch: $output" }
    $results.Add([pscustomobject]@{case=$Name; exit_code=$code; status=$ExpectedStatus})
}
try {
    Copy-Item -LiteralPath (Join-Path $repoRoot 'examples/python-cli/main.py') -Destination $testRoot
    Copy-Item -LiteralPath (Join-Path $repoRoot 'examples/python-cli/.env.example') -Destination $testRoot
    Invoke-Case 'python-real-venv-and-start' @('deploy',$testRoot,'--execute','--trust-project') 0 'SUCCEEDED'
    if (-not (Test-Path -LiteralPath (Join-Path $testRoot '.env'))) { throw 'Missing generated project config.' }
    $configPath = Join-Path $testRoot '.env'
    [IO.File]::WriteAllText($configPath, 'DEMO_MESSAGE=user-owned-synthetic-value')
    $report = Get-ChildItem -LiteralPath (Join-Path $testRoot '.repowayfinder-reports') -Directory | Select-Object -First 1
    $savedPause = $env:REPOWAYFINDER_NO_PAUSE
    try {
        $env:REPOWAYFINDER_NO_PAUSE = '1'
        $diagnosis = & (Join-Path $report.FullName '查看诊断.bat') 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -or $diagnosis -notmatch 'SUCCEEDED') { throw "Report launcher failed: $diagnosis" }
        $results.Add([pscustomobject]@{case='chinese-report-launcher';exit_code=0;status='SUCCEEDED'})
    } finally { $env:REPOWAYFINDER_NO_PAUSE = $savedPause }
    Invoke-Case 'saved-plan-resume' @('resume',(Join-Path $report.FullName 'deployment.json'),'--execute','--trust-project') 0 'SUCCEEDED'
    if ([IO.File]::ReadAllText($configPath) -ne 'DEMO_MESSAGE=user-owned-synthetic-value') { throw 'Existing user config was overwritten.' }
    Invoke-Case 'invalid-choice' @('deploy',$testRoot,'--candidate','99') -1 ''
    $httpRoot = Join-Path $testRoot 'http'
    New-Item -ItemType Directory -Path $httpRoot | Out-Null
    foreach ($name in @('package.json','server.js')) { Copy-Item -LiteralPath (Join-Path $repoRoot ('examples/node-http/' + $name)) -Destination $httpRoot }
    Invoke-Case 'node-install-and-http-health' @('deploy',$httpRoot,'--execute','--trust-project','--health-url','http://127.0.0.1:18765/') 0 'VERIFIED_HTTP'
    $connection = Get-NetTCPConnection -LocalPort 18765 -State Listen -ErrorAction SilentlyContinue
    if ($connection) { throw 'Owned Node HTTP process remained after verification.' }
    $results.Add([pscustomobject]@{case='owned-process-cleanup';exit_code=0;status='closed'})
    Copy-Item -LiteralPath (Join-Path $repoRoot 'examples/python-failure/main.py') -Destination (Join-Path $testRoot 'main.py')
    Invoke-Case 'real-project-exit-failure' @('deploy',$testRoot,'--execute','--trust-project') 1 'FAILED'
    $learnRoot = Join-Path $testRoot 'no-entry'
    New-Item -ItemType Directory -Path $learnRoot | Out-Null
    Invoke-Case 'no-entry-is-learning-not-failure' @('deploy',$learnRoot,'--execute','--trust-project') 0 'LEARN'
    $results | ConvertTo-Json
    Write-Output "Evidence directory: $testRoot (retained for inspection)"
} finally {
    $env:REPOWAYFINDER_HOME = $savedHome
}
