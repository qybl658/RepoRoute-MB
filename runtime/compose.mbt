///|
pub async fn prepare_compose(
  config : Json,
  project_root : String,
  protected_mode : Bool,
) -> Json {
  guard config is Object(top) && top.get("services") is Some(Object(services)) else {
    raise DeploymentError("Compose 配置缺少有效服务。")
  }
  let clean = (path : String) => {
    if @host.windows() {
      path.replace_all(old="\\", new="/").to_lower()
    } else {
      path
    }
  }
  let root = clean(@afs.realpath(project_root[:]))
  top.remove("name")
  for kind in ["networks", "volumes"] {
    if top.get(kind) is Some(Object(resources)) {
      for _, resource in resources {
        if resource is Object(fields) &&
          fields.get("external") != Some(Json(true)) {
          fields.remove("name")
        }
      }
    }
  }
  let approved : Array[String] = []
  for _, service in services {
    guard service is Object(fields) else {
      raise DeploymentError("Compose 服务格式无效。")
    }
    // Use the task's generated Compose project name, never another application's fixed name.
    fields.remove("container_name")
    fields["restart"] = Json("no")
    if fields.get("ports") is Some(Array(ports)) {
      for port in ports {
        if port is Object(values) {
          values["host_ip"] = Json("127.0.0.1")
        }
      }
    }
    if fields.get("volumes") is Some(Array(volumes)) {
      for volume in volumes {
        if volume is Object(bind) &&
          bind.get("type") == Some(Json("bind")) &&
          bind.get("source") is Some(String(source)) {
          let resolved = clean(
            @afs.realpath(source[:]) catch {
              _ =>
                raise DeploymentError(
                  "挂载路径不存在或无法核实：" + source,
                )
            },
          )
          if resolved != root && !resolved.has_prefix((root + "/")[:]) {
            raise DeploymentError(
              "拒绝挂载项目目录之外的文件：" + source,
            )
          }
          if source.to_lower().contains("docker.sock") ||
            source.to_lower().contains("docker_engine") {
            raise DeploymentError(
              "禁止向容器开放 Docker 控制接口。",
            )
          }
          approved.push(source)
        }
      }
    }
  }
  if @lib.validate_compose(
      config,
      protected_mode,
      approved_bind_sources=approved,
    )
    is Err(message) {
    raise DeploymentError(message)
  }
  config
}
