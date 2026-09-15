///|
pub(all) struct PythonEnvironmentResult {
  status : String
  required_version : String
  selected_version : String
  venv_version : String
  venv_path : String
  backup_path : String
  rollback_path : String
  message : String
} derive(Eq, Debug)

///|
fn version_token(text : String) -> String? {
  let normalized = text
    .replace_all(old="\r", new=" ")
    .replace_all(old="\n", new=" ")
    .replace_all(old="\t", new=" ")
  for raw in normalized.split(" ") {
    let token = raw.trim(chars="vV,;:()[]{}\"'").to_owned()
    let pieces = token.split(".").collect()
    if pieces.length() >= 2 {
      let major_parts = pieces[0].split("-").collect()
      let major = major_parts[major_parts.length() - 1].to_owned()
      let minor = pieces[1].to_owned()
      if !major.is_empty() &&
        !minor.is_empty() &&
        major.iter().all(c => c >= '0' && c <= '9') &&
        minor.iter().all(c => c >= '0' && c <= '9') {
        return Some(major + "." + minor)
      }
    }
  }
  None
}

///|
pub fn read_python_version_file(root : String) -> String? {
  let path = @host.join(root, ".python-version")
  guard @fs.path_exists(path) else { return None }
  let source = @fs.read_file_to_string(path) catch { _ => return None }
  version_token(source)
}

///|
pub fn python_version_from_output(output : String) -> String? {
  version_token(output)
}

///|
pub fn python_environment_action(
  required_version : String?,
  selected_version : String?,
  venv_exists : Bool,
  venv_version : String?,
) -> String {
  guard selected_version is Some(selected) else { return "waiting_python" }
  if required_version is Some(required) && required != selected {
    return "waiting_python_version"
  }
  if !venv_exists {
    return "ready_create"
  }
  if venv_version == Some(selected) {
    "ready_reuse"
  } else {
    "ready_rebuild"
  }
}

///|
async fn python_program_version(root : String, program : String) -> String? {
  let probe = @host.run(program, ["--version"], root, 30000)
  if probe.code == 0 && !probe.timed_out {
    python_version_from_output(probe.output)
  } else {
    None
  }
}

///|
pub async fn select_project_python(
  root : String,
  default_program : String,
) -> String {
  guard read_python_version_file(root) is Some(required) else {
    return default_program
  }
  let candidates : Array[String] = [default_program]
  let compact = required.replace_all(old=".", new="")
  if @host.windows() {
    if @env.get_env_var("LOCALAPPDATA") is Some(local_app_data) {
      candidates.push(
        @host.join(
          local_app_data,
          "Programs/Python/Python" + compact + "/python.exe",
        ),
      )
    }
    if @env.get_env_var("ProgramFiles") is Some(program_files) {
      candidates.push(
        @host.join(program_files, "Python" + compact + "/python.exe"),
      )
    }
  }
  for name in ["python" + required, "python" + compact, "python3", "python"] {
    if @host.resolve(name) is Some(path) && !candidates.contains(path) {
      candidates.push(path)
    }
  }
  for candidate in candidates {
    if python_program_version(root, candidate) == Some(required) {
      return candidate
    }
  }
  default_program
}

///|
fn powershell_literal(value : String) -> String {
  "'" + value.replace_all(old="'", new="''") + "'"
}

///|
pub async fn archive_project_python_venv(
  root : String,
  report_dir : String,
) -> (String, String) {
  let canonical_root = @afs.realpath(root[:])
  let venv_path = @host.join(canonical_root, ".repowayfinder-venv")
  guard @afs.kind(venv_path[:], follow_symlink=false) == @afs.Directory else {
    raise Failure(
      "Refusing to archive anything except the project-owned .repowayfinder-venv directory.",
    )
  }
  let stamp = @async.now().to_string()
  let mut backup_path = venv_path + ".backup-" + stamp
  let mut suffix = 1
  while @afs.exists(backup_path[:]) {
    backup_path = venv_path + ".backup-" + stamp + "-" + suffix.to_string()
    suffix += 1
  }
  if !@fs.path_exists(report_dir) {
    @fs.create_dir(report_dir)
  }
  let rollback_path = @host.join(report_dir, "restore-python-venv.ps1")
  let current = powershell_literal(venv_path)
  let backup = powershell_literal(backup_path)
  let rollback = "$ErrorActionPreference='Stop'\n" +
    "$current=" +
    current +
    "\n$backup=" +
    backup +
    "\nif (!(Test-Path -LiteralPath $backup -PathType Container)) { throw 'Python 虚拟环境备份不存在。' }\n" +
    "if (Test-Path -LiteralPath $current) {\n" +
    "  $displaced=$current + '.rollback-current-' + (Get-Date -Format 'yyyyMMdd-HHmmss')\n" +
    "  Move-Item -LiteralPath $current -Destination $displaced\n" +
    "}\n" +
    "Move-Item -LiteralPath $backup -Destination $current\n" +
    "Write-Host '已恢复之前的项目 Python 虚拟环境。'\n"
  // Persist recovery evidence before moving the environment. A report write
  // failure must never leave the canonical venv archived without a restore path.
  @fs.write_string_to_file(rollback_path, "\u{FEFF}" + rollback)
  @afs.rename(venv_path[:], backup_path[:], replace=false)
  (backup_path, rollback_path)
}

///|
pub async fn prepare_python_environment(
  root : String,
  report_dir : String,
  python_program : String,
) -> PythonEnvironmentResult {
  let venv_path = @host.join(root, ".repowayfinder-venv")
  let required = read_python_version_file(root)
  let selected = python_program_version(root, python_program)
  if selected is None {
    return {
      status: "waiting_python",
      required_version: required.unwrap_or(""),
      selected_version: "",
      venv_version: "",
      venv_path,
      backup_path: "",
      rollback_path: "",
      message: "所选 Python 无法报告可用的主版本和次版本号。",
    }
  }
  if required is Some(required_version) && selected != Some(required_version) {
    return {
      status: "waiting_python_version",
      required_version,
      selected_version: selected.unwrap(),
      venv_version: "",
      venv_path,
      backup_path: "",
      rollback_path: "",
      message: "项目要求 Python " +
      required_version +
      "，但当前选择的是 Python " +
      selected.unwrap() +
      "。请先安装或选择项目要求的版本，再继续运行。",
    }
  }
  let exists = @fs.path_exists(venv_path)
  if exists &&
    (@afs.kind(venv_path[:], follow_symlink=false) catch { _ => @afs.Unknown }) !=
    @afs.Directory {
    return {
      status: "waiting_unsafe_venv",
      required_version: required.unwrap_or(""),
      selected_version: selected.unwrap(),
      venv_version: "",
      venv_path,
      backup_path: "",
      rollback_path: "",
      message: "项目根目录下的 .repowayfinder-venv 不是普通目录，已保持原样并停止处理。",
    }
  }
  let venv_python = @host.join(
    venv_path,
    if @host.windows() {
      "Scripts/python.exe"
    } else {
      "bin/python"
    },
  )
  let venv_version = if exists && @fs.path_exists(venv_python) {
    let probe = @host.run(venv_python, ["--version"], root, 30000)
    if probe.code == 0 && !probe.timed_out {
      python_version_from_output(probe.output)
    } else {
      None
    }
  } else {
    None
  }
  let action = python_environment_action(
    required, selected, exists, venv_version,
  )
  if action == "ready_rebuild" {
    let archived = archive_project_python_venv(root, report_dir) catch {
      error =>
        return {
          status: "waiting_venv_backup",
          required_version: required.unwrap_or(""),
          selected_version: selected.unwrap(),
          venv_version: venv_version.unwrap_or(""),
          venv_path,
          backup_path: "",
          rollback_path: "",
          message: "无法备份现有项目 Python 虚拟环境：\{error}",
        }
    }
    return {
      status: "ready_rebuild",
      required_version: required.unwrap_or(""),
      selected_version: selected.unwrap(),
      venv_version: venv_version.unwrap_or(""),
      venv_path,
      backup_path: archived.0,
      rollback_path: archived.1,
      message: "不兼容或损坏的项目 Python 虚拟环境已备份，可以创建新的隔离环境。",
    }
  }
  {
    status: action,
    required_version: required.unwrap_or(""),
    selected_version: selected.unwrap(),
    venv_version: venv_version.unwrap_or(""),
    venv_path,
    backup_path: "",
    rollback_path: "",
    message: if action == "ready_reuse" {
      "现有项目 Python 虚拟环境与所选解释器版本一致，可以直接复用。"
    } else {
      "项目尚无 Python 虚拟环境，可以使用所选解释器创建。"
    },
  }
}
