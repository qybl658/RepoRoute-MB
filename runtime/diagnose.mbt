///|
pub fn diagnose(path : String) -> Json raise {
  let value = @json.parse(@fs.read_file_to_string(path))
  guard value is Object(fields) &&
    fields.get("status") is Some(String(status)) &&
    fields.get("root") is Some(String(root)) else {
    raise DeploymentError("Invalid deployment report.")
  }
  let detail = match fields.get("detail") {
    Some(String(s)) => @host.redact(s)
    _ => ""
  }
  let tips : Array[String] = []
  if status == "LEARN" {
    tips.push(
      "这是待了解入口的项目，不是已执行失败。查看项目 README 和示例；没有明确的启动证据时不自动猜命令。",
    )
  } else if status == "WAITING_ENVIRONMENT" {
    tips.push(
      "项目命令尚未执行。先准备报告中缺少或未就绪的环境，再通过 resume 继续；不要把它当作项目代码失败。",
    )
  } else if status.has_prefix("BLOCKED") {
    tips.push(
      "部署被检查规则阻止。先核对报告中的具体风险，不要绕过系统权限或把安全拦截当成安装失败。",
    )
  } else if status == "UNVERIFIED_RUNTIME" {
    tips.push(
      "进程存活不代表服务可用。按 README 确认端口，使用 --health-url 提供本地检查地址。",
    )
  } else if status == "SUCCEEDED" || status == "VERIFIED_HTTP" {
    tips.push(
      "这份报告没有记录执行失败。HTTP 验证模式会在完成后停止测试进程；使用 --serve 可保持前台运行。",
    )
  } else {
    let lower = detail.to_lower()
    if lower.contains("modulenotfounderror") ||
      lower.contains("cannot find module") {
      tips.push(
        "检查依赖清单是否完整、安装步骤是否成功。不要直接向系统环境补装项目依赖。",
      )
    }
    if lower.contains("address already in use") || lower.contains("eaddrinuse") {
      tips.push(
        "端口被占用。为目标项目选择其他端口，不要终止不属于本次部署的程序。",
      )
    }
    if lower.contains("timeout") ||
      lower.contains("resolve") ||
      lower.contains("ssl") {
      tips.push(
        "可能是网络、DNS、代理或证书问题。先检查原始错误，不要通过关闭证书验证解决。",
      )
    }
    tips.push(
      "定位 attempts 中第一条非零退出的步骤。修改配置或依赖后重新部署，修复前不宣称成功。",
    )
  }
  {
    "root": root,
    "status": status,
    "detail": detail,
    "tips": tips,
    "executed_repair": false,
  }
}
