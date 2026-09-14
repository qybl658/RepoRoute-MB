[CmdletBinding()]
param(
    [string]$Executable = (Join-Path $PSScriptRoot '../_build/native/debug/build/cmd/main/main.exe'),
    [string]$Bootstrap = (Join-Path $PSScriptRoot 'bootstrap.ps1')
)
$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('RepoWayfinder interactive ' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../examples/python-cli/main.py') -Destination $testRoot
Add-Content -LiteralPath (Join-Path $testRoot 'main.py') -Value "`nimport time`ntime.sleep(3)" -Encoding UTF8
$start = [Diagnostics.ProcessStartInfo]::new()
$start.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardInput = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
$start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
foreach ($arg in @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',([IO.Path]::GetFullPath($Bootstrap)),'-ExecutablePath',([IO.Path]::GetFullPath($Executable)),'-ProjectRoot',$testRoot)) { $start.ArgumentList.Add($arg) }
$process = [Diagnostics.Process]::Start($start)
$firstLine = $process.StandardOutput.ReadLineAsync()
if (-not $firstLine.Wait(5000)) { $process.Kill($true); throw 'No visible prompt before user input (stdout buffering).' }
$prefix = $firstLine.GetAwaiter().GetResult()
$promptLine = $process.StandardOutput.ReadLineAsync()
if (-not $promptLine.Wait(5000)) { $process.Kill($true); throw 'Input prompt did not become visible.' }
$prefix += "`n" + $promptLine.GetAwaiter().GetResult()
if (-not $prefix.Contains('GitHub')) { $process.Kill($true); throw "Unexpected startup prompt: $prefix" }
if (-not $prefix.Contains('AI Agent')) { $process.Kill($true); throw 'Missing keyword example in startup prompt.' }
$stdout = $process.StandardOutput.ReadToEndAsync()
$stderr = $process.StandardError.ReadToEndAsync()
$process.StandardInput.WriteLine($testRoot)
$process.StandardInput.Close()
if (-not $process.WaitForExit(60000)) { $process.Kill($true); throw 'Interactive launcher timed out.' }
$output = $prefix + "`n" + $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
$log = Get-Content -LiteralPath (Join-Path $testRoot 'run.md') -Raw -Encoding UTF8
$success = [string]::Concat([char]0x8FD0,[char]0x884C,[char]0x6210,[char]0x529F)
if ($process.ExitCode -ne 0 -or -not $output.Contains($success) -or -not $log.Contains($success)) { throw "Interactive execution/log failed: $output`nLOG: $log" }
if ($log -match 'Transcript|Start-Transcript' -or $log.Contains([string]::Concat([char]0x8F93,[char]0x8F93))) { throw 'Duplicated/transcript output in run.md.' }
if ($log.Contains('__RWF_WAIT') -or $output.Contains('__RWF_WAIT')) { throw 'Internal progress frames leaked into output/log.' }
if (-not $output.Contains([string]::Concat([char]0x5DF2,[char]0x7B49,[char]0x5F85))) { throw 'No waiting animation during slow project execution.' }
[pscustomobject]@{status='passed'; evidence=$testRoot; exit_code=$process.ExitCode} | ConvertTo-Json
