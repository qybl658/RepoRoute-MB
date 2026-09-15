///|
test "probe classification distinguishes missing, broken and ready" {
  assert_eq(classify_probe(false, 127, false), "missing")
  assert_eq(classify_probe(true, 1, false), "broken")
  assert_eq(classify_probe(true, 0, true), "broken")
  assert_eq(classify_probe(true, 0, false), "ready")
  assert_true(
    python_placeholder_without_runtime(
      "C:\\Users\\demo\\AppData\\Local\\Microsoft\\WindowsApps\\python.exe", 1, false,
    ),
  )
  assert_true(
    python_placeholder_without_runtime("C:\\Windows\\py.exe", 103, false),
  )
  assert_false(
    python_placeholder_without_runtime("C:\\Python313\\python.exe", 1, false),
  )
}

///|
test "trusted winget IDs are exact and unknown tools have no installer" {
  assert_eq(system_package_id("git"), Some("Git.Git"))
  assert_eq(system_package_id("node"), Some("OpenJS.NodeJS.LTS"))
  assert_eq(system_package_id("python"), Some("Python.Python.3.13"))
  assert_eq(system_package_id("docker"), Some("Docker.DockerDesktop"))
  assert_eq(system_package_id("wsl"), None)
  assert_eq(system_package_id("unknown"), None)
}

///|
test "winget ownership requires a confirmed absent-before state" {
  assert_true(
    winget_confirmed_absent(
      -1978335212, "No installed package found matching input criteria.",
    ),
  )
  assert_false(winget_confirmed_absent(1, "source agreement failed"))
  assert_eq(
    package_line("Git  Git.Git 2.54.0 2.55.0\n", "Git.Git"),
    Some("Git  Git.Git 2.54.0 2.55.0"),
  )
}

///|
test "WSL exit zero does not override localized readiness blockers" {
  assert_true(wsl_status_ready(0, "默认版本: 2", false))
  assert_false(
    wsl_status_ready(
      0, "此计算机不支持 WSL 2，请在固件中启用虚拟化。", false,
    ),
  )
  assert_false(
    wsl_status_ready(0, "WSL2 不可用；请启用虚拟机平台。", false),
  )
}

///|
test "WSL restart marker expires only after a different known boot" {
  let marker =
    #|{"owner":"RepoWayfinder-MB","action":"wsl --update","state":"restart_required","boot_id":"2026-09-15T00:00:00Z"}
  assert_eq(wsl_marker_disposition(marker, "2026-09-15T00:00:00Z"), "same_boot")
  assert_eq(wsl_marker_disposition(marker, "2026-09-15T01:00:00Z"), "stale")
  assert_eq(wsl_marker_disposition(marker, ""), "same_boot")
}

///|
test "uncertain or legacy WSL markers never authorize automatic replay" {
  let uncertain =
    #|{"owner":"RepoWayfinder-MB","action":"wsl --install --no-distribution","state":"uncertain","boot_id":"old"}
  let legacy =
    #|{"owner":"RepoWayfinder-MB","action":"wsl --update","state":"started_or_waiting"}
  assert_eq(wsl_marker_disposition(uncertain, "new"), "uncertain")
  assert_eq(wsl_marker_disposition(legacy, "new"), "uncertain")
  assert_eq(wsl_marker_disposition("not json", "new"), "uncertain")
  assert_eq(
    wsl_marker_disposition(
      uncertain.replace_all(old="RepoWayfinder-MB", new="other-owner"),
      "new",
    ),
    "uncertain",
  )
}

///|
test "Windows preparation decisions preserve modern WSL2 policy" {
  assert_eq(
    windows_docker_preparation_action(
      true, 1, "WSL is not installed; run wsl --install", false, "disabled",
    ),
    "install_wsl",
  )
  assert_eq(
    windows_docker_preparation_action(
      true, 1, "WSL kernel missing; run wsl --update", false, "disabled",
    ),
    "update_wsl",
  )
  assert_eq(
    windows_docker_preparation_action(
      true, 0, "WSL2 不可用；请启用虚拟机平台。", false, "disabled",
    ),
    "enable_virtual_machine_platform",
  )
  assert_eq(
    windows_docker_preparation_action(
      true, 0, "默认版本: 2", false, "enablepending",
    ),
    "restart_required",
  )
  assert_eq(
    windows_docker_preparation_action(
      true, 1, "WSL is not installed; run wsl --install", false, "disablepending",
    ),
    "restart_required",
  )
  assert_eq(
    windows_docker_preparation_action(
      true, 0, "默认版本: 2", false, "enabled",
    ),
    "ready",
  )
  assert_eq(
    windows_docker_preparation_action(
      true, 0, "默认版本: 2", false, "unknown",
    ),
    "manual",
  )
  assert_eq(
    windows_docker_preparation_action(
      false, 127, "Windows 找不到 wsl.exe。", false, "disabled",
    ),
    "enable_virtual_machine_platform",
  )
}

///|
test "Windows feature mock output is normalized conservatively" {
  assert_eq(windows_feature_state("Enabled\r\n"), "enabled")
  assert_eq(windows_feature_state("noise\nDisablePending\n"), "disablepending")
  assert_eq(windows_feature_state("policy denied"), "unknown")
}

///|
test "generated Windows helper uses native UAC and a narrow no-reboot allowlist" {
  let launcher = elevated_windows_launcher_script()
  assert_true(launcher.contains("Start-Process"))
  assert_true(launcher.contains("-Verb RunAs"))
  assert_true(launcher.contains("-WindowStyle Hidden"))
  assert_true(launcher.contains("-Wait -PassThru"))
  assert_false(launcher.to_lower().contains("consentpromptbehavioradmin"))
  assert_false(launcher.to_lower().contains("enablelua"))
  assert_false(launcher.to_lower().contains("shutdown.exe"))
  guard elevated_windows_action_script("enable_virtual_machine_platform")
    is Some(feature) else {
    fail("expected Virtual Machine Platform helper")
  }
  assert_true(feature.contains("/featurename:VirtualMachinePlatform"))
  assert_true(feature.contains("/norestart"))
  assert_false(feature.contains("Microsoft-Windows-Subsystem-Linux"))
  assert_false(feature.to_lower().contains("restart-computer"))
  guard elevated_windows_action_script("install_wsl") is Some(install) else {
    fail("expected WSL install helper")
  }
  assert_true(install.contains("--install --no-distribution"))
  guard elevated_windows_action_script("update_wsl") is Some(update) else {
    fail("expected WSL update helper")
  }
  assert_true(update.contains("--update"))
  assert_eq(elevated_windows_action_script("unreviewed"), None)
}

///|
async test "generated Windows helper scripts parse in Windows PowerShell" {
  if @host.windows() && @host.resolve("powershell") is Some(powershell) {
    let parser =
      #|& { param($encoded)
      #|$source=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
      #|$tokens=$null; $errors=$null
      #|[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors) | Out-Null
      #|if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Output $_.Message }; exit 1 }
      #|}
    let scripts = [elevated_windows_launcher_script()]
    for
      action in ["enable_virtual_machine_platform", "install_wsl", "update_wsl"] {
      guard elevated_windows_action_script(action) is Some(script) else {
        fail("missing generated action script: " + action)
      }
      scripts.push(script)
    }
    for script in scripts {
      let encoded = @base64.encode(
        @utf16.encode(script[:], endianness=Little)[:],
      )
      let parsed = @host.run(
        powershell,
        [
          "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", parser, encoded,
        ],
        current_dir(),
        15000,
      )
      if parsed.code != 0 {
        fail("PowerShell parser rejected generated helper:\n" + parsed.output)
      }
      assert_false(parsed.timed_out)
    }
  }
}

///|
async test "Windows launcher reaches native RunAs contract under a safe mock" {
  if @host.windows() && @host.resolve("powershell") is Some(powershell) {
    let launcher = elevated_windows_launcher_script()
    let encoded = @base64.encode(
      @utf16.encode(launcher[:], endianness=Little)[:],
    )
    let mock =
      #|& { param($launcherEncoded)
      #|function Start-Process {
      #|  param([string]$FilePath,[string]$Verb,[object[]]$ArgumentList,[string]$WindowStyle,[switch]$Wait,[switch]$PassThru)
      #|  if ($Verb -ne 'RunAs' -or $WindowStyle -ne 'Hidden' -or -not $Wait -or -not $PassThru) { throw 'launcher contract mismatch' }
      #|  if ($ArgumentList -notcontains '-EncodedCommand') { throw 'encoded child command missing' }
      #|  [pscustomobject]@{ExitCode=0}
      #|}
      #|$source=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($launcherEncoded))
      #|$block=[ScriptBlock]::Create($source)
      #|& $block 'VABlAHMAdAA='
      #|}
    let result = @host.run(
      powershell,
      ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", mock, encoded],
      current_dir(),
      15000,
    )
    if result.code != 0 {
      fail("mocked UAC launcher contract failed:\n" + result.output)
    }
    assert_true(result.output.contains("REPOWAYFINDER_ELEVATED_EXIT=0"))
  }
}

///|
test "Windows Docker distinguishes CLI-only from stopped Desktop" {
  assert_eq(classify_windows_docker(1, 1, 1), "broken")
  assert_eq(classify_windows_docker(0, 0, 1), "ready")
  assert_eq(classify_windows_docker(0, 1, 0), "waiting_environment")
  assert_eq(classify_windows_docker(0, 1, 1), "waiting_environment")
}

///|
test "MoonBit installer verification rejects blind execution primitives" {
  let reviewed =
    #|$MoonHome = $env:MOON_HOME
    #|$CLI_MOONBIT = "https://cli.moonbitlang.com"
    #|Invoke-WebRequest -Uri $MoonbitUri
    #|Expand-Archive x y
    #|moon.exe bundle
  assert_true(verified_moonbit_installer(reviewed))
  assert_false(
    verified_moonbit_installer(reviewed + "\nInvoke-Expression $payload"),
  )
  assert_false(
    verified_moonbit_installer(reviewed + "\nhttp://example.invalid"),
  )
}

///|
test "MoonBit installer transformation is exact and removes persistent writes" {
  let official =
    #|$MoonHome = $env:MOON_HOME
    #|$CLI_MOONBIT = "https://cli.moonbitlang.com"
    #|Invoke-WebRequest -Uri $MoonbitUri -OutFile "${HOME}\moonbit.zip"
    #|Expand-Archive "${HOME}\moonbit.zip" -DestinationPath $MoonHome -Force
    #|Remove-Item -Force "${HOME}\moonbit.zip"
    #|moon.exe bundle
    #|if ($env:Path -split ';' -notcontains $MoonBin) {
    #|  $currentPath = [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::User)
    #|  [System.Environment]::SetEnvironmentVariable("PATH", "$MoonBin;$currentPath", [System.EnvironmentVariableTarget]::User)
    #|
    #|  Write-Output "Added ~/.moon/bin to the PATH."
    #|  Write-Output "Please restart your terminal to use moonbit."
    #|}
    #|else {
    #|  Write-Output "Moonbit installed successfully."
    #|}
  guard portable_moonbit_installer(official) is Some(portable) else {
    fail("expected exact reviewed transformation")
  }
  assert_true(portable.contains("$MoonHome\\moonbit.zip"))
  assert_false(portable.contains("SetEnvironmentVariable(\"PATH\""))
  assert_true(portable.contains("未修改 PATH"))
  assert_eq(
    portable_moonbit_installer(
      official.replace_all(old="Please restart", new="Please reboot"),
    ),
    None,
  )
  assert_eq(
    portable_moonbit_installer(
      official + "\nSet-ItemProperty -Path HKCU:\\Software -Name test -Value 1",
    ),
    None,
  )
}

///|
test "ownership receipts fail closed when owner or root changes" {
  let valid =
    #|{"schema":1,"owner":"RepoWayfinder-MB","program":"pnpm","kind":"npm-local","package_id":"pnpm","tool_root":"C:/app/.repowayfinder-tools","version":"10.0.0"}
  assert_true(
    receipt_matches(
      valid, "pnpm", "npm-local", "pnpm", "C:/app/.repowayfinder-tools",
    ),
  )
  assert_false(receipt_matches(valid, "pnpm", "npm-local", "pnpm", "D:/other"))
  assert_false(
    receipt_matches(
      valid.replace_all(old="RepoWayfinder-MB", new="someone-else"),
      "pnpm",
      "npm-local",
      "pnpm",
      "C:/app/.repowayfinder-tools",
    ),
  )
}

///|
test "official no-winget artifacts are exact and bounded by independent identity" {
  assert_eq(
    mingit_url, "https://github.com/git-for-windows/git/releases/download/v2.55.0.windows.2/MinGit-2.55.0.2-64-bit.zip",
  )
  assert_true(valid_sha256(mingit_sha256))
  assert_false(valid_sha256(mingit_sha256 + "0"))
  assert_eq(
    python_direct_url, "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe",
  )
  assert_true(
    python_signature_valid(
      "Valid|CN=Python Software Foundation, O=Python Software Foundation, C=US",
    ),
  )
  assert_false(
    python_signature_valid("UnknownError|CN=Python Software Foundation"),
  )
  assert_false(python_signature_valid("Valid|CN=Unrelated Publisher"))
}

///|
test "Node LTS selection requires an exact official portable file marker" {
  let source =
    #|[
    #|  {"version":"v23.1.0","lts":false,"files":["win-x64-zip"]},
    #|  {"version":"v22.22.0","lts":"Jod","files":["linux-x64","win-x64-zip"]}
    #|]
  assert_eq(
    node_lts_archive(source),
    Some(
      (
        "v22.22.0", "node-v22.22.0-win-x64.zip", "https://nodejs.org/dist/v22.22.0/node-v22.22.0-win-x64.zip",
      ),
    ),
  )
  assert_eq(
    node_lts_archive(source.replace_all(old="win-x64-zip", new="win-arm64-zip")),
    None,
  )
  assert_eq(
    node_lts_archive(source.replace_all(old="v22.22.0", new="../../payload")),
    None,
  )
}

///|
test "Node checksum matching is exact and rejects path-like names" {
  let digest = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  let manifest = digest + "  node-v22.22.0-win-x64.zip\n"
  assert_eq(
    checksum_for_file(manifest, "node-v22.22.0-win-x64.zip"),
    Some(digest),
  )
  assert_eq(checksum_for_file(manifest, "node-v22.22.0-win-x64.msi"), None)
  assert_eq(checksum_for_file(manifest, "../node-v22.22.0-win-x64.zip"), None)
}

///|
test "python local receipt requires exact installer identity and owner root" {
  let digest = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  let valid = Json::object({
    "schema": Json(1),
    "owner": Json("RepoWayfinder-MB"),
    "program": Json("python"),
    "kind": Json("python-org-local"),
    "package_id": Json(
      "python.org/3.11.9/python-3.11.9-amd64.exe/sha256:" + digest,
    ),
    "tool_root": Json(@host.tool_root()),
    "version": Json("Python 3.11.9"),
  }).stringify()
  assert_eq(receipt_kind(valid), Some("python-org-local"))
  assert_eq(python_receipt_digest(valid), Some(digest))
  assert_true(
    receipt_matches(
      valid,
      "python",
      "python-org-local",
      "python.org/3.11.9/python-3.11.9-amd64.exe/sha256:" + digest,
      @host.tool_root(),
    ),
  )
  assert_eq(
    python_receipt_digest(valid.replace_all(old=digest, new=digest + "0")),
    None,
  )
}

///|
async test "uninstall is a no-op without explicit confirmation" {
  let result = uninstall(false)
  guard result is Object(object) else { fail("expected JSON object") }
  assert_eq(object.get("status"), Some(Json("confirmation_required")))
  assert_eq(object.get("changed"), Some(Json(false)))
}
