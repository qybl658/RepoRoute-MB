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
pub fn missing_known_python_package(text : String) -> String? {
  let marker = "ModuleNotFoundError: No module named '"
  guard text.contains(marker[:]) else { return None }
  let pieces = text.split(marker).collect()
  guard pieces.length() > 1 else { return None }
  let module_name = pieces[1].split("'").next().unwrap().to_owned()
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
async fn repair_missing_python(
  root : String,
  result : @host.CommandResult,
  allow_install : Bool,
) -> @host.CommandResult? {
  guard allow_install &&
    missing_known_python_package(result.output) is Some(package_name) else {
    return None
  }
  let python = @host.join(
    root,
    if @host.windows() {
      ".repowayfinder-venv/Scripts/python.exe"
    } else {
      ".repowayfinder-venv/bin/python"
    },
  )
  guard @fs.path_exists(python) else { return None }
  guard @host.prompt(
    "项目缺少明确识别的 Python 依赖 " +
    package_name +
    "。是否仅安装到该项目虚拟环境并重试一次？",
  ) else {
    return None
  }
  Some(
    @host.run(
      python,
      ["-m", "pip", "install", "--", package_name],
      root,
      300000,
    ),
  )
}
