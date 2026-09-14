///|
let official_moonbit_installer_url = "https://cli.moonbitlang.com/install/powershell.ps1"

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
  if name == "moon" {
    let local_moon = join(@host.tool_root(), "moon/bin/moon.exe")
    if @fs.path_exists(local_moon) &&
      (@fs.is_file(local_moon) catch { _ => false }) {
      Some(local_moon)
    } else {
      @host.resolve(name)
    }
  } else if name == "python" {
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
    println(
      "WAITING_ENVIRONMENT: winget is unavailable. RepoWayfinder will not install or replace winget; install \{package_id} from its official publisher and retry.",
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
      "ask winget for exact package \{package_id}; package licenses, UAC and restart decisions remain yours"
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
    results.push(uninstall_system(name, package_id, cwd))
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
