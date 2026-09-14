///|
pub fn normalize_ai_plan(
  proposal : @lib.AiDeploymentProposal,
  authorized : Bool,
) -> @lib.DeploymentPlan raise {
  let source = proposal.authorize(authorized).unwrap_or([])
  if source.is_empty() {
    raise DeploymentError("AI deployment requires an authorized nonempty plan.")
  }
  if source.any(s => s.program.to_lower().contains("docker")) {
    raise DeploymentError(
      "Use the detected Docker/Compose candidate for container execution so task-owned cleanup and resolved security checks are preserved.",
    )
  }
  let python_used = source.any(s => {
    s.program.to_lower().contains("python") ||
    ["py", "pip", "pip3", "pip.exe"].contains(s.program)
  })
  let steps : Array[@lib.DeploymentStep] = []
  let required : Array[String] = []
  if python_used {
    required.push(if @host.windows() { "python" } else { "python3" })
  }
  for step in source {
    if step.program.contains("/") ||
      step.program.contains("\\") ||
      ["py", "pip", "pip3", "pip.exe", "python", "python3", "python.exe"].contains(
        step.program,
      ) {
      continue
    }
    if [
        "npm", "npm.cmd", "yarn", "yarn.cmd", "pnpm", "pnpm.cmd", "npx", "npx.cmd",
      ].contains(step.program) &&
      !required.contains("node") {
      required.push("node")
    }
    if !required.contains(step.program) {
      required.push(step.program)
    }
  }
  for program in required {
    steps.push({
      phase: "preflight",
      program,
      args: if ["moon", "moon.exe", "go"].contains(program) {
        ["version"]
      } else {
        ["--version"]
      },
    })
  }
  let python = if @host.windows() { "python" } else { "python3" }
  let local_python = if @host.windows() {
    ".repowayfinder-venv/Scripts/python.exe"
  } else {
    ".repowayfinder-venv/bin/python"
  }
  if python_used {
    steps.push({
      phase: "prepare",
      program: python,
      args: ["-m", "venv", ".repowayfinder-venv"],
    })
  }
  for step in source {
    if step.phase == "preflight" {
      continue
    }
    if python_used && step.phase == "prepare" && step.args.contains("venv") {
      continue
    }
    if [
        "py", "python", "python3", "python.exe", ".repowayfinder-venv/Scripts/python.exe",
        ".repowayfinder-venv/bin/python",
      ].contains(step.program) {
      steps.push({ phase: step.phase, program: local_python, args: step.args, })
    } else if ["pip", "pip3", "pip.exe"].contains(step.program) {
      let args = ["-m", "pip"]
      args.append(step.args)
      steps.push({ phase: step.phase, program: local_python, args, })
    } else {
      steps.push(step)
    }
  }
  {
    root: proposal.deployment_root(),
    candidate_index: -1,
    candidate: {
      ecosystem: if python_used {
        "ai-python"
      } else {
        "ai-readme"
      },
      command: "README-backed argv plan",
      workdir: ".",
      confidence: 80,
      prerequisites: required,
      reason: "User-reviewed README-backed model proposal; runtime preflights and Python isolation are enforced locally.",
      evidence: {
        file: "README",
        line: 1,
        excerpt: "See ai-proposal.json for source evidence.",
      },
    },
    steps,
    warnings: [
      "Model output is validated, but repository commands still execute third-party code on this computer.",
    ],
  }
}

///|
pub async fn deploy_ai(
  proposal : @lib.AiDeploymentProposal,
  trust : Bool,
  allow_install : Bool,
  health : String,
  serve : Bool,
  protected_mode : Bool,
) -> Json {
  let plan = normalize_ai_plan(proposal, trust)
  let directory = @host.join(report_base(), @env.now().to_string())
  ensure_dir(directory)
  @fs.write_string_to_file(
    @host.join(directory, "ai-proposal.json"),
    @host.redact(proposal.to_json().stringify(indent=2)),
  )
  deploy(
    plan.root,
    None,
    true,
    trust,
    allow_install,
    health,
    serve,
    protected_mode,
    Some(directory),
    approved_plan=Some(plan),
  )
}
