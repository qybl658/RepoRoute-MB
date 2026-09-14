///|
extern "C" fn exit_with_code(code : Int) -> Unit = "exit"

///|
fn finish(report : Json) -> Unit {
  println(report.stringify(indent=2))
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
      #|  --compatible                               放宽审查但保留高危拦截
      #|  --workspace PATH                           下载仓库的工作目录
      #|  --update                                   获取新版到新目录，保留旧版
      #|resume REPORT --execute --trust-project       校验并继续已保存计划
      #|doctor [--repair]                            检查环境（修复需单独确认）
      #|search QUERY                                搜索公开 GitHub 项目
      #|config PATH [--write-config]                 查看配置字段或生成缺失模板
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
    "--update", "--repair", "--confirm", "--allow-send", "--write-config", "--ai",
  ]
  if args.contains("--compatible") && args.contains("--protected") {
    raise @runtime.DeploymentError("Choose one deployment mode.")
  }
  for i in 1..<args.length() {
    if args[i].has_prefix("--") {
      if option_values.contains(args[i]) {
        if i + 1 >= args.length() || args[i + 1].has_prefix("--") {
          raise @runtime.DeploymentError("Missing value for " + args[i])
        }
      } else if !option_flags.contains(args[i]) {
        raise @runtime.DeploymentError("Unknown option: " + args[i])
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
  if action.is_empty() {
    println(
      "RepoWayfinder MB\n输入 GitHub 仓库地址或本地项目目录（空行退出）：",
    )
    let input = @stdio.stdin.read_until("\n")
    guard input is Some(input) && !input.trim().is_empty() else { return }
    target = input.trim().to_owned()
    action = "deploy"
    execute = @host.prompt(
      "是否准备依赖并运行该项目？这会在本机执行第三方代码。",
    )
    trust = execute
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
          args.contains("--install"),
        ) {
        println(
          "WAITING_ENVIRONMENT: Git is not ready; no project commands started.",
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
      raise @runtime.DeploymentError("Directory does not exist: " + root)
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
          "AI selection unavailable or invalid; retaining deterministic candidates.",
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
    args.contains("--serve"),
    protected_mode,
    None,
  )
  finish(report)
}

///|
async fn main {
  entry()
}
