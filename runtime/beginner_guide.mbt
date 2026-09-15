///|
/// Bounded, offline counterpart of local_readme_beginner_digest. Author text
/// is quoted as evidence, never promoted to an approved executable plan.
pub fn readme_usage_excerpt(text : String) -> String {
  let mut result = ""
  let mut selected = false
  let mut count = 0
  for line in text.split("\n") {
    let lower = line.trim().to_lower()
    if lower.has_prefix("#") {
      selected = [
        "quick start", "quickstart", "getting started", "installation", "usage",
        "configuration", "快速", "安装", "使用", "配置", "运行",
      ].any(word => lower.contains(word[:]))
    }
    if selected && count < 60 && result.length() < 6000 {
      result += "> " + line.to_owned() + "\n"
      count += 1
    }
  }
  if result.is_empty() {
    "未找到明确的安装/使用章节，请打开作者 README 查看。\n"
  } else {
    result
  }
}

///|
/// Reuse the configured advisor and its bounded evidence/privacy boundary.
/// Never put translated prose back into an executable deployment plan.
pub async fn enrich_beginner_guide(
  report_path : String,
  allow_send : Bool,
) -> Json {
  let report = @json.parse(@fs.read_file_to_string(report_path))
  guard report is Object(fields) &&
    fields.get("root") is Some(String(root)) &&
    fields.get("report_dir") is Some(String(report_dir)) else {
    raise DeploymentError("报告缺少项目目录或报告目录。")
  }
  let canonical_report = @afs.realpath(report_path[:])
  let parts = canonical_report
    .replace_all(old="\\", new="/")
    .split("/")
    .map(p => p.to_owned())
    .collect()
  let _ = parts.pop()
  guard @afs.realpath(report_dir[:]) == @afs.realpath(parts.join("/")[:]) else {
    raise DeploymentError("报告目录与文件位置不一致。")
  }
  if !allow_send &&
    !@host.prompt(
      "是否把项目 README 和已知清单的有限内容发送给已配置的 AI，生成中文小白指南？可能产生服务费用；不会发送密钥配置，也不会执行返回内容。",
    ) {
    return { "status": "cancelled", "executed": false }
  }
  let response = @advisor.analyze(
    root, "用自然中文面向第一次使用这个项目的人解释作者 README：项目用途、前置条件、安装与使用顺序、配置字段含义和注意事项。忠实翻译英文，保留产品名。不要捏造步骤、密钥或本机成功状态；不要生成新的 shell 命令。summary 写用途，recommendation 写按顺序的中文操作说明，evidence 引用来源，risks 写未验证或缺失的信息。",
    true,
  ) catch {
    error =>
      return {
        "status": "unavailable",
        "detail": @host.redact("\{error}"),
        "offline_guide_preserved": true,
      }
  }
  guard response is Object(response_fields) &&
    response_fields.get("answer") is Some(Object(answer)) else {
    raise DeploymentError(
      "AI 返回缺少有效指南；原离线指南保持不动。",
    )
  }
  let body = render_chinese_guide(Json::object(answer))
  let path = @host.join(report_dir, "beginner_guide.zh-CN.md")
  @fs.write_string_to_file(path, @host.redact(body))
  {
    "status": "generated",
    "path": path,
    "executed": false,
    "offline_guide_preserved": true,
  }
}

///|
pub fn render_chinese_guide(answer : Json) -> String raise {
  guard answer is Object(fields) &&
    fields.get("summary") is Some(String(summary)) &&
    fields.get("recommendation") is Some(String(recommendation)) else {
    raise DeploymentError("AI 指南格式无效；不覆盖现有报告。")
  }
  "# 中文小白指南\n\n根据作者 README 由 AI 翻译、化简；未经执行验证。实际运行状态以 deployment.json 为准。\n\n" +
  summary +
  "\n\n## 使用步骤\n\n" +
  recommendation +
  "\n\n## 来源与限制\n\n```json\n" +
  answer.stringify(indent=2) +
  "\n```\n"
}

///|
fn write_beginner_guide(
  root : String,
  report_dir : String,
  status : String,
  health : String,
) -> Unit raise {
  let mut source = ""
  let mut readme = ""
  for
    name in [
      "README.zh-CN.md", "README_zh.md", "README.md", "README.rst", "README-en.md",
    ] {
    let path = @host.join(root, name)
    if @fs.path_exists(path) && source.is_empty() {
      source = name
      readme = @fs.read_file_to_string(path) catch { _ => "" }
    }
  }
  let action = match status {
    "WAITING_ENVIRONMENT" =>
      "先完成报告提示的环境步骤，再双击本目录的 `准备好环境后点我继续.bat`。重启后也从这里继续，不要重新安装已经存在的工具。"
    "VERIFIED_HTTP" =>
      "本地网页检查已通过：" +
      health +
      "。验证模式已停止服务；双击 `准备好环境后点我继续.bat` 重新启动并保持窗口开启。"
    "SUCCEEDED" =>
      "本次命令已正常退出；这不代表所有业务功能已验证。查看作者的实际使用步骤。"
    "LEARN" =>
      "这是阅读指导，不是部署失败。下面摘录作者的使用说明；没有执行其中的命令。"
    "BLOCKED_SECURITY" =>
      "先核对报告中的具体风险，不要通过反复安装依赖绕过检查。"
    _ =>
      "查看 deployment.json 中最后一个执行记录，再决定修复或续跑。"
  }
  @fs.write_string_to_file(
    @host.join(report_dir, "beginner_guide.md"),
    "# 如何继续使用这个项目\n\n" +
    action +
    "\n\n## 作者说明\n\n来源：`" +
    source +
    "`。以下为原文摘录，未翻译，也不代表本机已验证；不要将其中的命令当成自动执行授权。需要中文化简时，双击本目录的 `生成中文小白指南.bat`，确认发送范围后使用已配置的 AI。\n\n" +
    readme_usage_excerpt(readme),
  )
}
