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
    "`。以下为原文摘录，未翻译，也不代表本机已验证；不要将其中的命令当成自动执行授权。\n\n" +
    readme_usage_excerpt(readme),
  )
}
