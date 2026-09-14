///|
pub fn security_review(
  files : Array[SourceFile],
  ecosystem : String,
  protected_mode : Bool,
) -> Array[Finding] {
  let findings : Array[Finding] = []
  let container = ecosystem == "docker" || ecosystem == "docker-compose"
  for file in files {
    if !container &&
      (file.path == "Dockerfile" || file.path.contains("compose")) {
      continue
    }
    let content = file.content.to_lower()
    let critical = [
      "docker.sock", "docker_engine", "privileged:", "--privileged", "cap_add:",
      "--cap-add", "--pid=host", "--pid host", "pid: host", "pid: \"host\"", "--ipc=host",
      "--ipc host", "ipc: host", "devices:", "--device", "unconfined", "--mount",
      "--volume", " -v /", " -v c:", " -v d:", "sudo ", "runas ", "-verb runas",
      "net user", "schtasks /create", "currentversion\\run",
    ]
    for needle in critical {
      if content.contains(needle[:]) {
        findings.push({
          level: "error",
          code: "unsafe-host-operation",
          message: "Review required: " + needle,
          file: file.path,
        })
      }
    }
    if protected_mode {
      for
        needle in [
          "-encodedcommand", "-enc ", "| bash", "| sh", "| powershell", "| iex",
          "invoke-expression", "network_mode: host", "--network host", "--network=host",
        ] {
        if content.contains(needle[:]) {
          findings.push({
            level: "error",
            code: "protected-mode-review",
            message: "Protected mode blocks: " + needle,
            file: file.path,
          })
        }
      }
    }
  }
  findings
}

///|
pub fn validate_compose(
  config : Json,
  protected_mode : Bool,
) -> Result[Bool, String] {
  guard config is Object(root) &&
    root.get("services") is Some(Object(services)) &&
    !services.is_empty() else {
    return Err("Compose config has no resolved services.")
  }
  for name, service in services {
    guard service is Object(fields) else {
      return Err("Invalid service: " + name)
    }
    if fields.get("privileged") == Some(Json(true)) {
      return Err(name + ": privileged containers are blocked.")
    }
    for key in ["pid", "ipc", "userns_mode"] {
      if fields.get(key) == Some(Json("host")) {
        return Err(name + ": host namespace is blocked.")
      }
    }
    for
      key in [
        "cap_add", "devices", "device_cgroup_rules", "volumes_from", "security_opt",
      ] {
      if fields.get(key) is Some(Array(values)) && !values.is_empty() {
        return Err(name + ": " + key + " requires manual review.")
      }
    }
    if fields.get("volumes") is Some(Array(volumes)) {
      for volume in volumes {
        if volume is Object(fields) &&
          fields.get("type") == Some(Json("volume")) {
          continue
        }
        return Err(
          name +
          ": only named volumes are accepted automatically; bind mounts require review.",
        )
      }
    }
    if protected_mode && fields.get("network_mode") == Some(Json("host")) {
      return Err(name + ": host network is blocked in protected mode.")
    }
    if fields.get("container_name") is Some(_) {
      return Err(
        name + ": fixed container_name could collide with an existing service.",
      )
    }
  }
  Ok(true)
}

///|
pub fn local_health_url(url : String) -> Bool {
  let prefixes = ["http://127.0.0.1:", "http://localhost:", "http://[::1]:"]
  prefixes.any(prefix => {
    if !url.has_prefix(prefix[:]) {
      return false
    }
    let tail = url[prefix.length():].to_owned()
    let port = tail.split("/").next().unwrap().to_owned()
    !port.is_empty() &&
    port.iter().all(c => c >= '0' && c <= '9') &&
    !url.contains("@") &&
    !url.contains("#") &&
    !url.contains("\r") &&
    !url.contains("\n")
  })
}
