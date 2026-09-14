///|
fn find_file(files : Array[SourceFile], path : String) -> SourceFile? {
  for file in files {
    if file.path == path {
      return Some(file)
    }
  }
  None
}

///|
fn line_number(content : String, needle : StringView) -> Int {
  guard content.find(needle) is Some(end) else { return 1 }
  let mut line = 1
  for index = 0; index < end; index = index + 1 {
    if content.get_char(index).unwrap() == '\n' {
      line = line + 1
    }
  }
  line
}

///|
fn line_excerpt(content : String, line_number : Int) -> String {
  let mut current = 1
  for line in content.split("\n") {
    if current == line_number {
      return line.trim(chars=" \t\r").to_owned()
    }
    current = current + 1
  }
  ""
}

///|
fn evidence(file : SourceFile, needle : StringView) -> Evidence {
  let line = line_number(file.content, needle)
  { file: file.path, line, excerpt: line_excerpt(file.content, line), }
}

///|
fn package_manager(files : Array[SourceFile]) -> (String, String) {
  if find_file(files, "pnpm-lock.yaml") is Some(_) {
    ("pnpm", "pnpm")
  } else if find_file(files, "yarn.lock") is Some(_) {
    ("yarn", "yarn")
  } else if find_file(files, "bun.lock") is Some(_) ||
    find_file(files, "bun.lockb") is Some(_) {
    ("bun", "bun")
  } else {
    ("npm", "Node.js and npm")
  }
}

///|
fn add_node_candidates(
  files : Array[SourceFile],
  candidates : Array[Candidate],
  findings : Array[Finding],
) -> Unit {
  guard find_file(files, "package.json") is Some(file) else { return }
  let parsed = @json.parse(file.content) catch {
    _ => {
      findings.push({
        level: "error",
        code: "invalid-package-json",
        message: "package.json is not valid JSON; Node.js scripts were not inferred.",
        file: file.path,
      })
      return
    }
  }
  guard parsed is Object(root) else { return }
  guard root.get("scripts") is Some(Object(scripts)) else {
    findings.push({
      level: "warning",
      code: "missing-node-scripts",
      message: "package.json has no scripts object.",
      file: file.path,
    })
    return
  }
  let (manager, prerequisite) = package_manager(files)
  let names = ["start", "dev", "serve"]
  for name in names {
    if scripts.get(name) is Some(String(script)) {
      let command = if manager == "npm" {
        "npm run \{name}"
      } else {
        "\{manager} \{name}"
      }
      candidates.push({
        ecosystem: "node",
        command,
        workdir: ".",
        confidence: if name == "start" {
          95
        } else {
          85
        },
        prerequisites: [prerequisite],
        reason: "Explicit package.json script '\{name}' (\{script})",
        evidence: evidence(file, "\"\{name}\""),
      })
    }
  }
}

///|
fn add_manifest_candidate(
  files : Array[SourceFile],
  path : String,
  marker : StringView,
  ecosystem : String,
  command : String,
  prerequisite : String,
  reason : String,
  confidence : Int,
  candidates : Array[Candidate],
) -> Unit {
  guard find_file(files, path) is Some(file) else { return }
  guard file.content.contains(marker) else { return }
  candidates.push({
    ecosystem,
    command,
    workdir: ".",
    confidence,
    prerequisites: [prerequisite],
    reason,
    evidence: evidence(file, marker),
  })
}

///|
fn add_python_candidates(
  files : Array[SourceFile],
  candidates : Array[Candidate],
) -> Unit {
  guard find_file(files, "pyproject.toml") is Some(file) else { return }
  let mut in_scripts = false
  let mut line_number = 0
  for raw_line in file.content.split("\n") {
    line_number = line_number + 1
    let line = raw_line.trim(chars=" \t\r").to_owned()
    if line == "[project.scripts]" {
      in_scripts = true
      continue
    }
    if in_scripts && line.has_prefix("[") {
      break
    }
    if in_scripts &&
      !line.has_prefix("#") &&
      line.split_once("=") is Some((left, right)) {
      let name = left.trim(chars=" \t").to_owned()
      let target = right.trim(chars=" \t\"").to_owned()
      if !name.is_empty() && !target.is_empty() {
        candidates.push({
          ecosystem: "python",
          command: name,
          workdir: ".",
          confidence: 90,
          prerequisites: ["Python and an installed project environment"],
          reason: "Explicit PEP 621 console script targeting \{target}",
          evidence: { file: file.path, line: line_number, excerpt: line, },
        })
      }
    }
  }
}

///|
fn add_container_candidates(
  files : Array[SourceFile],
  candidates : Array[Candidate],
) -> Unit {
  let compose = match find_file(files, "compose.yaml") {
    Some(file) => Some(file)
    None => find_file(files, "docker-compose.yml")
  }
  if compose is Some(file) {
    candidates.push({
      ecosystem: "docker-compose",
      command: "docker compose up --build",
      workdir: ".",
      confidence: 90,
      prerequisites: ["Docker with Compose"],
      reason: "A conventional Compose manifest is present.",
      evidence: {
        file: file.path,
        line: 1,
        excerpt: line_excerpt(file.content, 1),
      },
    })
  }
  guard find_file(files, "Dockerfile") is Some(file) else { return }
  let marker : StringView = if file.content.contains("CMD") {
    "CMD"
  } else if file.content.contains("ENTRYPOINT") {
    "ENTRYPOINT"
  } else {
    "FROM"
  }
  candidates.push({
    ecosystem: "docker",
    command: "docker build -t reporoute-app . && docker run --rm reporoute-app",
    workdir: ".",
    confidence: if marker == "FROM" {
      70
    } else {
      88
    },
    prerequisites: ["Docker"],
    reason: if marker == "FROM" {
      "Dockerfile exists but has no explicit CMD or ENTRYPOINT."
    } else {
      "Dockerfile contains an explicit \{marker} instruction."
    },
    evidence: evidence(file, marker),
  })
}

///|
pub fn scan(root : String, files : Array[SourceFile]) -> RunContract {
  let candidates : Array[Candidate] = []
  let findings : Array[Finding] = []
  add_node_candidates(files, candidates, findings)
  add_python_candidates(files, candidates)
  add_manifest_candidate(
    files, "Cargo.toml", "[package]", "rust", "cargo run", "Rust and Cargo", "Cargo package manifest declares a runnable package.",
    85, candidates,
  )
  if find_file(files, "moon.mod") is Some(file) &&
    find_file(files, "cmd/main/moon.pkg") is Some(_) {
    candidates.push({
      ecosystem: "moonbit",
      command: "moon run cmd/main",
      workdir: ".",
      confidence: 95,
      prerequisites: ["MoonBit toolchain"],
      reason: "MoonBit module contains the conventional cmd/main package.",
      evidence: evidence(file, "name"),
    })
  }
  add_container_candidates(files, candidates)
  if candidates.is_empty() {
    findings.push({
      level: "warning",
      code: "no-explicit-entrypoint",
      message: "No supported explicit launch entrypoint was found.",
      file: ".",
    })
  } else if candidates.length() > 1 {
    findings.push({
      level: "info",
      code: "multiple-entrypoints",
      message: "Multiple explicit entrypoints were found; a caller should choose according to its goal and environment.",
      file: ".",
    })
  }
  { schema_version: 1, root, candidates, findings, }
}
