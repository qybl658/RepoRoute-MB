///|
pub fn transient_network_failure(text : String) -> Bool {
  let lower = text.to_lower()
  if [
      "permission denied", "unauthorized", "authentication required", "no such file",
      "dockerdesktoplinuxengine", "failed to connect to the docker api",
    ].any(s => lower.contains(s[:])) {
    return false
  }
  [
    "connection timed out", "temporary failure", "tls handshake timeout", "connection reset",
    "network is unreachable", "could not resolve host", "failed to fetch oauth token",
    "read timed out", "proxyerror", "getaddrinfo failed", "econnreset", "etimedout",
    "eai_again",
  ].any(s => lower.contains(s[:]))
}

///|
fn missing_python_module(text : String) -> String? {
  for error in ["ModuleNotFoundError", "ImportError"] {
    for quote in ["'", "\""] {
      let marker = error + ": No module named " + quote
      if text.contains(marker[:]) {
        let pieces = text.split(marker).collect()
        if pieces.length() > 1 {
          let module_name = pieces[1].split(quote).next().unwrap().to_owned()
          let top_level = module_name.split(".").next().unwrap().to_owned()
          if !top_level.is_empty() {
            return Some(top_level)
          }
        }
      }
    }
  }
  None
}

///|
pub fn missing_known_python_package(text : String) -> String? {
  guard missing_python_module(text) is Some(module_name) else { return None }
  // Import names are not arbitrary registry package names. Keep an explicit mapping.
  match module_name {
    "requests" => Some("requests")
    "flask" => Some("Flask")
    "fastapi" => Some("fastapi")
    "uvicorn" => Some("uvicorn")
    "streamlit" => Some("streamlit")
    "yaml" => Some("PyYAML")
    "PIL" => Some("Pillow")
    "numpy" => Some("numpy")
    "pandas" => Some("pandas")
    "pytest" => Some("pytest")
    _ => None
  }
}

///|
pub(all) struct DependencyRepair {
  kind : String
  package_name : String
  timeout_ms : Int
} derive(Eq, Debug)

///|
pub fn infer_dependency_repair(text : String) -> DependencyRepair? {
  if missing_python_module(text) == Some("pip") ||
    text.contains("No module named pip") {
    return Some({
      kind: "python-ensurepip",
      package_name: "",
      timeout_ms: 120000,
    })
  }
  if missing_known_python_package(text) is Some(package_name) {
    return Some({ kind: "python-package", package_name, timeout_ms: 300000, })
  }
  if text.contains("pytest: command not found") ||
    text.contains("No module named pytest") {
    return Some({
      kind: "python-package",
      package_name: "pytest",
      timeout_ms: 300000,
    })
  }
  if text.contains("vite: not found") ||
    text.to_lower().contains("vite' is not recognized") {
    return Some({ kind: "node-install", package_name: "", timeout_ms: 300000, })
  }
  None
}

///|
async fn repair_dependency(
  root : String,
  result : @host.CommandResult,
  allow_install : Bool,
) -> @host.CommandResult? {
  guard allow_install && infer_dependency_repair(result.output) is Some(repair) else {
    return None
  }
  match repair.kind {
    "python-package" | "python-ensurepip" => {
      let python = @host.join(
        root,
        if @host.windows() {
          ".repowayfinder-venv/Scripts/python.exe"
        } else {
          ".repowayfinder-venv/bin/python"
        },
      )
      guard @fs.path_exists(python) else { return None }
      let detail = if repair.kind == "python-ensurepip" {
        "项目虚拟环境缺少 pip。是否仅在该项目虚拟环境中恢复 pip 并重试一次？"
      } else {
        "项目缺少明确识别的 Python 依赖 " +
        repair.package_name +
        "。是否仅安装到该项目虚拟环境并重试一次？"
      }
      guard @host.prompt(detail) else { return None }
      let args = if repair.kind == "python-ensurepip" {
        ["-m", "ensurepip"]
      } else {
        ["-m", "pip", "install", "--", repair.package_name]
      }
      Some(@host.run(python, args, root, repair.timeout_ms))
    }
    "node-install" => {
      guard @host.prompt(
        "项目缺少 Vite 命令。是否仅在该项目目录运行 npm install 并重试一次？",
      ) else {
        return None
      }
      Some(@host.run("npm", ["install"], root, repair.timeout_ms))
    }
    _ => None
  }
}
