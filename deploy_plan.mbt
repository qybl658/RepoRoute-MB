///|
pub(all) struct DeploymentStep {
  phase : String
  program : String
  args : Array[String]
} derive(Eq, Debug, ToJson)

///|
pub(all) struct DeploymentPlan {
  root : String
  candidate_index : Int
  candidate : Candidate
  steps : Array[DeploymentStep]
  warnings : Array[String]
} derive(Eq, Debug)

///|
pub fn DeploymentPlan::to_json(self : DeploymentPlan) -> Json {
  {
    "schema_version": 1,
    "root": self.root,
    "candidate_index": self.candidate_index,
    "candidate": candidate_to_json(self.candidate),
    "steps": self.steps,
    "warnings": self.warnings,
  }
}

///|
pub fn safe_entry_name(name : String) -> Bool {
  !name.is_empty() &&
  !name.has_prefix("-") &&
  name
  .iter()
  .all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '_' ||
    c == '-' ||
    c == '.'
  }) &&
  name != "." &&
  name != ".."
}

///|
pub fn safe_python_command(command : String) -> Array[String]? {
  if command
    .iter()
    .any(c => {
      c == ';' ||
      c == '&' ||
      c == '|' ||
      c == '<' ||
      c == '>' ||
      c == '`' ||
      c == '$' ||
      c == '%' ||
      c == '\n' ||
      c == '\r' ||
      c == '"' ||
      c == '\''
    }) {
    return None
  }
  let tokens = command
    .split(" ")
    .filter(s => !s.is_empty())
    .map(s => s.to_owned())
    .collect()
  if tokens.length() < 2 {
    return None
  }
  if tokens[0] == "uvicorn" ||
    tokens[0] == "streamlit" ||
    tokens[0] == "gunicorn" {
    let result = ["-m"]
    result.append(tokens)
    return Some(result)
  }
  if tokens[0] != "python" && tokens[0] != "python3" {
    return None
  }
  let args = tokens[1:].to_owned()
  if args[0] == "-m" {
    if args.length() < 2 ||
      !["uvicorn", "streamlit", "gunicorn", "flask"].contains(args[1]) {
      return None
    }
  } else if !safe_entry_name(args[0]) || !args[0].has_suffix(".py") {
    return None
  }
  Some(args)
}

///|
pub fn plan_deployment(
  contract : RunContract,
  files : Array[SourceFile],
  index : Int?,
  windows : Bool,
) -> Result[DeploymentPlan, String] {
  let chosen = match index {
    Some(i) => i
    None => {
      if contract.candidates.length() != 1 {
        return Err(
          "Choose an entrypoint explicitly using --candidate N (one-based).",
        )
      }
      0
    }
  }
  if chosen < 0 || chosen >= contract.candidates.length() {
    return Err("Candidate index is out of range.")
  }
  let candidate = contract.candidates[chosen]
  let steps : Array[DeploymentStep] = []
  let warnings = [
    "Dependency installation and launch execute repository code on this host. This is not a sandbox.",
    "A discovered command is a candidate, not proof of a working deployment.",
  ]
  match candidate.ecosystem {
    "node" => {
      let (manager, _) = package_manager(files, [])
      let script = candidate.command.split(" ").last().unwrap().to_owned()
      if !["start", "dev", "serve", "preview", "demo", "example", "test"].contains(
          script,
        ) {
        return Err("Unsupported Node script.")
      }
      steps.push({ phase: "preflight", program: "node", args: ["--version"], })
      steps.push({ phase: "preflight", program: manager, args: ["--version"], })
      let install = if manager == "npm" &&
        find_file(files, "package-lock.json") is Some(_) {
        ["ci", "--no-audit", "--no-fund"]
      } else if manager == "npm" {
        ["install", "--no-audit", "--no-fund"]
      } else {
        ["install"]
      }
      steps.push({ phase: "install", program: manager, args: install, })
      if script == "start" || script == "preview" {
        if find_file(files, "package.json") is Some(file) {
          let parsed = @json.parse(file.content) catch { _ => Json::null() }
          if parsed is Object(obj) &&
            obj.get("scripts") is Some(Object(scripts)) &&
            scripts.get("build") is Some(String(build)) &&
            !build.is_empty() {
            steps.push({
              phase: "build",
              program: manager,
              args: ["run", "build"],
            })
          }
        }
      }
      steps.push({ phase: "start", program: manager, args: ["run", script], })
    }
    "python" | "python-file" | "python-command" => {
      if candidate.ecosystem != "python-command" &&
        !safe_entry_name(candidate.command) {
        return Err(
          "Python entrypoint must be a simple executable name, without paths or shell syntax.",
        )
      }
      let python = if windows { "python" } else { "python3" }
      let bin = if windows {
        ".repowayfinder-venv/Scripts/"
      } else {
        ".repowayfinder-venv/bin/"
      }
      let local_python = bin + (if windows { "python.exe" } else { "python" })
      steps.push({ phase: "preflight", program: python, args: ["--version"], })
      steps.push({
        phase: "prepare",
        program: python,
        args: ["-m", "venv", ".repowayfinder-venv"],
      })
      if find_file(files, "requirements.txt") is Some(_) {
        steps.push({
          phase: "install",
          program: local_python,
          args: ["-m", "pip", "install", "-r", "requirements.txt"],
        })
      }
      if candidate.ecosystem == "python" {
        steps.push({
          phase: "install",
          program: local_python,
          args: ["-m", "pip", "install", "."],
        })
        steps.push({
          phase: "start",
          program: bin + candidate.command + (if windows { ".exe" } else { "" }),
          args: [],
        })
      } else {
        let args = if candidate.ecosystem == "python-command" {
          match safe_python_command(candidate.command) {
            Some(args) => args
            None => return Err("Unsafe or unsupported Python Procfile command.")
          }
        } else {
          [candidate.command]
        }
        steps.push({ phase: "start", program: local_python, args, })
      }
    }
    "rust" => {
      steps.push({ phase: "preflight", program: "cargo", args: ["--version"], })
      steps.push({ phase: "install", program: "cargo", args: ["fetch"], })
      steps.push({ phase: "build", program: "cargo", args: ["build"], })
      steps.push({ phase: "start", program: "cargo", args: ["run"], })
    }
    "moonbit" => {
      steps.push({ phase: "preflight", program: "moon", args: ["version"], })
      steps.push({ phase: "install", program: "moon", args: ["update"], })
      steps.push({ phase: "build", program: "moon", args: ["build"], })
      steps.push({ phase: "start", program: "moon", args: ["run", "cmd/main"], })
    }
    "docker" => {
      if candidate.confidence < 80 {
        return Err(
          "Dockerfile has no explicit runtime command; choose or add one before deployment.",
        )
      }
      steps.push({ phase: "preflight", program: "docker", args: ["info"], })
      steps.push({
        phase: "build",
        program: "docker",
        args: ["build", "-t", "repowayfinder-mb-app", "."],
      })
      steps.push({
        phase: "start",
        program: "docker",
        args: ["run", "--rm", "repowayfinder-mb-app"],
      })
      warnings.push(
        "No port mapping is inferred. HTTP acceptance requires an explicit reachable health URL.",
      )
    }
    "docker-compose" => {
      steps.push({ phase: "preflight", program: "docker", args: ["info"], })
      steps.push({
        phase: "preflight",
        program: "docker",
        args: ["compose", "version"],
      })
      steps.push({
        phase: "validate-compose",
        program: "docker",
        args: [
          "compose",
          "-f",
          candidate.evidence.file,
          "config",
          "--format",
          "json",
        ],
      })
      steps.push({
        phase: "start",
        program: "docker",
        args: [
          "compose",
          "-f",
          candidate.evidence.file,
          "up",
          "--build",
          "--abort-on-container-failure",
        ],
      })
    }
    _ => return Err("Unsupported deployment ecosystem.")
  }
  Ok({
    root: contract.root,
    candidate_index: chosen,
    candidate,
    steps,
    warnings,
  })
}
