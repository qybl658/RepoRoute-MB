///|
pub(all) suberror DeploymentError {
  DeploymentError(String)
}

///|
pub fn collect(root : String) -> Array[@lib.SourceFile] {
  let files : Array[@lib.SourceFile] = []
  for
    name in [
      "package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock",
      "bun.lockb", "pyproject.toml", "requirements.txt", "Cargo.toml", "Cargo.lock",
      "moon.mod", "cmd/main/moon.pkg", "compose.yaml", "compose.yml", "docker-compose.yaml",
      "docker-compose.yml", "Dockerfile", "Procfile", "Procfile.windows", "main.py",
      "app.py", "setup.py", "demo.py", "example.py", "examples/main.py", "examples/demo.py",
      "examples/example.py", "demo/main.py",
    ] {
    let path = @host.join(root, name)
    if @fs.path_exists(path) && (@fs.is_file(path) catch { _ => false }) {
      let content = @fs.read_file_to_string(path) catch { _ => "" }
      files.push(@lib.source_file(name, content))
    }
  }
  files
}

///|
fn ensure_dir(path : String) -> Unit raise {
  if !@fs.path_exists(path) {
    @fs.create_dir(path)
  }
}

///|
fn report_base() -> String raise {
  let root = @host.join(@host.app_root(), ".repowayfinder-reports")
  ensure_dir(root)
  root
}

///|
fn save(
  report_dir : String,
  root : String,
  candidate : Int,
  status : String,
  detail : String,
  attempts : Array[Json],
  plan : Json,
  health : String,
) -> Json raise {
  let report : Json = {
    "schema_version": 1,
    "root": root,
    "candidate": candidate,
    "status": status,
    "detail": detail,
    "attempts": attempts,
    "plan": plan,
    "health_url": health,
    "report_dir": report_dir,
  }
  @fs.write_string_to_file(
    @host.join(report_dir, "deployment.json"),
    @host.redact(report.stringify(indent=2)),
  )
  let guide = "# RepoWayfinder MB 部署结果\n\n状态：" +
    status +
    "\n\n" +
    detail +
    "\n\n## 下一步\n\n" +
    (if status == "WAITING_ENVIRONMENT" {
      "准备提示的环境后执行 `repowayfinder resume <本目录/deployment.json> --execute --trust-project`。续跑会重新核对配置和环境。"
    } else if status == "SUCCEEDED" {
      "本次命令已经正常退出。若需要持续使用，请通过相同 deploy 命令重新启动。"
    } else if status == "VERIFIED_HTTP" {
      "启动期间本地 HTTP 检查成功；本次验证结束后已停止所启动的进程。使用 --serve 保持前台运行。"
    } else if status == "UNVERIFIED_RUNTIME" {
      "进程在观察期内未退出，但没有健康检查证据，不能确认项目可用。指定 --health-url 后重试。"
    } else {
      "查看下面的逐步结果；先修复报告指出的问题，不要重复安装已有的系统运行时。"
    }) +
    "\n\n## 执行记录\n\n```json\n" +
    @host.redact(report.stringify(indent=2)) +
    "\n```\n"
  @fs.write_string_to_file(@host.join(report_dir, "README.md"), guide)
  report
}

///|
pub async fn deploy(
  root : String,
  index : Int?,
  execute : Bool,
  trust : Bool,
  allow_install : Bool,
  health : String,
  serve : Bool,
  protected_mode : Bool,
  existing_report : String?,
  approved_plan? : @lib.DeploymentPlan? = None,
) -> Json {
  if !@fs.path_exists(root) || !(@fs.is_dir(root) catch { _ => false }) {
    raise DeploymentError("Repository directory does not exist: " + root)
  }
  if !health.is_empty() && !@lib.local_health_url(health) {
    raise DeploymentError(
      "Health URL must be an explicit loopback http://host:port URL.",
    )
  }
  let files = collect(root)
  let contract = @lib.scan(root, files)
  if approved_plan is None && contract.candidates.is_empty() && index is None {
    let report_dir = @host.join(report_base(), @env.now().to_string())
    ensure_dir(report_dir)
    return save(
      report_dir,
      root,
      -1,
      "LEARN",
      "没有发现可验证的启动入口。这可能是库、资料仓库或非标准项目，不表示运行失败。先查看项目 README 的安装与示例章节；不要凭空执行猜测命令。可使用 analyze 分析公开说明，补充明确入口后重新 deploy。",
      [],
      contract.to_json(),
      health,
    )
  }
  let plan = match approved_plan {
    Some(plan) => plan
    None =>
      match @lib.plan_deployment(contract, files, index, @host.windows()) {
        Ok(plan) => plan
        Err(message) => {
          println(@lib.render_markdown(contract))
          raise DeploymentError(message)
        }
      }
  }
  let health = if health.is_empty() && plan.candidate.ecosystem == "docker" {
    let ports = files
      .filter(f => f.path == "Dockerfile")
      .map(f => @lib.docker_exposed_ports(f.content))
      .flatten()
    if ports.is_empty() {
      ""
    } else {
      "http://127.0.0.1:" + ports[0] + "/"
    }
  } else {
    health
  }
  if !execute {
    return plan.to_json()
  }
  if !trust {
    raise DeploymentError(
      "Execution requires --trust-project: installs/builds run third-party code on this host, without a sandbox.",
    )
  }
  let report_dir = match existing_report {
    Some(path) => path
    None => {
      let path = @host.join(report_base(), @env.now().to_string())
      ensure_dir(path)
      path
    }
  }
  let attempts : Array[Json] = []
  if @host.windows() {
    let executable = @afs.realpath(@env.args()[0][:])
    let report_path = @host.join(report_dir, "deployment.json")
    @fs.write_string_to_file(
      @host.join(report_dir, "查看诊断.bat"),
      @host.windows_launcher(
        executable,
        ["diagnose", report_path],
        @host.app_root(),
        false,
      ),
    )
    @fs.write_string_to_file(
      @host.join(report_dir, "准备好环境后点我继续.bat"),
      @host.windows_launcher(
        executable,
        [
          "resume", report_path, "--execute", "--trust-project", "--install", "--serve",
        ],
        @host.app_root(),
        true,
      ),
    )
    @fs.write_string_to_file(
      @host.join(report_dir, "获取新版并运行.bat"),
      @host.windows_launcher(
        executable,
        [
          "deploy", root, "--update", "--execute", "--trust-project", "--install",
          "--serve",
        ],
        @host.app_root(),
        true,
      ),
    )
  }
  let image_name = "repowayfinder-mb-app-" + @env.now().to_string()
  let findings = @lib.security_review(
    files,
    plan.candidate.ecosystem,
    protected_mode,
  )
  if findings.any(f => f.level == "error") {
    let messages = findings.map(f => f.file + ": " + f.message).join("\n")
    return save(
      report_dir,
      root,
      plan.candidate_index,
      "BLOCKED_SECURITY",
      messages,
      attempts,
      plan.to_json(),
      health,
    )
  }
  let _ = save(
    report_dir,
    root,
    plan.candidate_index,
    "PREPARING",
    "Checking required runtimes before project execution.",
    attempts,
    plan.to_json(),
    health,
  )
  let configuration = configure_project(root, true)
  println(configuration.stringify())
  for step in plan.steps {
    if step.phase != "preflight" {
      continue
    }
    if !@environment.ensure(step.program, root, allow_install) {
      return save(
        report_dir,
        root,
        plan.candidate_index,
        "WAITING_ENVIRONMENT",
        "Not ready: " + step.program + ". No project commands were started.",
        attempts,
        plan.to_json(),
        health,
      )
    }
    let probe = @host.run(step.program, step.args, root, 30000)
    if probe.code != 0 {
      return save(
        report_dir,
        root,
        plan.candidate_index,
        "WAITING_ENVIRONMENT",
        step.program + ": " + probe.output,
        attempts,
        plan.to_json(),
        health,
      )
    }
  }
  for step in plan.steps {
    if step.phase == "preflight" {
      continue
    }
    let step : @lib.DeploymentStep = {
      phase: step.phase,
      program: step.program,
      args: step.args.map(arg => {
        if arg == "repowayfinder-mb-app" {
          image_name
        } else {
          arg
        }
      }),
    }
    println("[" + step.phase + "] " + step.program + " " + step.args.join(" "))
    if step.phase == "start" {
      let initial = launch(step, root, health, serve)
      let mut status = initial.0
      let mut result = initial.1
      attempts.push({
        "phase": step.phase,
        "program": step.program,
        "args": step.args,
        "result": result,
      })
      if status == "FAILED" && plan.candidate.ecosystem.has_prefix("python") {
        if repair_missing_python(root, result, allow_install) is Some(repaired) {
          attempts.push({ "phase": "repair-missing-python", "result": repaired })
          if repaired.code == 0 {
            let (retried_status, retried_result) = launch(
              step, root, health, serve,
            )
            status = retried_status
            result = retried_result
            attempts.push({ "phase": "start-after-repair", "result": result })
          }
        }
      }
      return save(
        report_dir,
        root,
        plan.candidate_index,
        status,
        result.output,
        attempts,
        plan.to_json(),
        health,
      )
    }
    let mut result = @host.run(step.program, step.args, root, 600000)
    if result.code != 0 &&
      !result.timed_out &&
      ["install", "build"].contains(step.phase) &&
      transient_network_failure(result.output) {
      attempts.push({
        "phase": step.phase,
        "program": step.program,
        "args": step.args,
        "result": result,
        "retry_reason": "recognized transient transport failure; one bounded retry",
      })
      result = @host.run(step.program, step.args, root, 600000)
    }
    if step.phase == "validate-compose" {
      if result.code != 0 {
        return save(
          report_dir,
          root,
          plan.candidate_index,
          "BLOCKED_SECURITY",
          "Compose configuration could not be resolved. Inspect it locally; resolved values are not copied to reports.",
          attempts,
          plan.to_json(),
          health,
        )
      }
      let config = @json.parse(result.output) catch { _ => Json::null() }
      if @lib.validate_compose(config, protected_mode) is Err(message) {
        return save(
          report_dir,
          root,
          plan.candidate_index,
          "BLOCKED_SECURITY",
          message,
          attempts,
          plan.to_json(),
          health,
        )
      }
      continue
    }
    attempts.push({
      "phase": step.phase,
      "program": step.program,
      "args": step.args,
      "result": result,
    })
    if result.code != 0 {
      return save(
        report_dir,
        root,
        plan.candidate_index,
        "FAILED",
        result.output,
        attempts,
        plan.to_json(),
        health,
      )
    }
    let _ = save(
      report_dir,
      root,
      plan.candidate_index,
      "RUNNING",
      "Completed " + step.phase,
      attempts,
      plan.to_json(),
      health,
    )
  }
  save(
    report_dir,
    root,
    plan.candidate_index,
    "FAILED",
    "Plan contained no start step.",
    attempts,
    plan.to_json(),
    health,
  )
}

///|
async fn launch(
  step : @lib.DeploymentStep,
  root : String,
  health : String,
  serve : Bool,
) -> (String, @host.CommandResult) {
  let baseline = if health.is_empty() && @host.windows() {
    @host.run("netstat", ["-an", "-p", "TCP"], root, 5000)
  } else {
    { code: 1, output: "", timed_out: false, }
  }
  if !health.is_empty() {
    let before = @host.run(
      "curl",
      [
        "--disable", "--noproxy", "*", "--fail", "--silent", "--max-time", "2", health,
      ],
      root,
      4000,
    )
    if before.code == 0 {
      return (
        "BLOCKED_HEALTH_PORT",
        {
          code: 1,
          output: "Health URL already responds before launch; refusing to attribute another service to this deployment.",
          timed_out: false,
        },
      )
    }
  }
  @async.with_task_group() <| group => {
    let args = step.args.copy()
    let owned_name = "repowayfinder-mb-" + @env.now().to_string()
    if step.program == "docker" && args[0] == "compose" {
      args.insert(1, "--project-name")
      args.insert(2, owned_name)
      group.add_defer(() => {
        let _ = @host.run(
          "docker",
          ["compose", "--project-name", owned_name, "-f", step.args[2], "down"],
          root,
          30000,
        )
      })
    } else if step.program == "docker" && args[0] == "run" {
      args.insert(1, "--name")
      args.insert(2, owned_name)
      group.add_defer(() => {
        let _ = @host.run("docker", ["stop", owned_name], root, 15000)
      })
    }
    let mut observed = ""
    let child = group.spawn(() => {
      @host.run(
        step.program,
        args,
        root,
        if serve {
          86400000
        } else {
          30000
        },
        on_output=text => observed = text,
      )
    })
    for _i in 0..<30 {
      if child.try_wait() is Some(result) {
        return (if result.code == 0 { "SUCCEEDED" } else { "FAILED" }, result)
      }
      let probe_url = if !health.is_empty() {
        health
      } else if baseline.code == 0 {
        automatic_url(observed, baseline.output)
      } else {
        ""
      }
      if !probe_url.is_empty() {
        let check = @host.run(
          "curl",
          [
            "--disable", "--noproxy", "*", "--fail", "--silent", "--max-time", "1",
            probe_url,
          ],
          root,
          2000,
        )
        if check.code == 0 {
          if serve {
            println("HTTP ready: " + probe_url + " (Ctrl+C to stop)")
            let result = child.wait()
            return (
              if result.code == 0 {
                "SUCCEEDED"
              } else {
                "FAILED"
              },
              result,
            )
          }
          child.cancel()
          return (
            "VERIFIED_HTTP",
            {
              code: 0,
              output: "HTTP health check passed at " +
              probe_url +
              "; verification process stopped.",
              timed_out: false,
            },
          )
        }
      }
      @async.sleep(500)
    }
    if serve {
      println(
        "Process running; waiting in foreground. No HTTP acceptance evidence yet.",
      )
      let result = child.wait()
      (if result.code == 0 { "SUCCEEDED" } else { "FAILED" }, result)
    } else {
      child.cancel()
      (
        "UNVERIFIED_RUNTIME",
        {
          code: 0,
          output: "Process stayed alive without verified HTTP health; stopped after observation.",
          timed_out: false,
        },
      )
    }
  }
}

///|
fn automatic_url(output : String, baseline : String) -> String {
  for part in output.split("http://") {
    let token = part
      .split("\n")
      .next()
      .unwrap()
      .split(" ")
      .next()
      .unwrap()
      .trim(chars="\r\t\"'(),;")
      .to_owned()
    let url = "http://" + token
    if @lib.local_health_url(url) {
      let host_port = token.split("/").next().unwrap().to_owned()
      let port = host_port.split(":").last().unwrap().to_owned()
      if !baseline.contains((":" + port)[:]) {
        return url
      }
    }
  }
  ""
}

///|
pub async fn resume_deployment(
  path : String,
  execute : Bool,
  trust : Bool,
  allow_install : Bool,
  serve : Bool,
) -> Json {
  let parsed = @json.parse(@fs.read_file_to_string(path))
  guard parsed is Object(obj) &&
    obj.get("root") is Some(String(root)) &&
    obj.get("candidate") is Some(Number(index, ..)) &&
    obj.get("plan") is Some(old_plan) &&
    obj.get("schema_version") == Some(Json(1)) else {
    raise DeploymentError("Invalid saved deployment report.")
  }
  let canonical = @afs.realpath(path[:])
  let parts = canonical
    .replace_all(old="\\", new="/")
    .split("/")
    .map(p => p.to_owned())
    .collect()
  let _ = parts.pop()
  let report_dir = parts.join("/")
  let files = collect(root)
  let approved_plan = if index == -1 {
    let original = @json.parse(
      @fs.read_file_to_string(@host.join(report_dir, "ai-proposal.json")),
    )
    let mut readme = ""
    for
      name in [
        "README.md", "README-en.md", "README.zh-CN.md", "README", "readme.md",
      ] {
      let file = @host.join(root, name)
      if @fs.path_exists(file) {
        readme += (@fs.read_file_to_string(file) catch { _ => "" }) + "\n"
      }
    }
    let proposal = match
      @lib.parse_ai_deployment_proposal(original, root, readme) {
      Ok(proposal) => proposal
      Err(message) =>
        raise DeploymentError(
          "Saved AI plan no longer matches README evidence: " + message,
        )
    }
    Some(normalize_ai_plan(proposal, true))
  } else {
    None
  }
  let new_plan = match approved_plan {
    Some(plan) => plan.to_json()
    None =>
      match
        @lib.plan_deployment(
          @lib.scan(root, files),
          files,
          Some(index.to_int()),
          @host.windows(),
        ) {
        Ok(plan) => plan.to_json()
        Err(message) => raise DeploymentError(message)
      }
  }
  if new_plan != old_plan {
    raise DeploymentError(
      "Entrypoint/plan changed since this report; run deploy again and review the new plan.",
    )
  }
  let health = match obj.get("health_url") {
    Some(String(url)) => url
    _ => ""
  }
  if execute {
    @fs.write_string_to_file(
      @host.join(report_dir, "previous-" + @env.now().to_string() + ".json"),
      parsed.stringify(indent=2),
    )
  }
  deploy(
    root,
    Some(index.to_int()),
    execute,
    trust,
    allow_install,
    health,
    serve,
    true,
    Some(report_dir),
    approved_plan~,
  )
}
