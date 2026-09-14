///|
/// A validated AI deployment proposal. Its executable steps remain private
/// until the caller explicitly authorizes the reviewed proposal.
pub struct AiDeploymentProposal {
  root : String
  action : String
  steps : Array[DeploymentStep]
  review_steps : Array[Json]
  reason : String
  evidence : Array[String]
}

///|
fn ai_plan_text(
  object : Map[String, Json],
  name : String,
  maximum : Int,
) -> Result[String, String] {
  guard object.get(name) is Some(String(value)) else {
    return Err("Plan field '" + name + "' must be a string.")
  }
  let clean = value.trim(chars=" \t\r\n").to_owned()
  if clean.is_empty() || clean.length() > maximum {
    Err(
      "Plan field '" +
      name +
      "' must contain 1 to " +
      maximum.to_string() +
      " characters.",
    )
  } else {
    Ok(clean)
  }
}

///|
fn ai_plan_safe_token(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 256 &&
  !value.contains("\r") &&
  !value.contains("\n") &&
  !value.contains("\u{0000}") &&
  !value.contains(";") &&
  !value.contains("&") &&
  !value.contains("|") &&
  !value.contains("<") &&
  !value.contains(">") &&
  !value.contains("`") &&
  !value.contains("${") &&
  !value.contains("$(") &&
  !value.contains("%") &&
  !value.contains("://") &&
  !value.has_prefix("@") &&
  !value.has_prefix("~") &&
  !value.has_prefix("/") &&
  !value.has_prefix("\\") &&
  !(value.length() >= 2 && value[1] == ':') &&
  !value.replace_all(old="\\", new="/").split("/").any(part => part == "..")
}

///|
fn ai_plan_safe_program(value : String) -> Bool {
  let normalized = value.replace_all(old="\\", new="/").to_lower()
  let basename = normalized.split("/").last().unwrap_or("").to_owned()
  let allowed = [
    "python", "python.exe", "python3", "py", "pip", "pip.exe", "pip3", "uv", "poetry",
    "npm", "npm.cmd", "pnpm", "pnpm.cmd", "yarn", "yarn.cmd", "node", "node.exe",
    "npx", "npx.cmd", "corepack", "cargo", "go", "dotnet", "java", "mvn", "mvn.cmd",
    "gradle", "gradle.bat", "gradlew", "gradlew.bat", "moon", "moon.exe", "docker",
    "docker.exe", "docker-compose", "docker-compose.exe",
  ]
  guard allowed.contains(basename) else { return false }
  if normalized == basename {
    return true
  }
  // A planner may refer to the venv it created, but never to another relative
  // executable or an absolute host path.
  normalized == ".repowayfinder-venv/scripts/python.exe" ||
  normalized == ".repowayfinder-venv/bin/python"
}

///|
fn ai_plan_forbidden_argument(value : String) -> Bool {
  let lower = value.to_lower()
  [
    "--password", "--token", "--api-key", "--apikey", "--secret", "--registry", "--global",
    "-g", "--prefix", "--target", "--root", "--user", "--privileged", "--cap-add",
    "--device", "--pid", "--ipc", "--security-opt", "--env-file", "--env", "-e",
    "--entrypoint", "--mount", "--volume", "-v", "--network", "--interactive", "--tty",
    "-i", "-t", "-it",
  ].any(flag => lower == flag || lower.has_prefix(flag + "="))
}

///|
fn ai_plan_safe_operation(program : String, args : Array[String]) -> Bool {
  guard !args.is_empty() else { return false }
  let base = program
    .replace_all(old="\\", new="/")
    .split("/")
    .last()
    .unwrap()
    .to_owned()
    .to_lower()
  let first = args[0].to_lower()
  if base == "python" ||
    base == "python.exe" ||
    base == "python3" ||
    base == "py" {
    if ["-c", "-e", "-"].contains(first) || first.has_prefix("-c") {
      return false
    }
    if first == "-m" && args.length() >= 2 && args[1].to_lower() == "pip" {
      return args.length() >= 3 &&
        ["install", "check", "--version"].contains(args[2].to_lower())
    }
  }
  if (base == "node" || base == "node.exe") &&
    (
      ["-e", "--eval", "-p", "--print", "-"].contains(first) ||
      first.has_prefix("--eval=")
    ) {
    return false
  }
  if base == "npm" || base == "npm.cmd" {
    if first == "run" {
      return args.length() >= 2 &&
        ["start", "dev", "serve", "preview", "demo", "example", "test", "build"].contains(
          args[1].to_lower(),
        )
    }
    return ["--version", "ci", "install", "start", "test"].contains(first)
  }
  if base == "pnpm" ||
    base == "pnpm.cmd" ||
    base == "yarn" ||
    base == "yarn.cmd" {
    if first == "run" {
      return args.length() >= 2 &&
        ["start", "dev", "serve", "preview", "demo", "example", "test", "build"].contains(
          args[1].to_lower(),
        )
    }
    return ["--version", "install", "start", "test", "build"].contains(first)
  }
  if base == "npx" || base == "npx.cmd" {
    return first == "--no-install" && args.length() >= 2
  }
  if base == "corepack" {
    return first == "--version"
  }
  if base == "pip" || base == "pip.exe" || base == "pip3" {
    return ["--version", "install", "check"].contains(first)
  }
  if base == "uv" {
    if first == "pip" {
      return args.length() >= 2 &&
        ["install", "check", "compile"].contains(args[1].to_lower())
    }
    return ["--version", "sync", "run", "venv", "pip"].contains(first)
  }
  if base == "poetry" {
    return ["--version", "install", "run", "build", "check"].contains(first)
  }
  if base == "cargo" {
    return ["--version", "fetch", "build", "run", "test", "check"].contains(
      first,
    )
  }
  if base == "go" {
    return ["version", "mod", "build", "run", "test"].contains(first)
  }
  if base == "dotnet" {
    return ["--version", "restore", "build", "run", "test"].contains(first)
  }
  if base == "mvn" ||
    base == "mvn.cmd" ||
    base == "gradle" ||
    base == "gradle.bat" ||
    base == "gradlew" ||
    base == "gradlew.bat" {
    return !["publish", "upload", "release"].contains(first)
  }
  if base == "moon" || base == "moon.exe" {
    return ["version", "update", "check", "build", "run", "test"].contains(
      first,
    )
  }
  if base == "docker" || base == "docker.exe" {
    if first == "compose" {
      return args.length() >= 2 &&
        ["version", "config", "build", "up"].contains(args[1].to_lower())
    }
    return ["info", "version", "build", "run", "compose"].contains(first)
  }
  if base == "docker-compose" || base == "docker-compose.exe" {
    return ["version", "config", "build", "up"].contains(first)
  }
  true
}

///|
fn parse_ai_plan_arguments(value : Json) -> Result[Array[String], String] {
  guard value is Array(values) else {
    return Err("Every deployment step must contain an argv array.")
  }
  if values.length() > 32 {
    return Err("A deployment step may contain at most 32 arguments.")
  }
  let result : Array[String] = []
  let mut total = 0
  for value in values {
    guard value is String(argument) else {
      return Err("Every argv element must be a string.")
    }
    if !ai_plan_safe_token(argument) || ai_plan_forbidden_argument(argument) {
      return Err("Unsafe deployment argument was rejected.")
    }
    total += argument.length()
    if total > 4096 {
      return Err("Deployment argv exceeds the 4096-character limit.")
    }
    result.push(argument)
  }
  Ok(result)
}

///|
fn ai_plan_phase_rank(phase : String) -> Int? {
  match phase {
    "preflight" => Some(0)
    "prepare" => Some(1)
    "install" => Some(2)
    "build" => Some(3)
    "start" => Some(4)
    _ => None
  }
}

///|
fn normalized_ai_plan_documentation(value : String) -> String {
  let mut result = value
    .to_lower()
    .replace_all(old="\r", new=" ")
    .replace_all(old="\n", new=" ")
    .replace_all(old="\t", new=" ")
  while result.contains("  ") {
    result = result.replace_all(old="  ", new=" ")
  }
  result
}

///|
fn documented_ai_plan_command(
  documentation : String,
  program : String,
  args : Array[String],
) -> Bool {
  let basename = program
    .replace_all(old="\\", new="/")
    .split("/")
    .last()
    .unwrap_or("")
    .to_owned()
    .to_lower()
  let portable_name = if basename.has_suffix(".exe") {
    basename[:basename.length() - 4].to_owned()
  } else if basename.has_suffix(".cmd") || basename.has_suffix(".bat") {
    basename[:basename.length() - 4].to_owned()
  } else {
    basename
  }
  let command = portable_name +
    (if args.is_empty() { "" } else { " " + args.join(" ") })
  normalized_ai_plan_documentation(documentation).contains(command[:])
}

///|
fn parse_ai_plan_evidence(value : Json?) -> Result[Array[String], String] {
  let values = match value {
    None => return Ok([])
    Some(Array(items)) => items
    _ => return Err("Plan evidence must be an array of strings.")
  }
  if values.length() > 12 {
    return Err("Plan evidence may contain at most 12 entries.")
  }
  let result : Array[String] = []
  for value in values {
    guard value is String(text) else {
      return Err("Plan evidence entries must be strings.")
    }
    let clean = text.trim(chars=" \t\r\n").to_owned()
    if clean.is_empty() || clean.length() > 500 {
      return Err("Plan evidence entries must contain 1 to 500 characters.")
    }
    result.push(clean)
  }
  Ok(result)
}

///|
/// Parse and validate an untrusted model response into a non-shell proposal.
///
/// `workdir` is intentionally required to be `.`. The executor can therefore
/// run every returned step at the already-canonicalized repository root without
/// interpreting model-generated paths.
pub fn parse_ai_deployment_proposal(
  value : Json,
  root : String,
  readme : String,
) -> Result[AiDeploymentProposal, String] {
  guard !root.is_empty() &&
    root.length() <= 4096 &&
    !root.contains("\r") &&
    !root.contains("\n") &&
    !root.contains("\u{0000}") else {
    return Err("Canonical deployment root is invalid.")
  }
  guard value is Object(object) else {
    return Err("AI deployment plan must be one JSON object.")
  }
  if ["cmd", "command", "shell", "script"].any(name => {
      object.get(name) is Some(_)
    }) {
    return Err("Raw command or shell fields are forbidden in an AI plan.")
  }
  let action = match ai_plan_text(object, "action", 16) {
    Ok(value) => value.to_upper()
    Err(error) => return Err(error)
  }
  if !["DEPLOY", "LEARN", "IGNORE"].contains(action) {
    return Err("Plan action must be DEPLOY, LEARN, or IGNORE.")
  }
  let reason = match ai_plan_text(object, "reason", 2000) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let evidence = match parse_ai_plan_evidence(object.get("evidence")) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  guard object.get("steps") is Some(Array(raw_steps)) else {
    return Err("Plan steps must be an array.")
  }
  if raw_steps.length() > 8 {
    return Err("A deployment plan may contain at most 8 steps.")
  }
  if action != "DEPLOY" {
    if !raw_steps.is_empty() {
      return Err("LEARN and IGNORE plans cannot contain executable steps.")
    }
    return Ok({ root, action, steps: [], review_steps: [], reason, evidence, })
  }
  if raw_steps.is_empty() {
    return Err("A DEPLOY plan must contain at least one step.")
  }
  let steps : Array[DeploymentStep] = []
  let review_steps : Array[Json] = []
  let mut previous_rank = -1
  let mut start_count = 0
  for index, raw in raw_steps {
    guard raw is Object(step) else {
      return Err("Every deployment step must be an object.")
    }
    if ["cmd", "command", "shell", "script"].any(name => {
        step.get(name) is Some(_)
      }) {
      return Err(
        "Raw command or shell fields are forbidden in a deployment step.",
      )
    }
    let phase = match ai_plan_text(step, "phase", 32) {
      Ok(value) => value.to_lower()
      Err(error) => return Err(error)
    }
    guard ai_plan_phase_rank(phase) is Some(rank) else {
      return Err("Deployment phase is not allowlisted.")
    }
    if rank < previous_rank {
      return Err("Deployment phases must be in execution order.")
    }
    previous_rank = rank
    if phase == "start" {
      start_count += 1
      if index != raw_steps.length() - 1 {
        return Err("The start step must be last.")
      }
    }
    let program = match ai_plan_text(step, "program", 160) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if !ai_plan_safe_program(program) {
      return Err("Deployment program is not allowlisted.")
    }
    let args = match step.get("args") {
      Some(value) =>
        match parse_ai_plan_arguments(value) {
          Ok(args) => args
          Err(error) => return Err(error)
        }
      None => return Err("Every deployment step must contain an argv array.")
    }
    if !ai_plan_safe_operation(program, args) {
      return Err("Deployment operation is not allowlisted for this program.")
    }
    if !documented_ai_plan_command(readme, program, args) {
      return Err(
        "Every deployment argv sequence must appear verbatim in the README.",
      )
    }
    let workdir = match ai_plan_text(step, "workdir", 32) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if workdir != "." {
      return Err("Deployment workdir must be the repository root (.).")
    }
    let purpose = match ai_plan_text(step, "purpose", 300) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    steps.push({ phase, program, args, })
    review_steps.push({
      "phase": phase,
      "program": program,
      "args": args,
      "workdir": workdir,
      "purpose": purpose,
    })
  }
  if start_count != 1 {
    return Err("A DEPLOY plan must contain exactly one final start step.")
  }
  Ok({ root, action, steps, review_steps, reason, evidence, })
}

///|
/// Return the canonical repository root bound to this reviewed proposal.
pub fn AiDeploymentProposal::deployment_root(
  self : AiDeploymentProposal,
) -> String {
  self.root
}

///|
/// Render exactly what must be reviewed before execution authorization.
pub fn AiDeploymentProposal::to_json(self : AiDeploymentProposal) -> Json {
  {
    "schema_version": 1,
    "source": "ai_readme_plan",
    "action": self.action,
    "root": self.root,
    "reason": self.reason,
    "evidence": self.evidence,
    "steps": self.review_steps,
    "review_required": self.action == "DEPLOY",
    "executed": false,
    "warning": "Repository commands execute untrusted project code on the host; this proposal is validated but not sandboxed.",
  }
}

///|
/// Release typed argv steps only after explicit execution consent.
pub fn AiDeploymentProposal::authorize(
  self : AiDeploymentProposal,
  allow_execute : Bool,
) -> Result[Array[DeploymentStep], String] {
  if self.action != "DEPLOY" {
    return Err("Only a DEPLOY proposal can be authorized.")
  }
  if !allow_execute {
    return Err("Deployment was not authorized after review.")
  }
  Ok(self.steps.copy())
}
