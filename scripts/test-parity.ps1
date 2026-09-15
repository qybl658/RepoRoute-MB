[CmdletBinding()]
param([string]$Executable=(Join-Path $PSScriptRoot '../_build/native/release/build/cmd/main/main.exe'))
$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('repowayfinder-parity-'+[guid]::NewGuid().ToString('N'))
$bin=Join-Path $root '.repowayfinder-tools/node_modules/.bin'
New-Item -ItemType Directory -Path $bin -Force | Out-Null
Set-Content -LiteralPath (Join-Path $root 'package.json') -Value '{"name":"parity-fixture","scripts":{"start":"node main.js"}}' -Encoding ASCII
Set-Content -LiteralPath (Join-Path $root 'README.md') -Value "# Fixture`n## Usage`nnpm start`n## Credits`nNot usage" -Encoding ASCII
# An offline registry stand-in: no package network request or third-party code.
$mock=@'
@echo off
if "%~1"=="--version" (echo 10.0.0 & exit /b 0)
if "%~1"=="run" (echo fixture-started & exit /b 0)
if "%~2"=="--registry=https://registry.npmmirror.com" (echo fixture-mirror-install & exit /b 0)
if "%~2"=="--registry" if "%~3"=="https://registry.npmmirror.com" (echo fixture-mirror-install & exit /b 0)
echo npm ERR! ETIMEDOUT
exit /b 1
'@
[IO.File]::WriteAllText((Join-Path $bin 'npm.cmd'),($mock -replace "`r?`n","`r`n"),[Text.Encoding]::ASCII)
$saved=$env:REPOWAYFINDER_HOME
$savedProfile=$env:USERPROFILE
try {
  $env:REPOWAYFINDER_HOME=$root
  $env:USERPROFILE=$root
  $output='y' | & $Executable deploy $root --execute --trust-project --install 2>&1 | Out-String
  if($LASTEXITCODE -ne 0 -or $output -notmatch 'SUCCEEDED'){throw "Mirror continuation failed: $output"}
  $report=Get-ChildItem -LiteralPath (Join-Path $root '.repowayfinder-reports') -Directory | Select-Object -First 1
  $json=Get-Content -LiteralPath (Join-Path $report.FullName 'deployment.json') -Raw | ConvertFrom-Json
  if(@($json.attempts | Where-Object phase -eq 'install-public-mirror').Count -ne 1){throw 'Expected exactly one mirror attempt'}
  $guide=Get-Content -LiteralPath (Join-Path $report.FullName 'beginner_guide.md') -Raw
  if($guide -notmatch 'npm start' -or $guide -match 'Not usage'){throw 'README guide extraction failed'}
  # Refusal must not execute a mirror or claim success.
  $denied='n' | & $Executable deploy $root --execute --trust-project --install 2>&1 | Out-String
  if($LASTEXITCODE -eq 0 -or $denied -match 'fixture-mirror-install'){throw "Mirror refusal failed: $denied"}
  $dockerRoot=Join-Path $root 'docker-fixture'
  New-Item -ItemType Directory -Path $dockerRoot | Out-Null
  $recipe="FROM python:3.11-slim-bullseye`nRUN echo deb http://deb.debian.org/debian bullseye main`nCMD python --version"
  Set-Content -LiteralPath (Join-Path $dockerRoot 'Dockerfile') -Value $recipe -Encoding ASCII
  $originalHash=(Get-FileHash -LiteralPath (Join-Path $dockerRoot 'Dockerfile')).Hash
  $dockerMock=@'
@echo off
if "%~1"=="build" (
  if not "%~2"=="--file" exit /b 9
  if not exist "%~3" exit /b 8
  findstr /c:"bookworm" "%~3" >nul
  exit /b %errorlevel%
)
echo offline-docker-fixture
exit /b 0
'@
  [IO.File]::WriteAllText((Join-Path $bin 'docker.cmd'),($dockerMock -replace "`r?`n","`r`n"),[Text.Encoding]::ASCII)
  $dockerOutput='y' | & $Executable deploy $dockerRoot --execute --trust-project 2>&1 | Out-String
  if($LASTEXITCODE -ne 0 -or $dockerOutput -notmatch 'SUCCEEDED'){throw "Report-local Docker route failed: $dockerOutput"}
  if((Get-FileHash -LiteralPath (Join-Path $dockerRoot 'Dockerfile')).Hash -ne $originalHash){throw 'Original Dockerfile changed'}
  $dockerDenied='n' | & $Executable deploy $dockerRoot --execute --trust-project 2>&1 | Out-String
  if($LASTEXITCODE -ne 20 -or $dockerDenied -notmatch 'WAITING_ENVIRONMENT' -or $dockerDenied -match 'offline-docker-fixture'){throw "Docker refusal failed: $dockerDenied"}
  [pscustomobject]@{status='passed';cases=@('one-shot-mirror-success','mirror-refusal','author-readme-guide','docker-repair-build-route','docker-refusal-no-execution');evidence=$root}|ConvertTo-Json
} finally { $env:REPOWAYFINDER_HOME=$saved; $env:USERPROFILE=$savedProfile }
