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
      detail: "未找到可执行文件。",
    }
  }
  let result = @host.run(executable, version_args(name), cwd, 15000)
  if name == "wsl" {
    if wsl_status_ready(result.code, result.output, result.timed_out) {
      return {
        name,
        executable: Some(executable),
        state: "ready",
        detail: "WSL 状态检查通过，未发现需要安装、更新内核或处理虚拟化的阻塞项。Linux 发行版选择和任何待重启操作仍由你决定。",
      }
    }
    return {
      name,
      executable: Some(executable),
      state: "waiting_environment",
      detail: "已找到 WSL 命令，但状态表明仍需安装、更新内核、配置虚拟化/虚拟机平台、重启，或完成其他需要你处理的设置。\n" +
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
      detail: "Windows 提供了 Python 启动器或应用商店别名，但运行时检查失败。现有启动器会保留，RepoWayfinder 可以另行准备应用内置的 Python。\n" +
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
            detail: "已找到 Docker CLI，但 Docker 守护进程和 Docker Desktop 管理接口都不可用。当前仍缺少可用的 Docker Desktop 运行环境；只有 CLI 还不够。\n" +
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
        "\nDocker CLI 已安装，但 Docker Desktop/守护进程尚未就绪。请启动 Docker Desktop，并自行完成许可确认及 WSL/虚拟化设置，然后重试。\n" +
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
      println("无法创建应用本地工具目录：\{root}。")
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
      println(
        "安装已完成，但无法写入归属收据，因此不会将其认定为 RepoWayfinder 所有。",
      )
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
      _ => println("无法删除归属收据：\{path}。")
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
      "WAITING_ENVIRONMENT: 需要 PowerShell 才能执行经过校验的下载。",
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
      "WAITING_ENVIRONMENT: 上一次限量下载留下的状态尚未处理；为避免覆盖，已保留：" +
      partial,
    )
    return false
  }
  let script =
    #|& { param($url,$partial,$destination,[int64]$minimum,[int64]$maximum)
    #|$ErrorActionPreference='Stop'
    #|if (-not $url.StartsWith('https://',[StringComparison]::Ordinal)) { throw '仅允许 HTTPS 下载' }
    #|$request=[Net.HttpWebRequest]::Create($url)
    #|$request.AllowAutoRedirect=$true; $request.MaximumAutomaticRedirections=5
    #|$request.UserAgent='RepoWayfinder-MB prerequisite bootstrap'
    #|$response=$null; $input=$null; $output=$null
    #|try {
    #|  $response=$request.GetResponse()
    #|  if ($response.ContentLength -gt $maximum) { throw '下载内容长度超过上限' }
    #|  $input=$response.GetResponseStream()
    #|  $output=[IO.File]::Open($partial,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    #|  $buffer=New-Object byte[] 65536; [int64]$total=0
    #|  while (($read=$input.Read($buffer,0,$buffer.Length)) -gt 0) {
    #|    $total += $read; if ($total -gt $maximum) { throw '实际下载大小超过上限' }
    #|    $output.Write($buffer,0,$read)
    #|  }
    #|  if ($total -lt $minimum) { throw '实际下载大小低于下限' }
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
      "WAITING_ENVIRONMENT: 官方文件的限量下载失败；没有执行任何安装器或压缩包。\n" +
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
      "WAITING_ENVIRONMENT: 便携工具目标目录或之前保留的解压状态已经存在；没有覆盖任何内容：" +
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
    #|    if ([IO.Path]::IsPathRooted($entry.FullName)) { throw '已拒绝包含绝对路径的 ZIP 条目' }
    #|    $candidate=[IO.Path]::GetFullPath((Join-Path $stage $entry.FullName))
    #|    if (-not $candidate.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw '已拒绝越出目标目录的 ZIP 路径' }
    #|  }
    #|} finally { $zip.Dispose() }
    #|[IO.Compression.ZipFile]::ExtractToDirectory($archive,$stage)
    #|$source=$stage
    #|if (-not (Test-Path -LiteralPath (Join-Path $source $expected) -PathType Leaf)) {
    #|  $items=@(Get-ChildItem -LiteralPath $stage -Force)
    #|  if ($items.Count -ne 1 -or -not $items[0].PSIsContainer -or -not (Test-Path -LiteralPath (Join-Path $items[0].FullName $expected) -PathType Leaf)) { throw '压缩包目录结构与预期不符' }
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
      "WAITING_ENVIRONMENT: 便携工具安全解压失败。已保留不完整状态供检查，后续不会自动覆盖。\n" +
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
    #|  Write-Output "MoonBit 已安装到应用本地目录。"
    #|  Write-Output "未修改 PATH；RepoWayfinder 只会为其子进程临时提供该路径。"
    #|}
    #|else {
    #|  Write-Output "MoonBit 安装成功。"
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
      "MoonBit 自动准备目前仅支持 Windows。请从 MoonBit 官方下载页安装后重试。",
    )
    return false
  }
  guard ensure_tool_root() else { return false }
  guard @host.resolve("powershell") is Some(powershell) else {
    println(
      "WAITING_ENVIRONMENT: Windows PowerShell 不可用，无法下载并检查 MoonBit 官方安装脚本源码。",
    )
    return false
  }
  let script_path = join(@host.tool_root(), "moonbit-official-installer.ps1")
  let moon_home = join(@host.tool_root(), "moon")
  if @fs.path_exists(moon_home) {
    println(
      "WAITING_ENVIRONMENT: 预定的 MoonBit 应用本地目录已经存在，但没有找到可用的 moon 可执行文件。该目录可能是不完整安装或已被修改，RepoWayfinder 不会覆盖它：" +
      moon_home,
    )
    return false
  }
  guard powershell_literal(official_moonbit_installer_url) is Some(url) &&
    powershell_literal(script_path) is Some(destination) else {
    println("MoonBit 准备路径中含有不支持的字符。")
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
        "WAITING_ENVIRONMENT: 无法下载 MoonBit 官方安装脚本源码；没有执行安装器。\n" +
        download.output,
      )
      return false
    }
  }
  let source = @fs.read_file_to_string(script_path) catch {
    _ => {
      println(
        "无法读取已下载的 MoonBit 安装脚本，因此没有执行它。",
      )
      return false
    }
  }
  guard portable_moonbit_installer(source) is Some(portable_source) else {
    println(
      "已下载的 MoonBit 安装脚本与经过审查的便携化转换规则不完全匹配，因此没有执行。请检查：" +
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
          "无法读取现有的 MoonBit 便携化安装脚本；已保留该文件并停止。",
        )
        return false
      }
    }
    if existing != portable_source {
      println(
        "现有的 MoonBit 便携化安装脚本与审查结果不一致；已保留该文件并停止：" +
        portable_script_path,
      )
      return false
    }
  } else {
    @fs.write_string_to_file(portable_script_path, portable_source) catch {
      _ => {
        println(
          "无法写入经过审查的 MoonBit 便携化安装脚本；没有执行任何内容。",
        )
        return false
      }
    }
  }
  let moon_bin = join(moon_home, "bin")
  guard powershell_literal(moon_home) is Some(home) &&
    powershell_literal(moon_bin) is Some(bin) &&
    powershell_literal(portable_script_path) is Some(portable_destination) else {
    println("MoonBit 安装路径中含有不支持的字符。")
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
      "WAITING_ENVIRONMENT: 经过审查的 MoonBit 安装脚本未能完成。源码已保留供检查。\n" +
      install.output,
    )
    return false
  }
  let checked = @host.run(moon_exe, ["--version"], cwd, 30000)
  if checked.code != 0 || checked.timed_out {
    println(
      "MoonBit 文件已经生成，但编译器检查失败，因此没有写入成功收据。\n" +
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
      "WAITING_ENVIRONMENT: 在应用本地安装 \{program} 需要 npm。请先安装或修复 Node.js。",
    )
    return false
  }
  guard ensure_tool_root() else { return false }
  let package_dir = join(@host.tool_root(), "node_modules/" + package_name)
  if @fs.path_exists(package_dir) {
    println(
      "WAITING_ENVIRONMENT: 应用本地的 \{package_name} 目录已经存在，但没有找到可用的可执行文件。RepoWayfinder 不会覆盖可能已修改或不完整的文件：" +
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
      "应用本地的 \{program} 安装失败，因此没有写入归属收据。\n" +
      result.output,
    )
    return false
  }
  let checked = probe(program, cwd)
  if checked.state != "ready" {
    println(
      "\{program} 已下载到应用本地目录，但版本检查失败，因此没有写入成功收据。\n" +
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
      "WAITING_ENVIRONMENT: 经过审查的 MinGit 备用方案仅支持 Windows x64。请从官方发布方安装适用于本机架构的 Git for Windows。",
    )
    return false
  }
  guard ensure_tool_root() else { return false }
  let archive = join(@host.tool_root(), mingit_filename)
  let target = join(@host.tool_root(), "git")
  if @fs.path_exists(target) {
    println(
      "WAITING_ENVIRONMENT: 应用本地 Git 目标目录已经存在，但没有可用的可执行文件。该目录可能不完整或已被修改，因此已保留：" +
      target,
    )
    return false
  }
  guard download_bounded(mingit_url, archive, 10000000L, 100000000L, cwd) else {
    return false
  }
  guard file_sha256(archive, cwd) == Some(mingit_sha256) else {
    println(
      "WAITING_ENVIRONMENT: MinGit 的 SHA-256 与 Git for Windows 官方发布文件不一致，因此没有解压：" +
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
      "应用本地 MinGit 已解压，但版本检查失败，因此没有写入归属收据。\n" +
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
      "WAITING_ENVIRONMENT: Node 官方便携备用方案仅支持 Windows x64。请安装适用于本机架构的 Node.js 版本。",
    )
    return false
  }
  guard ensure_tool_root() else { return false }
  let target = join(@host.tool_root(), "node")
  if @fs.path_exists(target) {
    println(
      "WAITING_ENVIRONMENT: 应用本地 Node 目标目录已经存在，但 node/npm 均不可用。该目录可能不完整或已被修改，因此已保留：" +
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
      println("无法读取已下载的 Node 官方版本索引。")
      return false
    }
  }
  guard node_lts_archive(index_source) is Some((version, filename, url)) else {
    println(
      "WAITING_ENVIRONMENT: nodejs.org 版本索引中没有结构有效的 LTS Windows x64 便携压缩包；不会猜测已经变化的来源格式。",
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
      println("无法读取已下载的 Node 官方校验清单。")
      return false
    }
  }
  guard checksum_for_file(sums, filename) is Some(expected_sha256) else {
    println(
      "WAITING_ENVIRONMENT: Node 官方校验清单中没有与下列文件完全匹配的条目：" +
      filename +
      "；没有下载压缩包。",
    )
    return false
  }
  let archive = join(@host.tool_root(), filename)
  guard download_bounded(url, archive, 10000000L, 250000000L, cwd) else {
    return false
  }
  guard file_sha256(archive, cwd) == Some(expected_sha256) else {
    println(
      "WAITING_ENVIRONMENT: Node 压缩包的 SHA-256 与官方 SHASUMS256.txt 中的精确条目不一致，因此没有解压：" +
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
      "应用本地 Node 已解压，但 node 和 npm 未能同时通过版本检查，因此没有写入归属收据。\nnode：" +
      node_checked.detail +
      "\nnpm：" +
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
      "WAITING_ENVIRONMENT: 经过审查的 python.org 备用方案仅支持 Windows x64 安装器。请自行选择适用于本机架构的官方安装器。",
    )
    return false
  }
  guard ensure_tool_root() else { return false }
  let target = join(@host.tool_root(), "python")
  let executable = join(target, "python.exe")
  let installer = join(@host.tool_root(), python_direct_filename)
  if @fs.path_exists(target) {
    println(
      "WAITING_ENVIRONMENT: 应用本地 Python 目标目录已经存在，但没有可用的可执行文件。该目录可能不完整或已被修改，因此已保留：" +
      target,
    )
    return false
  }
  if @fs.path_exists(installer) {
    println(
      "WAITING_ENVIRONMENT: Python 安装器的预定路径已经被无归属记录的文件占用；不会复用或覆盖该文件：" +
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
      "WAITING_ENVIRONMENT: 已下载的 Python 安装器没有有效的 Python Software Foundation Authenticode 签名，因此没有执行：" +
      installer,
    )
    return false
  }
  guard file_sha256(installer, cwd) is Some(installer_sha256) else {
    println(
      "WAITING_ENVIRONMENT: 无法记录已签名 Python 安装器的 SHA-256，因此没有执行它。",
    )
    return false
  }
  println(
    "即将以当前用户、可见的被动模式运行已签名的 python.org 精确版本安装器。它不会修改 PATH、安装启动器、请求重启或自动回应 UAC；任何 Windows 或许可提示都由你决定。",
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
      "WAITING_ENVIRONMENT: Python 官方安装器没有创建所请求的精确本地运行时。未写入归属收据；安装器和不完整状态已保留供诊断。\n" +
      result.output,
    )
    return false
  }
  let checked = probe("python", cwd)
  if checked.state != "ready" ||
    checked.detail.trim() != "Python " + python_direct_version {
    println(
      "应用本地 Python 已存在，但安装版本未通过精确校验，因此没有写入归属收据。\n" +
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
        "WAITING_ENVIRONMENT: 尚未为以下工具实现经过审查的无 winget 官方备用方案：" +
        program +
        "。",
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
      "当前平台不支持自动安装系统前置工具。请使用该平台支持的包管理器安装 \{program}，然后重试。",
    )
    return false
  }
  guard @host.resolve("winget") is Some(winget) else {
    if normalize(program) == "git" ||
      normalize(program) == "node" ||
      normalize(program) == "python" {
      println(
        "未找到 winget，将改用经过审查的官方应用本地备用方案；不会修改系统 PATH、包管理器、服务、自启动项或机器设置。",
      )
      return install_official_fallback(program, cwd)
    }
    println(
      "WAITING_ENVIRONMENT: winget 不可用，且 \{package_id} 尚无安全的官方本地备用方案。请从官方发布方安装后重试。",
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
      "WAITING_ENVIRONMENT: winget 显示 \{package_id} 已安装，但 \{program} 无法使用。它属于预先存在或已损坏的安装，RepoWayfinder 不会升级它或声称归属。请通过 Windows“已安装的应用”或官方发布方进行修复。",
    )
    return false
  }
  if !winget_confirmed_absent(before.code, before.output) {
    println(
      "WAITING_ENVIRONMENT: winget 无法证明 \{package_id} 确实未安装。为避免误升级现有软件或错误认领归属，RepoWayfinder 已停止。\n" +
      before.output,
    )
    return false
  }
  println(
    "winget 将使用精确包 ID \{package_id}。RepoWayfinder 不会传入自动接受许可/来源的参数，也不会请求重启或升级现有工具。",
  )
  let result = @host.run(
    winget,
    ["install", "--id", package_id, "--exact", "--source", "winget"],
    cwd,
    600000,
  )
  if result.code != 0 || result.timed_out {
    println(
      "WAITING_ENVIRONMENT: winget 未能完成。请自行查看并决定任何软件包许可或 UAC 请求；未写入成功收据。\n" +
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
      "winget 返回成功，但无法验证新的精确软件包记录，因此没有写入归属收据。\n" +
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
      "WAITING_ENVIRONMENT: 软件包安装已完成，但仍需单独完成并验证 Windows/Docker 就绪状态。RepoWayfinder 不会代你接受许可、启用固件虚拟化、自行提权或重启 Windows。",
    )
    return false
  }
  if checked.state != "ready" {
    println(
      "WAITING_ENVIRONMENT: 安装已完成，但当前进程中的 \{program} 尚未就绪。如果安装器修改了 PATH，请重开终端后重试。\n" +
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
/// A completed WSL maintenance command may legitimately need one Windows
/// restart. It suppresses repeats only during that same boot. An uncertain
/// command remains blocked across boots because replaying it could duplicate a
/// system change whose result was never observed.
fn wsl_marker_disposition(content : String, current_boot_id : String) -> String {
  guard (@json.parse(content) catch { _ => Json::null() }) is Object(object) &&
    object_string(object, "owner") == Some("RepoWayfinder-MB") &&
    object_string(object, "state") is Some(state) else {
    return "uncertain"
  }
  if state == "uncertain" || state == "started_or_waiting" {
    return "uncertain"
  }
  if state != "restart_required" {
    return "uncertain"
  }
  guard object_string(object, "boot_id") is Some(marker_boot_id) &&
    !marker_boot_id.trim().is_empty() &&
    !current_boot_id.trim().is_empty() else {
    return "same_boot"
  }
  if marker_boot_id.trim() == current_boot_id.trim() {
    "same_boot"
  } else {
    "stale"
  }
}

///|
async fn windows_boot_id(cwd : String) -> String {
  guard @host.resolve("powershell") is Some(powershell) else { return "" }
  let result = @host.run(
    powershell,
    [
      "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", "try { (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString('o') } catch { exit 1 }",
    ],
    cwd,
    15000,
  )
  if result.code == 0 && !result.timed_out {
    result.output.trim().to_owned()
  } else {
    ""
  }
}

///|
fn write_wsl_marker(
  path : String,
  action : String,
  state : String,
  boot_id : String,
) -> Bool {
  try {
    @fs.write_string_to_file(
      path,
      Json({
        "owner": "RepoWayfinder-MB",
        "action": action,
        "state": state,
        "boot_id": boot_id,
      }).stringify(indent=2),
    )
    true
  } catch {
    _ => false
  }
}

///|
async fn repair_docker(cwd : String, allow_install : Bool) -> Bool {
  guard @host.windows() else {
    println(
      "WAITING_ENVIRONMENT: Docker 守护进程不可用。自动启动 Docker Desktop 目前仅支持 Windows；请自行启动当前平台支持的守护进程。",
    )
    return false
  }
  guard @host.resolve("docker") is Some(docker) else { return false }
  if !allow_install {
    println(
      "WAITING_ENVIRONMENT: Docker CLI 已安装，但守护进程已停止或不可用。本次运行不允许启动 Docker Desktop，也不会重新安装现有版本。",
    )
    return false
  }
  guard @host.prompt(
    "Docker 已安装，但守护进程尚未就绪。是否允许执行官方命令 `docker desktop start`？任何 Docker 许可或首次运行界面都需要你亲自查看并决定；RepoWayfinder 不会重新安装 Docker。",
  ) else {
    println(
      "WAITING_ENVIRONMENT: 已取消启动 Docker Desktop（默认选择为“否”）。",
    )
    return false
  }
  let started = @host.run(docker, ["desktop", "start"], cwd, 120000)
  if started.code != 0 || started.timed_out {
    println(
      "WAITING_ENVIRONMENT: 未能通过官方 CLI 启动 Docker Desktop。请完成 WSL、虚拟化和许可设置，或自行启动；没有尝试重新安装。\n" +
      started.output,
    )
    return false
  }
  let after = probe("docker", cwd)
  if after.state == "ready" {
    true
  } else {
    println(
      "WAITING_ENVIRONMENT: Docker Desktop 启动命令已成功返回，但守护进程尚未就绪。请完成可见的首次运行、许可和 WSL 设置后重试；没有尝试重新安装。\n" +
      after.detail,
    )
    false
  }
}

///|
async fn repair_wsl(cwd : String, allow_install : Bool) -> Bool {
  guard @host.windows() else {
    println("WSL 修复功能仅支持 Windows。")
    return false
  }
  guard @host.resolve("wsl") is Some(wsl) else {
    println(
      "WAITING_ENVIRONMENT: 未找到 Windows WSL 命令。RepoWayfinder 无法通过隐藏或提权助手安全启用 Windows 功能。请打开管理员终端，确认后运行 `wsl --install --no-distribution`；仅在 Windows 要求时重启。",
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
  let waiting_marker = wsl_waiting_marker_path()
  if @fs.path_exists(waiting_marker) {
    let marker_content = @fs.read_file_to_string(waiting_marker) catch {
      _ => ""
    }
    let disposition = wsl_marker_disposition(
      marker_content,
      windows_boot_id(cwd),
    )
    if disposition == "stale" {
      // The restart happened. Remove only the obsolete wait marker and decide
      // from the fresh wsl --status evidence below; ownership receipts remain.
      @fs.remove_file(waiting_marker) catch {
        _ => ()
      }
    } else {
      let explanation = if disposition == "same_boot" {
        "之前的 WSL 官方命令已在本次 Windows 启动周期完成；在重启前不会重复执行。"
      } else {
        "之前的 WSL 官方命令结果不确定；为避免重复系统变更，不会自动重放。请先人工核对 WSL 状态和该检查点。"
      }
      println("WAITING_ENVIRONMENT: " + explanation + "\n" + status.output)
      return false
    }
  }
  let action = wsl_repair_action(status.code, status.output, status.timed_out)
  if action == "manual" {
    println(
      "WAITING_ENVIRONMENT: WSL 尚未就绪，但状态并未明确要求安装或更新内核。RepoWayfinder 不会猜测操作；请自行完成虚拟化、虚拟机平台、固件或重启要求。\n" +
      status.output,
    )
    return false
  }
  let suffix = if action == "install" { " --no-distribution" } else { "" }
  if !allow_install {
    println(
      "WAITING_ENVIRONMENT: WSL 状态检查失败，并且本次运行不允许修复。根据现有证据，应执行的官方操作是 `wsl --\{action}\{suffix}`。",
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
        "WAITING_ENVIRONMENT: PowerShell 不可用，无法检查当前是否已提权。请在管理员终端中自行运行 `wsl --install --no-distribution`。",
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
        "WAITING_ENVIRONMENT: 安装 WSL 需要管理员终端，并且可能需要重启。RepoWayfinder 不会自动触发 UAC。请自行运行 `wsl --install --no-distribution`，查看并决定 Windows 提示，然后重新运行已保存的部署。",
      )
      return false
    }
  }
  let command_text = "wsl " + args.join(" ")
  guard @host.prompt(
    "WSL 状态已证明运行环境尚未就绪。是否允许现在执行官方命令 `\{command_text}`？RepoWayfinder 不会代你接受许可、回应 UAC 或重启 Windows。",
  ) else {
    println(
      "WAITING_ENVIRONMENT: 已取消 WSL 修复（默认选择为“否”）。",
    )
    return false
  }
  guard ensure_tool_root() else { return false }
  let boot_id = windows_boot_id(cwd)
  if !write_wsl_marker(waiting_marker, command_text, "uncertain", boot_id) {
    println(
      "WAITING_ENVIRONMENT: 无法写入 WSL 防重复执行检查点，因此没有执行系统命令。",
    )
    return false
  }
  let result = @host.run(wsl, args, cwd, 600000)
  if result.code != 0 || result.timed_out {
    println(
      "WAITING_ENVIRONMENT: `\{command_text}` 未能完成。为避免在结果不确定时重复执行，检查点已保留；没有尝试其他安装器、自动回应 UAC 或重启。请先核对 WSL 状态，再检查或移除该文件：\{waiting_marker}\n" +
      result.output,
    )
    return false
  }
  if !write_wsl_marker(
      waiting_marker, command_text, "restart_required", boot_id,
    ) {
    println(
      "WAITING_ENVIRONMENT: WSL 命令已返回成功，但无法持久化安全续跑状态。请先人工核对 WSL 状态；不会在本次运行中重复命令。",
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
      "WAITING_ENVIRONMENT: WSL 官方命令已经完成，但 WSL 尚未就绪。请完成屏幕上显示的 Windows 设置或重启要求后再次运行；在此状态未解决前，RepoWayfinder 不会重复该命令。",
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
      "WAITING_ENVIRONMENT: \{name} 已安装，但检查失败。RepoWayfinder 不会升级或覆盖预先存在的损坏安装；请使用官方安装器修复后重试。\n" +
      status.detail,
    )
    return false
  }
  if name == "npm" {
    let node = probe("node", cwd)
    if node.state == "ready" {
      println(
        "WAITING_ENVIRONMENT: Node.js 已安装，但缺少 npm。RepoWayfinder 不会再安装一份 Node.js 或升级现有发行版；请通过官方来源修复或重新安装当前 Node.js，然后重试。",
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
      "WAITING_ENVIRONMENT: 现有 Node.js 未通过检查，因此无法准备 npm。请先修复 Node.js。",
    )
    return false
  }
  if !allow_install {
    println(
      "WAITING_ENVIRONMENT: 缺少 \{name}，并且本次运行不允许安装。",
    )
    return false
  }
  let install_action = match
    (local_npm_package(name), system_package_id(name)) {
    (Some(package_name), _) =>
      "仅在 \{@host.tool_root()} 中安装 npm 包 \{package_name}"
    (_, Some(package_id)) =>
      if @host.resolve("winget") is Some(_) {
        "请求 winget 安装精确软件包 \{package_id}；软件包许可、UAC 和重启仍由你决定"
      } else if name == "git" {
        "下载固定版本的 Git for Windows 官方 MinGit 压缩包，核对其公开的 SHA-256，并且只解压到 \{@host.tool_root()}"
      } else if name == "node" {
        "选择最新的 Node 官方 LTS Windows x64 便携压缩包，使用该版本的 SHASUMS256.txt 校验，并且只解压到 \{@host.tool_root()}"
      } else if name == "python" {
        "下载 python.org 3.11.9 x64 精确版本安装器，验证 Python Software Foundation 签名，并以可见方式执行不修改 PATH 的当前用户本地安装；许可和 UAC 仍由你决定"
      } else {
        "停止操作，因为缺少 winget，且 \{package_id} 没有经过审查的本地备用方案"
      }
    _ if name == "moon" =>
      "下载并读取 MoonBit 官方 PowerShell 安装脚本，通过结构校验后安装到 \{@host.tool_root()}"
    _ => {
      println(
        "不支持的前置工具：\{name}。目前支持 git、node、npm、python、docker、wsl、moon、pnpm、yarn 和 bun。",
      )
      return false
    }
  }
  guard @host.prompt(
    "缺少 \{name}。是否允许 RepoWayfinder \{install_action}？",
  ) else {
    println(
      "WAITING_ENVIRONMENT: 已取消安装 \{name}（默认选择为“否”）。",
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
            println("没有适用于 \{name} 的受支持安装器。")
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
      "缺失与已安装但损坏是两种不同状态", "能使用 Docker CLI 并不代表 Docker Desktop/守护进程已经就绪",
      "WSL、虚拟化、许可接受、UAC 和重启仍是需要用户亲自决定的边界",
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
      "detail": "没有找到匹配的 RepoWayfinder 归属收据，未执行删除。",
    })
  }
  guard current_version(program, cwd) is Some(version) &&
    receipt_version(receipt) == Some(version) else {
    return Json({
      "program": program,
      "state": "preserved",
      "detail": "已安装版本与归属收据不再一致，或当前无法验证；已保留可能被修改或共享的文件。",
    })
  }
  guard resolve_alias("npm") is Some(npm) else {
    return Json({
      "program": program,
      "state": "preserved",
      "detail": "npm 不可用；归属收据已保留，稍后可以重试。",
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
      "detail": "npm 官方卸载失败；文件和归属收据均已保留。\n" +
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
      "detail": "没有找到匹配的 RepoWayfinder 归属收据；已保留共享或预先存在的安装。",
    })
  }
  guard @host.resolve("winget") is Some(winget) else {
    return Json({
      "program": program,
      "state": "preserved",
      "detail": "winget 不可用；请使用 Windows“已安装的应用”。归属收据已保留。",
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
      "detail": "已安装软件包记录与归属收据不再一致，或当前无法验证；已保留可能更新过或共享的安装。",
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
      "detail": "winget 卸载失败或需要用户操作；归属收据已保留。\n" +
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
      "detail": "没有找到精确匹配的 RepoWayfinder python.org 本地安装归属收据；已保留预先存在或共享的 Python。",
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
      "detail": "本地 Python 版本与归属收据不再一致，或当前无法验证；已保留可能被修改的文件。",
    })
  }
  guard @fs.path_exists(installer) &&
    verified_python_installer(installer, cwd) &&
    file_sha256(installer, cwd) == Some(installer_sha256) else {
    return Json({
      "program": "python",
      "state": "preserved",
      "detail": "保留的 python.org 精确版本安装器缺失，或其 Python Software Foundation 签名已无效。运行时和归属收据均已保留；没有猜测使用其他卸载器。",
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
      "detail": "已使用精确匹配且签名有效的 python.org 安装器移除归属明确的运行时。没有递归删除目录；非运行时残留和保留的安装器仍在原处。",
    })
  } else {
    Json({
      "program": "python",
      "state": "preserved",
      "detail": "Python 官方卸载失败、超时、要求重启，或仍留下 python.exe。运行时、安装器和归属收据均已保留供核对；RepoWayfinder 没有重试或删除目录。\n" +
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
        "没有移除任何内容。只有在用户明确确认后才能再次执行。",
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
          "detail": "该应用本地便携运行时由 RepoWayfinder 安装，但目前没有逐文件完整性清单可以证明目录未被修改。为稳妥起见，运行时和归属收据均已保留；没有进行大范围递归删除。",
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
        "detail": "MoonBit 没有提供受支持的 Windows 卸载命令。应用本地工具链和归属收据均已保留，没有递归删除目录。",
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
        "detail": "WSL Windows 功能没有安全的应用本地卸载方式。相关功能和归属收据均已保留；请先确认共享依赖，再使用 Windows“已安装的应用”或“可选功能”处理。",
      }),
    )
  }
  Json::object({ "status": Json("complete"), "results": Json(results) })
}
