///|
let official_moonbit_installer_url = "https://cli.moonbitlang.com/install/powershell.ps1"

///|
let mingit_version = "2.55.0.2"

///|
let mingit_filename = "MinGit-2.55.0.2-64-bit.zip"

///|
let mingit_url = "https://github.com/git-for-windows/git/releases/download/v2.55.0.windows.2/MinGit-2.55.0.2-64-bit.zip"

///|
/// SHA-256 published by the official Git for Windows GitHub release API.
let mingit_sha256 = "e3ea2944cea4b3fabcd69c7c1669ef69b1b66c05ac7806d81224d0abad2dec31"

///|
let node_index_url = "https://nodejs.org/dist/index.json"

///|
let python_direct_version = "3.11.9"

///|
let python_direct_filename = "python-3.11.9-amd64.exe"

///|
let python_direct_url = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"

///|
priv struct Probe {
  name : String
  executable : String?
  state : String
  detail : String
}

///|
fn current_dir() -> String {
  @env.current_dir().unwrap_or(".")
}

///|
fn normalize(program : String) -> String {
  match program.trim().to_lower() {
    "python3" | "py" => "python"
    "npm.cmd" => "npm"
    "docker.exe" => "docker"
    "moon.exe" => "moon"
    name => name.to_owned()
  }
}

///|
fn join(root : String, leaf : String) -> String {
  root +
  (if root.has_suffix("/") || root.has_suffix("\\") { "" } else { "/" }) +
  leaf
}

///|
fn receipt_path(program : String) -> String {
  join(@host.tool_root(), "receipt-" + normalize(program) + ".json")
}

///|
fn version_args(program : String) -> Array[String] {
  match normalize(program) {
    "python" => ["--version"]
    "docker" => ["--version"]
    "wsl" => ["--status"]
    _ => ["--version"]
  }
}

///|
fn system_package_id(program : String) -> String? {
  match normalize(program) {
    "git" => Some("Git.Git")
    "node" => Some("OpenJS.NodeJS.LTS")
    "python" => Some("Python.Python.3.13")
    "docker" => Some("Docker.DockerDesktop")
    _ => None
  }
}

///|
fn local_npm_package(program : String) -> String? {
  match normalize(program) {
    "pnpm" => Some("pnpm")
    "yarn" => Some("yarn")
    "bun" => Some("bun")
    _ => None
  }
}

///|
fn package_line(output : String, package_id : String) -> String? {
  for line in output.split("\n") {
    let owned = line.trim().to_owned()
    if owned.contains(package_id[:]) {
      return Some(owned)
    }
  }
  None
}

///|
fn winget_confirmed_absent(code : Int, output : String) -> Bool {
  code == -1978335212 ||
  output.contains("No installed package found") ||
  output.contains("No package found matching input criteria") ||
  output.contains("找不到与输入条件匹配的已安装程序包")
}

///|
fn resolve_alias(program : String) -> String? {
  let name = normalize(program)
  if name == "git" {
    let local_git = join(@host.tool_root(), "git/cmd/git.exe")
    if @fs.path_exists(local_git) &&
      (@fs.is_file(local_git) catch { _ => false }) {
      Some(local_git)
    } else {
      @host.resolve(name)
    }
  } else if name == "node" {
    let local_node = join(@host.tool_root(), "node/node.exe")
    if @fs.path_exists(local_node) &&
      (@fs.is_file(local_node) catch { _ => false }) {
      Some(local_node)
    } else {
      @host.resolve(name)
    }
  } else if name == "npm" {
    let local_npm = join(@host.tool_root(), "node/npm.cmd")
    if @fs.path_exists(local_npm) &&
      (@fs.is_file(local_npm) catch { _ => false }) {
      Some(local_npm)
    } else {
      @host.resolve(name)
    }
  } else if name == "moon" {
    let local_moon = join(@host.tool_root(), "moon/bin/moon.exe")
    if @fs.path_exists(local_moon) &&
      (@fs.is_file(local_moon) catch { _ => false }) {
      Some(local_moon)
    } else {
      @host.resolve(name)
    }
  } else if name == "python" {
    let local_python = join(@host.tool_root(), "python/python.exe")
    if @fs.path_exists(local_python) &&
      (@fs.is_file(local_python) catch { _ => false }) {
      return Some(local_python)
    }
    for candidate in ["python", "python3", "py"] {
      if @host.resolve(candidate) is Some(path) {
        return Some(path)
      }
    }
    None
  } else {
    @host.resolve(name)
  }
}

///|
fn classify_probe(found : Bool, code : Int, timed_out : Bool) -> String {
  if !found {
    "missing"
  } else if timed_out || code != 0 {
    "broken"
  } else {
    "ready"
  }
}

///|
/// Windows may expose a Store execution alias or the Python launcher even
/// when no Python runtime is installed. A failed probe there means the runtime
/// is missing, not that RepoWayfinder may overwrite a broken Python install.
fn python_placeholder_without_runtime(
  executable : String,
  code : Int,
  timed_out : Bool,
) -> Bool {
  let path = executable.replace_all(old="/", new="\\").to_lower()
  (code != 0 || timed_out) &&
  (path.contains("\\microsoft\\windowsapps\\") || path.has_suffix("\\py.exe"))
}

///|
fn wsl_status_needs_install(output : String) -> Bool {
  let text = output.to_lower()
  text.contains("wsl --install") ||
  text.contains("wsl.exe --install") ||
  text.contains("wsl is not installed") ||
  text.contains("windows subsystem for linux is not installed") ||
  text.contains("wsl 未安装") ||
  text.contains("wsl 尚未安装") ||
  text.contains("适用于 linux 的 windows 子系统未安装")
}

///|
fn wsl_status_needs_update(output : String) -> Bool {
  let text = output.to_lower()
  text.contains("wsl --update") ||
  text.contains("wsl.exe --update") ||
  (
    (text.contains("kernel") || text.contains("内核")) &&
    (
      text.contains("missing") ||
      text.contains("not found") ||
      text.contains("缺失") ||
      text.contains("找不到")
    )
  )
}

///|
fn wsl_status_has_platform_blocker(output : String) -> Bool {
  let text = output.to_lower()
  [
    "virtualization is not supported", "virtualization is disabled", "enable virtualization",
    "wsl 2 is not supported", "wsl2 is not supported", "wsl 2 is unavailable", "wsl2 is unavailable",
    "virtual machine platform", "不支持虚拟化", "虚拟化未启用", "虚拟化已禁用",
    "启用虚拟化", "wsl 2 不可用", "wsl2 不可用", "不支持 wsl 2", "不支持 wsl2",
    "虚拟机平台",
  ].any(marker => text.contains(marker[:]))
}

///|
fn wsl_status_ready(code : Int, output : String, timed_out : Bool) -> Bool {
  code == 0 &&
  !timed_out &&
  !wsl_status_needs_install(output) &&
  !wsl_status_needs_update(output) &&
  !wsl_status_has_platform_blocker(output)
}

///|
fn classify_windows_docker(
  cli_code : Int,
  daemon_code : Int,
  desktop_code : Int,
) -> String {
  if cli_code != 0 {
    "broken"
  } else if daemon_code == 0 {
    "ready"
  } else if desktop_code == 0 {
    "waiting_environment"
  } else {
    "missing"
  }
}

///|
async fn probe(program : String, cwd : String) -> Probe {
  let name = normalize(program)
  guard resolve_alias(name) is Some(executable) else {
    return {
      name,
      executable: None,
      state: "missing",
      detail: "Executable not found.",
    }
  }
  let result = @host.run(executable, version_args(name), cwd, 15000)
  if name == "wsl" {
    if wsl_status_ready(result.code, result.output, result.timed_out) {
      return {
        name,
        executable: Some(executable),
        state: "ready",
        detail: "WSL status probe succeeded without install, kernel-update, or virtualization blockers. Distribution choice and any pending restart remain user-owned.",
      }
    }
    return {
      name,
      executable: Some(executable),
      state: "waiting_environment",
      detail: "WSL command is present, but status indicates installation, kernel update, virtualization/Virtual Machine Platform, restart, or another user-owned setup is still required.\n" +
      result.output,
    }
  }
  let state = classify_probe(true, result.code, result.timed_out)
  if name == "python" &&
    python_placeholder_without_runtime(
      executable,
      result.code,
      result.timed_out,
    ) {
    return {
      name,
      executable: Some(executable),
      state: "missing",
      detail: "Windows exposes a Python launcher/Store alias, but its runtime probe failed. The launcher is preserved; a separate application-local Python may be prepared.\n" +
      result.output,
    }
  }
  if state != "ready" {
    return { name, executable: Some(executable), state, detail: result.output, }
  }
  if name == "docker" {
    let daemon = @host.run(executable, ["info"], cwd, 30000)
    if daemon.code != 0 || daemon.timed_out {
      if @host.windows() {
        let desktop = @host.run(executable, ["desktop", "version"], cwd, 30000)
        if classify_windows_docker(result.code, daemon.code, desktop.code) ==
          "missing" {
          return {
            name,
            executable: Some(executable),
            state: "missing",
            detail: "Docker CLI exists, but neither a daemon nor the Docker Desktop management interface is available. Docker Desktop is still a missing runtime; the CLI alone is insufficient.\n" +
            daemon.output +
            "\n" +
            desktop.output,
          }
        }
      }
      return {
        name,
        executable: Some(executable),
        state: "waiting_environment",
        detail: result.output +
        "\nDocker CLI is installed, but Docker Desktop/daemon is not ready. Start Docker Desktop, complete its license and WSL/virtualization setup yourself, then retry.\n" +
        daemon.output,
      }
    }
  }
  { name, executable: Some(executable), state: "ready", detail: result.output, }
}

///|
fn probe_json(value : Probe) -> Json {
  Json({
    "program": value.name,
    "state": value.state,
    "executable": value.executable.unwrap_or(""),
    "detail": value.detail,
  })
}

///|
fn ensure_tool_root() -> Bool {
  let root = @host.tool_root()
  if @fs.path_exists(root) {
    return @fs.is_dir(root) catch { _ => false }
  }
  try {
    @fs.create_dir(root)
    true
  } catch {
    _ => {
      println("Cannot create application-local tool directory: \{root}.")
      false
    }
  }
}

///|
fn write_receipt(
  program : String,
  kind : String,
  package_id : String,
  version : String,
) -> Bool {
  guard ensure_tool_root() else { return false }
  let receipt = Json::object({
    "schema": Json(1),
    "owner": Json("RepoWayfinder-MB"),
    "program": Json(normalize(program)),
    "kind": Json(kind),
    "package_id": Json(package_id),
    "tool_root": Json(@host.tool_root()),
    "version": Json(version),
  })
  try {
    @fs.write_string_to_file(receipt_path(program), receipt.stringify(indent=2))
    true
  } catch {
    _ => {
      println("Installed, but could not write the ownership receipt.")
      false
    }
  }
}

///|
fn object_string(object : Map[String, Json], key : String) -> String? {
  match object.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn receipt_matches(
  content : String,
  program : String,
  kind : String,
  package_id : String,
  root : String,
) -> Bool {
  guard (@json.parse(content) catch { _ => Json::null() }) is Object(object) else {
    return false
  }
  object.get("schema") == Some(Json(1)) &&
  object_string(object, "owner") == Some("RepoWayfinder-MB") &&
  object_string(object, "program") == Some(normalize(program)) &&
  object_string(object, "kind") == Some(kind) &&
  object_string(object, "package_id") == Some(package_id) &&
  object_string(object, "tool_root") == Some(root)
}

///|
fn read_receipt(program : String) -> String? {
  let path = receipt_path(program)
  if !@fs.path_exists(path) {
    return None
  }
  Some(@fs.read_file_to_string(path)) catch {
    _ => None
  }
}

///|
fn receipt_version(content : String) -> String? {
  guard (@json.parse(content) catch { _ => Json::null() }) is Object(object) else {
    return None
  }
  object_string(object, "version")
}

///|
fn receipt_kind(content : String) -> String? {
  guard (@json.parse(content) catch { _ => Json::null() }) is Object(object) else {
    return None
  }
  object_string(object, "kind")
}

///|
fn receipt_package_id(content : String) -> String? {
  guard (@json.parse(content) catch { _ => Json::null() }) is Object(object) else {
    return None
  }
  object_string(object, "package_id")
}

///|
/// Return the recorded installer digest only when every fixed Python receipt
/// field and the digest-bearing package identity match exactly.
fn python_receipt_digest(content : String) -> String? {
  let prefix = "python.org/" +
    python_direct_version +
    "/" +
    python_direct_filename +
    "/sha256:"
  guard receipt_package_id(content) is Some(package_id) &&
    package_id.has_prefix(prefix) else {
    return None
  }
  let digest = package_id[prefix.length():].to_lower().to_owned()
  guard valid_sha256(digest) &&
    receipt_matches(
      content,
      "python",
      "python-org-local",
      prefix + digest,
      @host.tool_root(),
    ) else {
    return None
  }
  Some(digest)
}

///|
async fn current_version(program : String, cwd : String) -> String? {
  guard resolve_alias(program) is Some(executable) else { return None }
  let args = if normalize(program) == "wsl" {
    ["--version"]
  } else {
    version_args(program)
  }
  let result = @host.run(executable, args, cwd, 30000)
  if result.code == 0 && !result.timed_out {
    Some(result.output.trim().to_owned())
  } else {
    None
  }
}

///|
fn remove_receipt(program : String) -> Unit {
  let path = receipt_path(program)
  if @fs.path_exists(path) {
    @fs.remove_file(path) catch {
      _ => println("Could not remove receipt \{path}.")
    }
  }
}

///|
fn powershell_literal(value : String) -> String? {
  if value.contains("\u{0000}") || value.contains("\r") || value.contains("\n") {
    None
  } else {
    Some("'" + value.replace_all(old="'", new="''") + "'")
  }
}

///|
fn valid_sha256(value : String) -> Bool {
  value.length() == 64 &&
  value
  .iter()
  .all(c => {
    (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
  })
}

///|
fn trusted_node_version(value : String) -> Bool {
  value.has_prefix("v") &&
  value.length() >= 6 &&
  value[1:].split(".").length() == 3 &&
  value[1:].iter().all(c => (c >= '0' && c <= '9') || c == '.')
}

///|
/// Select the first official LTS release that actually publishes a Windows
/// x64 portable archive. nodejs.org orders index.json newest first.
fn node_lts_archive(index_source : String) -> (String, String, String)? {
  guard (@json.parse(index_source) catch { _ => Json::null() }) is Array(items) else {
    return None
  }
  for item in items {
    guard item is Object(object) &&
      object_string(object, "version") is Some(version) &&
      trusted_node_version(version) &&
      object.get("lts") is Some(String(_)) &&
      object.get("files") is Some(Array(files)) else {
      continue
    }
    let has_windows_archive = files.any(value => {
      match value {
        String(name) => name == "win-x64-zip"
        _ => false
      }
    })
    if has_windows_archive {
      let filename = "node-" + version + "-win-x64.zip"
      return Some(
        (
          version,
          filename,
          "https://nodejs.org/dist/" + version + "/" + filename,
        ),
      )
    }
  }
  None
}

///|
fn checksum_for_file(source : String, filename : String) -> String? {
  if filename.contains("/") || filename.contains("\\") {
    return None
  }
  for line in source.replace_all(old="\r\n", new="\n").split("\n") {
    let fields = line.trim().split("  ").collect()
    if fields.length() == 2 && fields[1] == filename {
      let digest = fields[0].to_lower().to_owned()
      if valid_sha256(digest) {
        return Some(digest)
      }
    }
  }
  None
}

///|
/// Download an exact HTTPS URL without shell interpolation. The reviewed
/// PowerShell body enforces both Content-Length (when supplied) and a streaming
/// byte ceiling, writes a new .part file, then atomically promotes it.
async fn download_bounded(
  url : String,
  destination : String,
  minimum_bytes : Int64,
  maximum_bytes : Int64,
  cwd : String,
) -> Bool {
  guard url.has_prefix("https://") &&
    minimum_bytes > 0L &&
    maximum_bytes >= minimum_bytes else {
    return false
  }
  guard @host.resolve("powershell") is Some(powershell) else {
    println(
      "WAITING_ENVIRONMENT: PowerShell is required for verified downloads.",
    )
    return false
  }
  if @fs.path_exists(destination) {
    // Callers still verify an official checksum or publisher signature before
    // use. Reuse is allowed only if the file still satisfies the same bounds.
    let checked = @host.run(
      powershell,
      [
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "& { param($path,[int64]$minimum,[int64]$maximum) $ErrorActionPreference='Stop'; $length=(Get-Item -LiteralPath $path).Length; if ($length -lt $minimum -or $length -gt $maximum) { exit 3 } }",
        destination,
        minimum_bytes.to_string(),
        maximum_bytes.to_string(),
      ],
      cwd,
      15000,
    )
    return checked.code == 0 && !checked.timed_out
  }
  let partial = destination + ".part"
  if @fs.path_exists(partial) {
    println(
      "WAITING_ENVIRONMENT: a prior bounded download is unresolved; preserving it instead of overwriting: " +
      partial,
    )
    return false
  }
  let script =
    #|& { param($url,$partial,$destination,[int64]$minimum,[int64]$maximum)
    #|$ErrorActionPreference='Stop'
    #|if (-not $url.StartsWith('https://',[StringComparison]::Ordinal)) { throw 'HTTPS required' }
    #|$request=[Net.HttpWebRequest]::Create($url)
    #|$request.AllowAutoRedirect=$true; $request.MaximumAutomaticRedirections=5
    #|$request.UserAgent='RepoWayfinder-MB prerequisite bootstrap'
    #|$response=$null; $input=$null; $output=$null
    #|try {
    #|  $response=$request.GetResponse()
    #|  if ($response.ContentLength -gt $maximum) { throw 'Content-Length exceeds byte ceiling' }
    #|  $input=$response.GetResponseStream()
    #|  $output=[IO.File]::Open($partial,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    #|  $buffer=New-Object byte[] 65536; [int64]$total=0
    #|  while (($read=$input.Read($buffer,0,$buffer.Length)) -gt 0) {
    #|    $total += $read; if ($total -gt $maximum) { throw 'download exceeds byte ceiling' }
    #|    $output.Write($buffer,0,$read)
    #|  }
    #|  if ($total -lt $minimum) { throw 'download is below byte floor' }
    #|} finally {
    #|  if ($output) { $output.Dispose() }; if ($input) { $input.Dispose() }; if ($response) { $response.Dispose() }
    #|}
    #|[IO.File]::Move($partial,$destination)
    #|}
  let result = @host.run(
    powershell,
    [
      "-NoLogo",
      "-NoProfile",
      "-NonInteractive",
      "-Command",
      script,
      url,
      partial,
      destination,
      minimum_bytes.to_string(),
      maximum_bytes.to_string(),
    ],
    cwd,
    360000,
  )
  if result.code != 0 || result.timed_out || !@fs.path_exists(destination) {
    println(
      "WAITING_ENVIRONMENT: bounded official download failed; no installer/archive was executed.\n" +
      result.output,
    )
    return false
  }
  true
}

///|
async fn file_sha256(path : String, cwd : String) -> String? {
  guard @host.resolve("powershell") is Some(powershell) else { return None }
  let result = @host.run(
    powershell,
    [
      "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", "& { param($path) $ErrorActionPreference='Stop'; (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() }",
      path,
    ],
    cwd,
    30000,
  )
  let digest = result.output.trim().to_lower().to_owned()
  if result.code == 0 && !result.timed_out && valid_sha256(digest) {
    Some(digest)
  } else {
    None
  }
}

///|
async fn extract_portable_zip(
  archive : String,
  target : String,
  expected_executable : String,
  cwd : String,
) -> Bool {
  if @fs.path_exists(target) || @fs.path_exists(target + ".extracting") {
    println(
      "WAITING_ENVIRONMENT: portable target or preserved extraction state already exists; nothing was overwritten: " +
      target,
    )
    return false
  }
  guard @host.resolve("powershell") is Some(powershell) else { return false }
  let script =
    #|& { param($archive,$target,$expected)
    #|$ErrorActionPreference='Stop'
    #|Add-Type -AssemblyName System.IO.Compression.FileSystem
    #|$stage=$target+'.extracting'
    #|$root=[IO.Path]::GetFullPath($stage+[IO.Path]::DirectorySeparatorChar)
    #|$zip=[IO.Compression.ZipFile]::OpenRead($archive)
    #|try {
    #|  foreach ($entry in $zip.Entries) {
    #|    if ([IO.Path]::IsPathRooted($entry.FullName)) { throw 'rooted zip entry rejected' }
    #|    $candidate=[IO.Path]::GetFullPath((Join-Path $stage $entry.FullName))
    #|    if (-not $candidate.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'zip path escape rejected' }
    #|  }
    #|} finally { $zip.Dispose() }
    #|[IO.Compression.ZipFile]::ExtractToDirectory($archive,$stage)
    #|$source=$stage
    #|if (-not (Test-Path -LiteralPath (Join-Path $source $expected) -PathType Leaf)) {
    #|  $items=@(Get-ChildItem -LiteralPath $stage -Force)
    #|  if ($items.Count -ne 1 -or -not $items[0].PSIsContainer -or -not (Test-Path -LiteralPath (Join-Path $items[0].FullName $expected) -PathType Leaf)) { throw 'archive layout mismatch' }
    #|  $source=$items[0].FullName
    #|}
    #|Move-Item -LiteralPath $source -Destination $target
    #|if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage }
    #|}
  let result = @host.run(
    powershell,
    [
      "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script, archive, target,
      expected_executable,
    ],
    cwd,
    180000,
  )
  if result.code == 0 &&
    !result.timed_out &&
    @fs.path_exists(join(target, expected_executable)) {
    true
  } else {
    println(
      "WAITING_ENVIRONMENT: safe portable extraction failed. Partial state was preserved for inspection and will not be overwritten.\n" +
      result.output,
    )
    false
  }
}

///|
fn verified_moonbit_installer(source : String) -> Bool {
  source.contains("$CLI_MOONBIT = \"https://cli.moonbitlang.com\"") &&
  source.contains("$MoonHome = $env:MOON_HOME") &&
  source.contains("Invoke-WebRequest -Uri $MoonbitUri") &&
  source.contains("Expand-Archive") &&
  source.contains("moon.exe bundle") &&
  !source.contains("http://") &&
  !source.to_lower().contains("invoke-expression") &&
  !source.to_lower().contains("start-process") &&
  !source.to_lower().contains("frombase64string") &&
  !source.to_lower().contains("-encodedcommand")
}

///|
fn portable_moonbit_installer(source : String) -> String? {
  let normalized = source.replace_all(old="\r\n", new="\n")
  guard verified_moonbit_installer(normalized) else { return None }
  let archive_in_user_dir = "$" + "{HOME}\\moonbit.zip"
  let archive_in_toolchain = "$MoonHome\\moonbit.zip"
  let persistent_path_block =
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
  let portable_path_block =
    #|if ($env:Path -split ';' -notcontains $MoonBin) {
    #|  Write-Output "MoonBit installed in an application-local directory."
    #|  Write-Output "PATH was not changed. RepoWayfinder supplies it only to child processes."
    #|}
    #|else {
    #|  Write-Output "Moonbit installed successfully."
    #|}
  // The reviewed official script currently uses the archive path exactly three
  // times and contains exactly one persistent user-PATH block. Any source drift
  // fails closed instead of applying a broad or approximate rewrite.
  guard normalized.split(archive_in_user_dir).length() == 4 &&
    normalized.split(persistent_path_block).length() == 2 else {
    return None
  }
  let transformed = normalized
    .replace_all(old=archive_in_user_dir, new=archive_in_toolchain)
    .replace_all(old=persistent_path_block, new=portable_path_block)
  let transformed_lower = transformed.to_lower()
  if transformed.contains(archive_in_user_dir) ||
    transformed_lower.contains("setenvironmentvariable(") ||
    transformed_lower.contains("set-itemproperty") ||
    transformed_lower.contains("new-itemproperty") ||
    transformed_lower.contains("setx ") ||
    transformed_lower.contains("schtasks") ||
    transformed_lower.contains("register-scheduledtask") {
    None
  } else {
    Some(transformed)
  }
}

///|
async fn install_moonbit(cwd : String) -> Bool {
  guard @host.windows() else {
    println(
      "MoonBit automatic bootstrap is currently implemented only for Windows. Install MoonBit from the official download page and retry.",
    )
    return false
  }
  guard ensure_tool_root() else { return false }
  guard @host.resolve("powershell") is Some(powershell) else {
    println(
      "WAITING_ENVIRONMENT: Windows PowerShell is unavailable, so the official MoonBit installer source cannot be downloaded and inspected.",
    )
    return false
  }
  let script_path = join(@host.tool_root(), "moonbit-official-installer.ps1")
  let moon_home = join(@host.tool_root(), "moon")
  if @fs.path_exists(moon_home) {
    println(
      "WAITING_ENVIRONMENT: the intended application-local MoonBit directory already exists but no working moon executable was found. It may contain a partial or user-modified install, so RepoWayfinder will not overwrite it: " +
      moon_home,
    )
    return false
  }
  guard powershell_literal(official_moonbit_installer_url) is Some(url) &&
    powershell_literal(script_path) is Some(destination) else {
    println("Unsupported characters in MoonBit bootstrap path.")
    return false
  }
  if !@fs.path_exists(script_path) {
    let download = @host.run(
      powershell,
      [
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "$ErrorActionPreference='Stop'; Invoke-WebRequest -UseBasicParsing -Uri " +
        url +
        " -OutFile " +
        destination,
      ],
      cwd,
      120000,
    )
    if download.code != 0 || download.timed_out || !@fs.path_exists(script_path) {
      println(
        "WAITING_ENVIRONMENT: Could not download the official MoonBit installer source. No installer was executed.\n" +
        download.output,
      )
      return false
    }
  }
  let source = @fs.read_file_to_string(script_path) catch {
    _ => {
      println(
        "Downloaded MoonBit installer could not be read; it was not executed.",
      )
      return false
    }
  }
  guard portable_moonbit_installer(source) is Some(portable_source) else {
    println(
      "The downloaded MoonBit installer did not match the exact reviewed portable transformation; it was not executed. Inspect: " +
      script_path,
    )
    return false
  }
  let portable_script_path = join(
    @host.tool_root(),
    "moonbit-reviewed-portable-installer.ps1",
  )
  if @fs.path_exists(portable_script_path) {
    let existing = @fs.read_file_to_string(portable_script_path) catch {
      _ => {
        println(
          "Existing transformed MoonBit installer cannot be read; preserving it and stopping.",
        )
        return false
      }
    }
    if existing != portable_source {
      println(
        "Existing transformed MoonBit installer differs from the reviewed result; preserving it and stopping: " +
        portable_script_path,
      )
      return false
    }
  } else {
    @fs.write_string_to_file(portable_script_path, portable_source) catch {
      _ => {
        println(
          "Could not write the reviewed portable MoonBit installer; nothing was executed.",
        )
        return false
      }
    }
  }
  let moon_bin = join(moon_home, "bin")
  guard powershell_literal(moon_home) is Some(home) &&
    powershell_literal(moon_bin) is Some(bin) &&
    powershell_literal(portable_script_path) is Some(portable_destination) else {
    println("Unsupported characters in MoonBit install path.")
    return false
  }
  let install = @host.run(
    powershell,
    [
      "-NoLogo",
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "Bypass",
      "-Command",
      "$ErrorActionPreference='Stop'; $env:MOON_HOME=" +
      home +
      "; $env:Path=" +
      bin +
      "+';'+$env:Path; & " +
      portable_destination,
    ],
    cwd,
    600000,
  )
  let moon_exe = join(moon_bin, "moon.exe")
  if install.code != 0 || install.timed_out || !@fs.path_exists(moon_exe) {
    println(
      "WAITING_ENVIRONMENT: The reviewed MoonBit installer did not complete. The source is retained for inspection.\n" +
      install.output,
    )
    return false
  }
  let checked = @host.run(moon_exe, ["--version"], cwd, 30000)
  if checked.code != 0 || checked.timed_out {
    println(
      "MoonBit files were created, but the installed compiler probe failed. No success receipt was written.\n" +
      checked.output,
    )
    return false
  }
  write_receipt(
    "moon",
    "moonbit-local",
    "MoonBit.CLI",
    checked.output.trim().to_owned(),
  )
}

///|
async fn install_local_npm(
  program : String,
  package_name : String,
  cwd : String,
) -> Bool {
  guard resolve_alias("npm") is Some(npm) else {
    println(
      "WAITING_ENVIRONMENT: npm is required for an application-local \{program} install. Install/repair Node.js first.",
    )
    return false
  }
  guard ensure_tool_root() else { return false }
  let package_dir = join(@host.tool_root(), "node_modules/" + package_name)
  if @fs.path_exists(package_dir) {
    println(
      "WAITING_ENVIRONMENT: an application-local \{package_name} directory already exists but no working executable was found. RepoWayfinder will not overwrite possibly modified or partial files: " +
      package_dir,
    )
    return false
  }
  let result = @host.run(
    npm,
    [
      "install",
      "--global=false",
      "--registry=https://registry.npmjs.org",
      "--prefix",
      @host.tool_root(),
      "--no-save",
      "--no-package-lock",
      package_name + "@latest",
    ],
    cwd,
    300000,
  )
  if result.code != 0 || result.timed_out {
    println(
      "Application-local \{program} install failed. No ownership receipt was written.\n" +
      result.output,
    )
    return false
  }
  let checked = probe(program, cwd)
  if checked.state != "ready" {
    println(
      "\{program} was downloaded locally but its version probe failed. No success receipt was written.\n" +
      checked.detail,
    )
    return false
  }
  write_receipt(
    program,
    "npm-local",
    package_name,
    checked.detail.trim().to_owned(),
  )
}

///|
async fn windows_x64(cwd : String) -> Bool {
  guard @host.resolve("powershell") is Some(powershell) else { return false }
  let result = @host.run(
    powershell,
    [
      "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", "[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()",
    ],
    cwd,
    15000,
  )
  result.code == 0 &&
  !result.timed_out &&
  result.output.trim().to_lower() == "x64"
}

///|
async fn install_portable_git(cwd : String) -> Bool {
  guard windows_x64(cwd) else {
    println(
      "WAITING_ENVIRONMENT: the reviewed MinGit fallback supports Windows x64 only. Install Git for Windows for this architecture from its official publisher.",
    )
    return false
  }
  guard ensure_tool_root() else { return false }
  let archive = join(@host.tool_root(), mingit_filename)
  let target = join(@host.tool_root(), "git")
  if @fs.path_exists(target) {
    println(
      "WAITING_ENVIRONMENT: application-local Git target exists without a working executable. It is preserved as possibly partial or modified: " +
      target,
    )
    return false
  }
  guard download_bounded(mingit_url, archive, 10000000L, 100000000L, cwd) else {
    return false
  }
  guard file_sha256(archive, cwd) == Some(mingit_sha256) else {
    println(
      "WAITING_ENVIRONMENT: MinGit SHA-256 does not match the official Git for Windows release asset. The archive was not extracted: " +
      archive,
    )
    return false
  }
  guard extract_portable_zip(archive, target, "cmd/git.exe", cwd) else {
    return false
  }
  let checked = probe("git", cwd)
  if checked.state != "ready" {
    println(
      "Application-local MinGit was extracted, but its version probe failed. No ownership receipt was written.\n" +
      checked.detail,
    )
    return false
  }
  let recorded = write_receipt(
    "git",
    "portable-local",
    "GitForWindows.MinGit/" + mingit_version + "/" + mingit_sha256,
    checked.detail.trim().to_owned(),
  )
  if recorded {
    @fs.remove_file(archive) catch {
      _ => ()
    }
  }
  recorded
}

///|
async fn install_portable_node(cwd : String) -> Bool {
  guard windows_x64(cwd) else {
    println(
      "WAITING_ENVIRONMENT: the official Node portable fallback supports Windows x64 only. Install a supported Node.js build for this architecture.",
    )
    return false
  }
  guard ensure_tool_root() else { return false }
  let target = join(@host.tool_root(), "node")
  if @fs.path_exists(target) {
    println(
      "WAITING_ENVIRONMENT: application-local Node target exists without working node/npm executables. It is preserved as possibly partial or modified: " +
      target,
    )
    return false
  }
  let index_path = join(@host.tool_root(), "node-official-index.json")
  guard download_bounded(node_index_url, index_path, 1000L, 5000000L, cwd) else {
    return false
  }
  let index_source = @fs.read_file_to_string(index_path) catch {
    _ => {
      println("Downloaded official Node release index could not be read.")
      return false
    }
  }
  guard node_lts_archive(index_source) is Some((version, filename, url)) else {
    println(
      "WAITING_ENVIRONMENT: nodejs.org index has no structurally valid LTS Windows x64 portable archive; source drift was not guessed around.",
    )
    return false
  }
  let sums_url = "https://nodejs.org/dist/" + version + "/SHASUMS256.txt"
  let sums_path = join(@host.tool_root(), "node-" + version + "-SHASUMS256.txt")
  guard download_bounded(sums_url, sums_path, 100L, 5000000L, cwd) else {
    return false
  }
  let sums = @fs.read_file_to_string(sums_path) catch {
    _ => {
      println("Downloaded official Node checksum manifest could not be read.")
      return false
    }
  }
  guard checksum_for_file(sums, filename) is Some(expected_sha256) else {
    println(
      "WAITING_ENVIRONMENT: official Node checksum manifest has no exact entry for " +
      filename +
      "; archive was not downloaded.",
    )
    return false
  }
  let archive = join(@host.tool_root(), filename)
  guard download_bounded(url, archive, 10000000L, 250000000L, cwd) else {
    return false
  }
  guard file_sha256(archive, cwd) == Some(expected_sha256) else {
    println(
      "WAITING_ENVIRONMENT: Node archive SHA-256 does not match the exact official SHASUMS256.txt entry. It was not extracted: " +
      archive,
    )
    return false
  }
  guard extract_portable_zip(archive, target, "node.exe", cwd) else {
    return false
  }
  let node_checked = probe("node", cwd)
  let npm_checked = probe("npm", cwd)
  if node_checked.state != "ready" || npm_checked.state != "ready" {
    println(
      "Application-local Node was extracted, but node and npm did not both pass version probes. No ownership receipt was written.\nnode: " +
      node_checked.detail +
      "\nnpm: " +
      npm_checked.detail,
    )
    return false
  }
  let recorded = write_receipt(
    "node",
    "portable-local",
    "Node.js/" + version + "/" + expected_sha256,
    node_checked.detail.trim().to_owned(),
  )
  if recorded {
    @fs.remove_file(archive) catch {
      _ => ()
    }
  }
  recorded
}

///|
fn python_signature_valid(output : String) -> Bool {
  let text = output.trim().to_lower()
  text.has_prefix("valid|") && text.contains("python software foundation")
}

///|
async fn verified_python_installer(path : String, cwd : String) -> Bool {
  guard @host.resolve("powershell") is Some(powershell) else { return false }
  let result = @host.run(
    powershell,
    [
      "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", "& { param($path) $ErrorActionPreference='Stop'; $signature=Get-AuthenticodeSignature -LiteralPath $path; $signature.Status.ToString()+'|'+$signature.SignerCertificate.Subject }",
      path,
    ],
    cwd,
    30000,
  )
  result.code == 0 && !result.timed_out && python_signature_valid(result.output)
}

///|
async fn install_local_python(cwd : String) -> Bool {
  guard windows_x64(cwd) else {
    println(
      "WAITING_ENVIRONMENT: the reviewed python.org fallback is the Windows x64 installer only. Select an official installer for this architecture yourself.",
    )
    return false
  }
  guard ensure_tool_root() else { return false }
  let target = join(@host.tool_root(), "python")
  let executable = join(target, "python.exe")
  let installer = join(@host.tool_root(), python_direct_filename)
  if @fs.path_exists(target) {
    println(
      "WAITING_ENVIRONMENT: application-local Python target exists without a working executable. It is preserved as possibly partial or modified: " +
      target,
    )
    return false
  }
  if @fs.path_exists(installer) {
    println(
      "WAITING_ENVIRONMENT: an unowned file already occupies the exact Python installer path. It will not be reused or overwritten: " +
      installer,
    )
    return false
  }
  guard download_bounded(
    python_direct_url, installer, 10000000L, 100000000L, cwd,
  ) else {
    return false
  }
  guard verified_python_installer(installer, cwd) else {
    println(
      "WAITING_ENVIRONMENT: the downloaded Python installer does not have a valid Python Software Foundation Authenticode signature. It was not executed: " +
      installer,
    )
    return false
  }
  guard file_sha256(installer, cwd) is Some(installer_sha256) else {
    println(
      "WAITING_ENVIRONMENT: the signed Python installer SHA-256 could not be recorded, so it was not executed.",
    )
    return false
  }
  println(
    "The exact signed python.org installer will run visibly in passive, current-user mode. It will not change PATH, install the launcher, request a restart, or auto-answer UAC. Any Windows/license prompt remains yours.",
  )
  let result = @host.run(
    installer,
    [
      "/passive",
      "/norestart",
      "InstallAllUsers=0",
      "TargetDir=" + target,
      "PrependPath=0",
      "Include_launcher=0",
      "Include_pip=1",
      "Include_tcltk=0",
      "Include_test=0",
      "SimpleInstall=1",
    ],
    cwd,
    600000,
  )
  if result.code != 0 || result.timed_out || !@fs.path_exists(executable) {
    println(
      "WAITING_ENVIRONMENT: the official Python installer did not create the exact requested local runtime. No ownership receipt was written; installer and partial state are preserved for diagnosis.\n" +
      result.output,
    )
    return false
  }
  let checked = probe("python", cwd)
  if checked.state != "ready" ||
    checked.detail.trim() != "Python " + python_direct_version {
    println(
      "Local Python exists, but its exact installed version did not pass verification. No ownership receipt was written.\n" +
      checked.detail,
    )
    return false
  }
  write_receipt(
    "python",
    "python-org-local",
    "python.org/" +
    python_direct_version +
    "/" +
    python_direct_filename +
    "/sha256:" +
    installer_sha256,
    checked.detail.trim().to_owned(),
  )
}

///|
async fn install_official_fallback(program : String, cwd : String) -> Bool {
  match normalize(program) {
    "git" => install_portable_git(cwd)
    "node" => install_portable_node(cwd)
    "python" => install_local_python(cwd)
    _ => {
      println(
        "WAITING_ENVIRONMENT: no reviewed official no-winget fallback is implemented for " +
        program +
        ".",
      )
      false
    }
  }
}

///|
async fn install_system(
  program : String,
  package_id : String,
  cwd : String,
) -> Bool {
  guard @host.windows() else {
    println(
      "Automatic system prerequisite installation is unsupported on this platform. Install \{program} with your supported package manager, then retry.",
    )
    return false
  }
  guard @host.resolve("winget") is Some(winget) else {
    if normalize(program) == "git" ||
      normalize(program) == "node" ||
      normalize(program) == "python" {
      println(
        "winget is absent. Using the reviewed official application-local fallback; no system PATH, package-manager, service, auto-start, or machine setting will be changed.",
      )
      return install_official_fallback(program, cwd)
    }
    println(
      "WAITING_ENVIRONMENT: winget is unavailable and no safe official local fallback is implemented for \{package_id}. Install it from its official publisher and retry.",
    )
    return false
  }
  let before = @host.run(
    winget,
    ["list", "--id", package_id, "--exact", "--source", "winget"],
    cwd,
    60000,
  )
  if before.code == 0 && before.output.contains(package_id[:]) {
    println(
      "WAITING_ENVIRONMENT: winget reports \{package_id} is already installed, but \{program} was not usable. It is pre-existing or broken, so RepoWayfinder will not upgrade it or claim ownership. Repair it from Windows Installed Apps or its official publisher.",
    )
    return false
  }
  if !winget_confirmed_absent(before.code, before.output) {
    println(
      "WAITING_ENVIRONMENT: winget could not prove that \{package_id} is absent. RepoWayfinder will not risk upgrading an existing package or claiming ownership.\n" +
      before.output,
    )
    return false
  }
  println(
    "winget will use exact package ID \{package_id}. RepoWayfinder does not pass license/source auto-accept flags and will not request a restart or upgrade an existing tool.",
  )
  let result = @host.run(
    winget,
    ["install", "--id", package_id, "--exact", "--source", "winget"],
    cwd,
    600000,
  )
  if result.code != 0 || result.timed_out {
    println(
      "WAITING_ENVIRONMENT: winget did not complete. Review any package license/UAC request yourself; no success receipt was written.\n" +
      result.output,
    )
    return false
  }
  let after = @host.run(
    winget,
    ["list", "--id", package_id, "--exact", "--source", "winget"],
    cwd,
    60000,
  )
  guard after.code == 0 &&
    package_line(after.output, package_id) is Some(installed_line) else {
    println(
      "winget returned success, but a new exact package record could not be verified. No ownership receipt was written.\n" +
      after.output,
    )
    return false
  }
  let checked = probe(program, cwd)
  let recorded = write_receipt(
    program, "winget-system", package_id, installed_line,
  )
  if normalize(program) == "docker" {
    println(
      "WAITING_ENVIRONMENT: package installation completed, but Windows/Docker readiness must be completed and verified separately. RepoWayfinder will not accept a license, enable firmware virtualization, elevate itself, or reboot Windows.",
    )
    return false
  }
  if checked.state != "ready" {
    println(
      "WAITING_ENVIRONMENT: installation completed, but \{program} is not ready in this process. Restart the terminal if the installer changed PATH, then retry.\n" +
      checked.detail,
    )
    return false
  }
  recorded
}

///|
fn wsl_repair_action(
  status_code : Int,
  output : String,
  timed_out : Bool,
) -> String {
  if wsl_status_ready(status_code, output, timed_out) {
    "none"
  } else if wsl_status_needs_install(output) {
    "install"
  } else if wsl_status_needs_update(output) {
    "update"
  } else {
    "manual"
  }
}

///|
fn wsl_waiting_marker_path() -> String {
  join(@host.tool_root(), "wsl-maintenance-waiting.json")
}

///|
async fn repair_docker(cwd : String, allow_install : Bool) -> Bool {
  guard @host.windows() else {
    println(
      "WAITING_ENVIRONMENT: Docker daemon is unavailable. Automatic Docker Desktop start is implemented only on Windows; start the supported daemon for this platform yourself.",
    )
    return false
  }
  guard @host.resolve("docker") is Some(docker) else { return false }
  if !allow_install {
    println(
      "WAITING_ENVIRONMENT: Docker CLI is installed but the daemon is stopped or unavailable. Starting Docker Desktop is disabled for this run; the existing installation will not be reinstalled.",
    )
    return false
  }
  guard @host.prompt(
    "Docker is installed but its daemon is not ready. Allow the official `docker desktop start` command? You must review/accept any Docker license or first-run UI yourself; RepoWayfinder will not reinstall Docker.",
  ) else {
    println(
      "WAITING_ENVIRONMENT: Docker Desktop start was declined (default is No).",
    )
    return false
  }
  let started = @host.run(docker, ["desktop", "start"], cwd, 120000)
  if started.code != 0 || started.timed_out {
    println(
      "WAITING_ENVIRONMENT: Docker Desktop did not start through its official CLI. Complete WSL/virtualization/license setup or start it yourself; no reinstall was attempted.\n" +
      started.output,
    )
    return false
  }
  let after = probe("docker", cwd)
  if after.state == "ready" {
    true
  } else {
    println(
      "WAITING_ENVIRONMENT: Docker Desktop start returned successfully, but the daemon is not ready. Complete its visible first-run/license/WSL setup and retry; no reinstall was attempted.\n" +
      after.detail,
    )
    false
  }
}

///|
async fn repair_wsl(cwd : String, allow_install : Bool) -> Bool {
  guard @host.windows() else {
    println("WSL repair is available only on Windows.")
    return false
  }
  guard @host.resolve("wsl") is Some(wsl) else {
    println(
      "WAITING_ENVIRONMENT: the Windows WSL command is absent. RepoWayfinder cannot safely enable Windows features through a hidden/elevated helper. Open an Administrator terminal, review `wsl --install --no-distribution`, then restart only if Windows asks.",
    )
    return false
  }
  let status = @host.run(wsl, ["--status"], cwd, 30000)
  if wsl_status_ready(status.code, status.output, status.timed_out) {
    let marker = wsl_waiting_marker_path()
    if @fs.path_exists(marker) {
      @fs.remove_file(marker) catch {
        _ => ()
      }
    }
    return true
  }
  if @fs.path_exists(wsl_waiting_marker_path()) ||
    read_receipt("wsl") is Some(_) {
    println(
      "WAITING_ENVIRONMENT: a prior official WSL install/update command completed, but WSL status is still not ready. RepoWayfinder will not repeat it; complete Windows setup or restart if requested, then retry.\n" +
      status.output,
    )
    return false
  }
  let action = wsl_repair_action(status.code, status.output, status.timed_out)
  if action == "manual" {
    println(
      "WAITING_ENVIRONMENT: WSL status is not ready, but it does not specifically request install or kernel update. RepoWayfinder will not guess. Complete virtualization, Virtual Machine Platform, firmware, or restart requirements yourself.\n" +
      status.output,
    )
    return false
  }
  let suffix = if action == "install" { " --no-distribution" } else { "" }
  if !allow_install {
    println(
      "WAITING_ENVIRONMENT: WSL status failed and repair is disabled for this run. The evidence-selected official action is `wsl --\{action}\{suffix}`.",
    )
    return false
  }
  let args = if action == "update" {
    ["--update"]
  } else {
    ["--install", "--no-distribution"]
  }
  if action == "install" {
    guard @host.resolve("powershell") is Some(powershell) else {
      println(
        "WAITING_ENVIRONMENT: PowerShell is unavailable, so elevation state cannot be checked. Run `wsl --install --no-distribution` yourself from an Administrator terminal.",
      )
      return false
    }
    let elevated = @host.run(
      powershell,
      [
        "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", "([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)",
      ],
      cwd,
      15000,
    )
    if elevated.code != 0 || !elevated.output.trim().to_lower().contains("true") {
      println(
        "WAITING_ENVIRONMENT: WSL installation needs an Administrator terminal and may require a restart. RepoWayfinder will not trigger UAC automatically. Run `wsl --install --no-distribution` yourself, review Windows prompts, then rerun the saved deployment.",
      )
      return false
    }
  }
  let command_text = "wsl " + args.join(" ")
  guard @host.prompt(
    "WSL status proves the runtime is not ready. Allow the official `\{command_text}` command now? RepoWayfinder will not accept licenses, answer UAC, or restart Windows.",
  ) else {
    println("WAITING_ENVIRONMENT: WSL repair was declined (default is No).")
    return false
  }
  guard ensure_tool_root() else { return false }
  let waiting_marker = wsl_waiting_marker_path()
  @fs.write_string_to_file(
    waiting_marker,
    Json({
      "owner": "RepoWayfinder-MB",
      "action": command_text,
      "state": "started_or_waiting",
    }).stringify(indent=2),
  ) catch {
    _ => {
      println(
        "WAITING_ENVIRONMENT: the WSL no-repeat checkpoint could not be written, so no system command was executed.",
      )
      return false
    }
  }
  let result = @host.run(wsl, args, cwd, 600000)
  if result.code != 0 || result.timed_out {
    println(
      "WAITING_ENVIRONMENT: `\{command_text}` did not complete. Its checkpoint is retained to prevent uncertain replay; no alternate installer, UAC automation, or reboot was attempted. Inspect/remove only after reconciling WSL state: \{waiting_marker}\n" +
      result.output,
    )
    return false
  }
  if action == "install" {
    write_receipt(
      "wsl",
      "wsl-helper",
      "wsl --install --no-distribution",
      result.output.trim().to_owned(),
    )
    |> ignore
  }
  let after = @host.run(wsl, ["--status"], cwd, 30000)
  if wsl_status_ready(after.code, after.output, after.timed_out) {
    let marker = wsl_waiting_marker_path()
    if @fs.path_exists(marker) {
      @fs.remove_file(marker) catch {
        _ => ()
      }
    }
    true
  } else {
    println(
      "WAITING_ENVIRONMENT: the official WSL command completed, but WSL is not ready yet. Complete any displayed Windows setup or restart, then rerun; RepoWayfinder will not repeat the command while this state is unresolved.",
    )
    false
  }
}

///|
pub async fn ensure(
  program : String,
  cwd : String,
  allow_install : Bool,
) -> Bool {
  let name = normalize(program)
  let status = probe(name, cwd)
  if status.state == "ready" {
    return true
  }
  if name == "wsl" {
    return repair_wsl(cwd, allow_install)
  }
  if name == "docker" && status.state == "waiting_environment" {
    return repair_docker(cwd, allow_install)
  }
  if status.state == "waiting_environment" {
    println("WAITING_ENVIRONMENT: " + status.detail)
    return false
  }
  if status.state == "broken" {
    println(
      "WAITING_ENVIRONMENT: \{name} is installed but its probe failed. RepoWayfinder will not upgrade or overwrite a pre-existing broken installation. Repair it with its official installer, then retry.\n" +
      status.detail,
    )
    return false
  }
  if name == "npm" {
    let node = probe("node", cwd)
    if node.state == "ready" {
      println(
        "WAITING_ENVIRONMENT: Node.js is installed but npm is missing. RepoWayfinder will not install a second Node.js or upgrade the existing distribution. Repair/reinstall that Node.js distribution from its official owner, then retry.",
      )
      return false
    }
    if node.state == "missing" {
      if !ensure("node", cwd, allow_install) {
        return false
      }
      return probe("npm", cwd).state == "ready"
    }
    println(
      "WAITING_ENVIRONMENT: npm cannot be prepared because the existing Node.js probe is not ready. Repair Node.js first.",
    )
    return false
  }
  if !allow_install {
    println(
      "WAITING_ENVIRONMENT: \{name} is missing and installation is disabled for this run.",
    )
    return false
  }
  let install_action = match
    (local_npm_package(name), system_package_id(name)) {
    (Some(package_name), _) =>
      "install npm package \{package_name} only under \{@host.tool_root()}"
    (_, Some(package_id)) =>
      if @host.resolve("winget") is Some(_) {
        "ask winget for exact package \{package_id}; package licenses, UAC and restart decisions remain yours"
      } else if name == "git" {
        "download the pinned official Git for Windows MinGit archive, verify its published SHA-256, and extract it only under \{@host.tool_root()}"
      } else if name == "node" {
        "select the newest official Node LTS Windows x64 portable archive, verify it against that release's SHASUMS256.txt, and extract it only under \{@host.tool_root()}"
      } else if name == "python" {
        "download the exact python.org 3.11.9 x64 installer, verify its Python Software Foundation signature, and visibly run a no-PATH current-user local install; license/UAC decisions remain yours"
      } else {
        "stop because winget is absent and no reviewed local fallback exists for \{package_id}"
      }
    _ if name == "moon" =>
      "download, read and structurally verify the official MoonBit PowerShell installer, then install under \{@host.tool_root()}"
    _ => {
      println(
        "Unsupported prerequisite: \{name}. Supported: git, node, npm, python, docker, wsl, moon, pnpm, yarn and bun.",
      )
      return false
    }
  }
  guard @host.prompt(
    "\{name} is missing. Allow RepoWayfinder to \{install_action}?",
  ) else {
    println(
      "WAITING_ENVIRONMENT: \{name} installation was declined (default is No).",
    )
    return false
  }
  match local_npm_package(name) {
    Some(package_name) => install_local_npm(name, package_name, cwd)
    None =>
      if name == "moon" {
        install_moonbit(cwd)
      } else {
        match system_package_id(name) {
          Some(package_id) => install_system(name, package_id, cwd)
          None => {
            println("No supported installer for \{name}.")
            false
          }
        }
      }
  }
}

///|
pub async fn doctor() -> Json {
  let cwd = current_dir()
  let tools : Array[Json] = []
  for
    name in [
      "git", "node", "npm", "python", "docker", "wsl", "moon", "pnpm", "yarn", "bun",
    ] {
    tools.push(probe_json(probe(name, cwd)))
  }
  Json::object({
    "status": Json("ok"),
    "platform": Json(
      if @host.windows() {
        "windows"
      } else {
        "unsupported_non_windows_install"
      },
    ),
    "tool_root": Json(@host.tool_root()),
    "tools": Json(tools),
    "notes": Json([
      "missing and installed-but-broken are distinct states", "Docker CLI availability does not prove Docker Desktop/daemon readiness",
      "WSL, virtualization, license acceptance, UAC and reboot remain user-owned boundaries",
    ]),
  })
}

///|
async fn uninstall_npm_local(
  program : String,
  package_name : String,
  cwd : String,
) -> Json {
  guard read_receipt(program) is Some(receipt) &&
    receipt_matches(
      receipt,
      program,
      "npm-local",
      package_name,
      @host.tool_root(),
    ) else {
    return Json({
      "program": program,
      "state": "preserved",
      "detail": "No matching RepoWayfinder ownership receipt.",
    })
  }
  guard current_version(program, cwd) is Some(version) &&
    receipt_version(receipt) == Some(version) else {
    return Json({
      "program": program,
      "state": "preserved",
      "detail": "Installed version no longer matches the ownership receipt, or cannot be verified; preserving possibly modified/shared files.",
    })
  }
  guard resolve_alias("npm") is Some(npm) else {
    return Json({
      "program": program,
      "state": "preserved",
      "detail": "npm is unavailable; receipt retained for a later retry.",
    })
  }
  let result = @host.run(
    npm,
    [
      "uninstall",
      "--global=false",
      "--prefix",
      @host.tool_root(),
      "--no-save",
      "--no-package-lock",
      package_name,
    ],
    cwd,
    180000,
  )
  if result.code == 0 && !result.timed_out {
    remove_receipt(program)
    Json({ "program": program, "state": "removed", "detail": result.output })
  } else {
    Json({
      "program": program,
      "state": "preserved",
      "detail": "Official npm uninstall failed; files and receipt were retained.\n" +
      result.output,
    })
  }
}

///|
async fn uninstall_system(
  program : String,
  package_id : String,
  cwd : String,
) -> Json {
  guard read_receipt(program) is Some(receipt) &&
    receipt_matches(
      receipt,
      program,
      "winget-system",
      package_id,
      @host.tool_root(),
    ) else {
    return Json({
      "program": program,
      "state": "preserved",
      "detail": "No matching RepoWayfinder ownership receipt; shared or pre-existing install preserved.",
    })
  }
  guard @host.resolve("winget") is Some(winget) else {
    return Json({
      "program": program,
      "state": "preserved",
      "detail": "winget is unavailable; use Windows Installed Apps. Receipt retained.",
    })
  }
  let installed = @host.run(
    winget,
    ["list", "--id", package_id, "--exact", "--source", "winget"],
    cwd,
    60000,
  )
  guard installed.code == 0 &&
    package_line(installed.output, package_id) is Some(version) &&
    receipt_version(receipt) == Some(version) else {
    return Json({
      "program": program,
      "state": "preserved",
      "detail": "Installed package record no longer matches the ownership receipt, or cannot be verified; preserving possibly updated/shared installation.",
    })
  }
  let result = @host.run(
    winget,
    ["uninstall", "--id", package_id, "--exact", "--source", "winget"],
    cwd,
    600000,
  )
  if result.code == 0 && !result.timed_out {
    remove_receipt(program)
    Json({ "program": program, "state": "removed", "detail": result.output })
  } else {
    Json({
      "program": program,
      "state": "preserved",
      "detail": "winget uninstall failed or needs user interaction; receipt retained.\n" +
      result.output,
    })
  }
}

///|
async fn uninstall_local_python(cwd : String) -> Json {
  guard read_receipt("python") is Some(receipt) &&
    python_receipt_digest(receipt) is Some(installer_sha256) else {
    return Json({
      "program": "python",
      "state": "preserved",
      "detail": "No exact RepoWayfinder python.org-local ownership receipt; pre-existing/shared Python was preserved.",
    })
  }
  let target = join(@host.tool_root(), "python")
  let executable = join(target, "python.exe")
  let installer = join(@host.tool_root(), python_direct_filename)
  guard current_version("python", cwd) is Some(version) &&
    receipt_version(receipt) == Some(version) else {
    return Json({
      "program": "python",
      "state": "preserved",
      "detail": "Local Python version no longer matches the ownership receipt, or cannot be verified; possibly modified files were preserved.",
    })
  }
  guard @fs.path_exists(installer) &&
    verified_python_installer(installer, cwd) &&
    file_sha256(installer, cwd) == Some(installer_sha256) else {
    return Json({
      "program": "python",
      "state": "preserved",
      "detail": "The retained exact-version python.org installer is absent or its Python Software Foundation signature is no longer valid. Runtime and receipt were preserved; no substitute uninstaller was guessed.",
    })
  }
  let result = @host.run(
    installer,
    [
      "/uninstall",
      "/passive",
      "/norestart",
      "InstallAllUsers=0",
      "TargetDir=" + target,
    ],
    cwd,
    600000,
  )
  if result.code == 0 && !result.timed_out && !@fs.path_exists(executable) {
    remove_receipt("python")
    Json({
      "program": "python",
      "state": "removed",
      "detail": "The exact signed python.org installer removed the owned runtime. Any non-runtime residual directory and the retained installer were preserved rather than recursively deleted.",
    })
  } else {
    Json({
      "program": "python",
      "state": "preserved",
      "detail": "The official Python uninstall failed, timed out, requested a restart, or left python.exe present. Runtime/installer/receipt were preserved for reconciliation; RepoWayfinder did not retry or delete the directory.\n" +
      result.output,
    })
  }
}

///|
pub async fn uninstall(confirmed : Bool) -> Json {
  if !confirmed {
    return Json::object({
      "status": Json("confirmation_required"),
      "changed": Json(false),
      "detail": Json(
        "Nothing was removed. Call again only after explicit user confirmation.",
      ),
    })
  }
  let cwd = current_dir()
  let results : Array[Json] = []
  for name in ["pnpm", "yarn", "bun"] {
    guard local_npm_package(name) is Some(package_name) else { continue }
    results.push(uninstall_npm_local(name, package_name, cwd))
  }
  for name in ["git", "node", "python", "docker"] {
    guard system_package_id(name) is Some(package_id) else { continue }
    if name == "python" &&
      read_receipt("python") is Some(receipt) &&
      python_receipt_digest(receipt) is Some(_) {
      results.push(uninstall_local_python(cwd))
    } else if read_receipt(name) is Some(receipt) &&
      receipt_kind(receipt) == Some("portable-local") {
      results.push(
        Json({
          "program": name,
          "state": "preserved",
          "detail": "RepoWayfinder owns this application-local portable runtime, but no per-file integrity manifest exists to prove that its directory is still unmodified. It and its receipt were conservatively preserved; no broad recursive deletion was attempted.",
        }),
      )
    } else {
      results.push(uninstall_system(name, package_id, cwd))
    }
  }
  if read_receipt("moon") is Some(receipt) &&
    receipt_matches(
      receipt,
      "moon",
      "moonbit-local",
      "MoonBit.CLI",
      @host.tool_root(),
    ) {
    results.push(
      Json({
        "program": "moon",
        "state": "preserved",
        "detail": "MoonBit publishes no supported Windows uninstall command. The application-local toolchain and receipt were preserved rather than recursively deleting a directory.",
      }),
    )
  }
  if read_receipt("wsl") is Some(receipt) &&
    receipt_matches(
      receipt,
      "wsl",
      "wsl-helper",
      "wsl --install --no-distribution",
      @host.tool_root(),
    ) {
    results.push(
      Json({
        "program": "wsl",
        "state": "preserved",
        "detail": "WSL Windows features have no safe application-local uninstall. They and the ownership receipt were preserved; use Windows Installed Apps/Optional Features after reviewing shared dependencies.",
      }),
    )
  }
  Json::object({ "status": Json("complete"), "results": Json(results) })
}
