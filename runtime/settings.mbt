///|
pub async fn deployment_mode(
  request_compatible : Bool,
  force_protected : Bool,
) -> Bool {
  let path = @host.join(@host.app_root(), ".repowayfinder-mode.json")
  let previous = @json.parse(@fs.read_file_to_string(path)) catch {
    _ => Json::null()
  }
  if force_protected {
    @fs.write_string_to_file(
      path, "{\"mode\":\"protected\",\"acknowledged_version\":1}",
    )
    return true
  }
  if request_compatible {
    if previous ==
      Json::object({ "mode": "compatible", "acknowledged_version": 1 }) {
      return false
    }
    if !@host.prompt(
        "兼容模式会放宽部分审查，但不会绕过高危拦截；项目代码仍在本机运行。是否切换？",
      ) {
      return true
    }
    @fs.write_string_to_file(
      path, "{\"mode\":\"compatible\",\"acknowledged_version\":1}",
    )
    return false
  }
  previous != Json::object({ "mode": "compatible", "acknowledged_version": 1 })
}
