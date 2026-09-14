///|
test "probe classification distinguishes missing, broken and ready" {
  assert_eq(classify_probe(false, 127, false), "missing")
  assert_eq(classify_probe(true, 1, false), "broken")
  assert_eq(classify_probe(true, 0, true), "broken")
  assert_eq(classify_probe(true, 0, false), "ready")
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
  assert_eq(
    wsl_repair_action(0, "WSL2 不可用；请启用虚拟机平台。", false),
    "manual",
  )
  assert_eq(
    wsl_repair_action(
      1, "WSL2 内核缺失，请运行 wsl.exe --update。", false,
    ),
    "update",
  )
  assert_eq(
    wsl_repair_action(1, "WSL is not installed; run wsl --install", false),
    "install",
  )
}

///|
test "Windows Docker distinguishes CLI-only from stopped Desktop" {
  assert_eq(classify_windows_docker(1, 1, 1), "broken")
  assert_eq(classify_windows_docker(0, 0, 1), "ready")
  assert_eq(classify_windows_docker(0, 1, 0), "waiting_environment")
  assert_eq(classify_windows_docker(0, 1, 1), "missing")
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
  assert_true(portable.contains("PATH was not changed"))
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
async test "uninstall is a no-op without explicit confirmation" {
  let result = uninstall(false)
  guard result is Object(object) else { fail("expected JSON object") }
  assert_eq(object.get("status"), Some(Json("confirmation_required")))
  assert_eq(object.get("changed"), Some(Json(false)))
}
