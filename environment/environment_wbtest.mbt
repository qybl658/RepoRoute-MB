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
