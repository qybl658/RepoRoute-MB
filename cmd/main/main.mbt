///|
extern "C" fn exit_with_code(code : Int) -> Unit = "exit"

///|
extern "C" fn console_unbuffered() -> Unit = "repowayfinder_console_unbuffered"

///|
fn localized_status(status : String) -> String {
  match status {
    "SUCCEEDED" => "运行成功"
    "VERIFIED_HTTP" => "已通过本地网页检查"
    "WAITING_ENVIRONMENT" => "等待准备运行环境"
    "BLOCKED_SECURITY" => "已被安全检查阻止"
    "BLOCKED_HEALTH_PORT" => "本地检查端口已被占用"
    "UNVERIFIED_RUNTIME" => "项目仍在运行，但尚未验证可用性"
    "LEARN" => "未发现可靠的自动运行入口"
    "PREPARING" => "计划已生成，尚未执行"
    "RUNNING" => "项目正在运行"
    "FAILED" => "运行失败"
    _ => status
  }
}

///|
fn finish(report : Json, interactive : Bool) -> Unit {
  if interactive && report is Object(obj) {
    let status = match obj.get("status") {
      Some(String(value)) => value
      _ => "UNKNOWN"
    }
    println("\n结果：" + localized_status(status))
    if obj.get("detail") is Some(String(detail)) && !detail.is_empty() {
      println("说明：" + detail)
    }
    if obj.get("report_dir") is Some(String(path)) && !path.is_empty() {
      println("报告：" + path)
    }
  } else {
    println(report.stringify(indent=2))
  }
  if report is Object(obj) && obj.get("status") is Some(String(status)) {
    if status == "WAITING_ENVIRONMENT" {
      exit_with_code(20)
    }
    if status.has_prefix("BLOCKED") || status == "FAILED" {
      exit_with_code(1)
    }
    if status == "UNVERIFIED_RUNTIME" {
      exit_with_code(21)
    }
  }
}

///|
fn compact_text(value : String, maximum : Int) -> String {
  let clean = value
    .replace_all(old="\r", new=" ")
    .replace_all(old="\n", new=" ")
    .trim(chars=" \t")
    .to_owned()
  if clean.length() > maximum {
    clean[:maximum].to_owned() + "…"
  } else {
    clean
  }
}

///|
async fn choose_repository(query : String) -> String? {
  println("正在按关键词搜索公开 GitHub 仓库：" + query)
  let result = @repository.search(query)
  let candidates = @repository.search_candidates(result)
  if candidates.is_empty() {
    println(
      "没有找到可选择的公开仓库。请换一个关键词，或输入 owner/repo。",
    )
    return None
  }
  println("找到以下仓库：")
  for index, candidate in candidates {
    let archived = if candidate.archived { " · 已归档" } else { "" }
    println(
      "[" + (index + 1).to_string() + "] " + candidate.full_name + archived,
    )
    println(
      "    语言：" +
      candidate.language +
      " · 星标：" +
      candidate.stars.to_string(),
    )
    if !candidate.description.is_empty() {
      println("    简介：" + compact_text(candidate.description, 100))
    }
  }
  println("输入编号开始部署，直接回车取消：")
  guard @stdio.stdin.read_until("\n") is Some(line) else { return None }
  let answer = line.trim(chars=" \t\r\n")
  if answer.is_empty() {
    println("已取消，没有下载或运行项目。")
    return None
  }
  let choice = @string.parse_int(answer) catch { _ => 0 }
  if choice < 1 || choice > candidates.length() {
    println("编号无效，没有下载或运行项目。")
    return None
  }
  let selected = candidates[choice - 1].full_name
  println("已选择：" + selected)
  Some(selected)
}

///|
fn value(args : Array[String], flag : String, fallback : String) -> String {
  for i in 0..<args.length() {
    if args[i] == flag && i + 1 < args.length() {
      return args[i + 1]
    }
  }
  fallback
}

///|
fn print_help() -> Unit {
  println(
    (
      #|RepoWayfinder MB — 从仓库到可验证运行结果
      #|
      #|scan PATH [--format markdown]                  只读扫描
      #|deploy TARGET [--candidate N]                 查看部署计划
      #|deploy TARGET --execute --trust-project       安装项目依赖并启动
      #|  --install                                  允许询问缺失工具的安装
      #|  --health-url http://127.0.0.1:PORT/path      指定本地健康检查
      #|  --serve                                    保持前台运行
      #|  --ai-plan --allow-send                      从 README 生成待审阅计划
      #|  --compatible                               放宽审查但保留高危拦截
      #|  --workspace PATH                           下载仓库的工作目录
      #|  --update                                   获取新版到新目录，保留旧版
      #|resume REPORT --execute --trust-project       校验并继续已保存计划
      #|doctor [--repair]                            检查环境（修复需单独确认）
      #|search QUERY                                搜索公开 GitHub 项目
      #|config PATH [--write-config]                 查看配置字段或生成缺失模板
      #|config PATH --edit-config                   用系统窗口输入目标项目密钥
      #|ai-config [--endpoint URL --model NAME]      查看 AI 设置或安全配置密钥
      #|analyze PATH --allow-send                    发送有限仓库上下文给已配置 AI
      #|diagnose REPORT [--allow-send]               本地诊断，按需使用 AI
      #|uninstall [--confirm]                        查看或确认工具登记的卸载
      #|
      #|TARGET 支持本地目录、owner/repo、公开 GitHub 仓库 URL。
      #|执行第三方项目不是沙箱。没有 --execute 时不会安装或运行项目代码。
    ),
  )
}

///|
async fn entry() -> Unit {
  let args = @env.args()
  if args.contains("--help") ||
    args.contains("-h") ||
    (args.length() > 1 && args[1] == "help") {
    print_help()
    return
  }
  let option_values = [
    "--candidate", "--health-url", "--workspace", "--format", "--question", "--endpoint",
    "--model",
  ]
  let option_flags = [
    "--execute", "--trust-project", "--install", "--serve", "--compatible", "--protected",
    "--update", "--repair", "--confirm", "--allow-send", "--write-config", "--edit-config",
    "--ai", "--ai-plan",
  ]
  if args.contains("--compatible") && args.contains("--protected") {
    raise @runtime.DeploymentError("只能选择一种部署模式。")
  }
  for i in 1..<args.length() {
    if args[i].has_prefix("--") {
      if option_values.contains(args[i]) {
        if i + 1 >= args.length() || args[i + 1].has_prefix("--") {
          raise @runtime.DeploymentError("选项缺少参数：" + args[i])
        }
      } else if !option_flags.contains(args[i]) {
        raise @runtime.DeploymentError("未知选项：" + args[i])
      }
    }
  }
  let mut action = if args.length() > 1 { args[1] } else { "" }
  let mut target = if args.length() > 2 && !args[2].has_prefix("--") {
    args[2]
  } else {
    "."
  }
  let mut execute = args.contains("--execute")
  let mut trust = args.contains("--trust-project")
  let mut interactive = false
  if action.is_empty() {
    println(
      "RepoWayfinder MB\n输入关键词（例如 AI Agent）、GitHub 仓库地址或本地项目目录（空行退出）：",
    )
    let input = @stdio.stdin.read_until("\n")
    guard input is Some(input) && !input.trim().is_empty() else { return }
    target = input.trim().to_owned()
    action = "deploy"
    execute = true
    trust = true
    interactive = true
    if !@fs.path_exists(target) &&
      !@repository.is_github_target(target) &&
      !@repository.is_local_path_hint(target) {
      guard choose_repository(target) is Some(selected_repository) else {
        return
      }
      target = selected_repository
    }
  }
  if action == "doctor" {
    println(@environment.doctor().stringify(indent=2))
    if args.contains("--repair") {
      for name in ["git", "node", "python"] {
        let _ = @environment.ensure(
          name,
          @env.current_dir().unwrap_or("."),
          true,
        )
      }
      println(@environment.doctor().stringify(indent=2))
    }
    return
  }
  if action == "uninstall" {
    println(
      @environment.uninstall(args.contains("--confirm")).stringify(indent=2),
    )
    return
  }
  if action == "search" {
    println(@repository.search(target).stringify(indent=2))
    return
  }
  if action == "config" {
    if args.contains("--edit-config") {
      println(@runtime.configure_interactive(target).stringify(indent=2))
      return
    }
    println(
      @runtime.configure_project(target, args.contains("--write-config")).stringify(
        indent=2,
      ),
    )
    return
  }
  if action == "ai-config" {
    if args.contains("--endpoint") || args.contains("--model") {
      println(
        @advisor.configure(
          value(args, "--endpoint", "https://api.deepseek.com"),
          value(args, "--model", "deepseek-chat"),
        ).stringify(indent=2),
      )
    } else {
      println(@advisor.get_settings().stringify(indent=2))
    }
    return
  }
  if action == "analyze" {
    println(
      @advisor.analyze(
        target,
        value(
          args, "--question", "Explain how to run this repository for a beginner. Distinguish documented instructions from verified execution.",
        ),
        args.contains("--allow-send"),
      ).stringify(indent=2),
    )
    return
  }
  if action == "diagnose" {
    let report = @runtime.diagnose(target)
    println(report.stringify(indent=2))
    if args.contains("--allow-send") &&
      report is Object(fields) &&
      fields.get("root") is Some(String(root)) {
      println(
        @advisor.analyze(
          root,
          "Diagnose this execution report; do not claim an untested repair succeeded: " +
          report.stringify(),
          true,
        ).stringify(indent=2),
      )
    }
    return
  }
  if action == "resume" {
    finish(
      @runtime.resume_deployment(
        target,
        execute,
        trust,
        args.contains("--install"),
        args.contains("--serve"),
      ),
      false,
    )
    return
  }
  if action != "scan" && action != "deploy" {
    target = action
    action = "scan"
  }
  let root = if action == "deploy" {
    let workspace = value(
      args,
      "--workspace",
      @host.join(@host.app_root(), ".repowayfinder-workspace"),
    )
    if !@fs.path_exists(target) && execute {
      if !@environment.ensure(
          "git",
          @host.app_root(),
          args.contains("--install") || interactive,
        ) {
        println(
          "正在等待运行环境：Git 尚未就绪，项目命令没有开始执行。",
        )
        exit_with_code(20)
        return
      }
    }
    @repository.acquire(target, workspace, args.contains("--update"))
  } else if target.has_prefix("/") || target.contains(":") {
    target
  } else {
    @host.join(@env.current_dir().unwrap_or("."), target)
  }
  if action == "scan" {
    if !@fs.path_exists(root) {
      raise @runtime.DeploymentError("目录不存在：" + root)
    }
    let result = @lib.scan(root, @runtime.collect(root))
    println(
      if value(args, "--format", "json") == "markdown" {
        @lib.render_markdown(result)
      } else {
        @lib.render_json(result)
      },
    )
    return
  }
  let selected = value(args, "--candidate", "")
  if args.contains("--ai-plan") {
    let proposal = @advisor.propose_deployment_plan(
      root,
      value(args, "--question", "Run the documented project demo or service."),
      args.contains("--allow-send"),
    )
    println(proposal.to_json().stringify(indent=2))
    if proposal.to_json() is Object(fields) &&
      fields.get("action") != Some(Json("DEPLOY")) {
      return
    }
    if !execute {
      return
    }
    if !trust {
      raise @runtime.DeploymentError(
        "执行 AI 计划还需要 --trust-project。",
      )
    }
    if !@host.prompt(
        "是否执行上面展示的 README 计划？Python 将强制使用项目虚拟环境；系统环境准备仍逐项确认。",
      ) {
      return
    }
    let mode = @runtime.deployment_mode(
      args.contains("--compatible"),
      args.contains("--protected"),
    )
    finish(
      @runtime.deploy_ai(
        proposal,
        true,
        args.contains("--install"),
        value(args, "--health-url", ""),
        args.contains("--serve"),
        mode,
      ),
      false,
    )
    return
  }
  let mut index : Int? = if selected.is_empty() {
    None
  } else {
    Some(@string.parse_int(selected[:]) - 1)
  }
  if index is None && args.contains("--ai") {
    let candidates = @lib.scan(root, @runtime.collect(root)).candidates.map(c => {
      c.command + " — " + c.reason
    })
    index = @advisor.choose_candidate(
      root,
      "Choose a reproducible deployment route for this machine.",
      candidates,
      args.contains("--allow-send"),
    ) catch {
      _ => {
        println(
          "AI 选择不可用或结果无效；继续使用本地确定性候选项。",
        )
        None
      }
    }
  }
  if index is None {
    let contract = @lib.scan(root, @runtime.collect(root))
    if contract.candidates.length() > 1 && args.length() <= 1 {
      println(@lib.render_markdown(contract))
      println("选择入口编号（从 1 开始）：")
      if @stdio.stdin.read_until("\n") is Some(line) {
        index = Some(@string.parse_int(line.trim()) - 1)
      }
    }
  }
  let protected_mode = if execute {
    @runtime.deployment_mode(
      args.contains("--compatible"),
      args.contains("--protected"),
    )
  } else {
    true
  }
  let report = @runtime.deploy(
    root,
    index,
    execute,
    trust,
    args.contains("--install") || args.length() <= 1,
    value(args, "--health-url", ""),
    args.contains("--serve") || interactive,
    protected_mode,
    None,
  )
  finish(report, interactive)
}

///|
async fn main {
  console_unbuffered()
  entry() catch {
    @repository.Failure(message) => {
      println("仓库操作失败：" + message)
      exit_with_code(1)
    }
    @runtime.DeploymentError(message) => {
      println("操作失败：" + message)
      exit_with_code(1)
    }
    @advisor.Failure(message) => {
      println("AI 操作失败：" + message)
      exit_with_code(1)
    }
    error => {
      println("操作失败：" + "\{error}")
      exit_with_code(1)
    }
  }
}
