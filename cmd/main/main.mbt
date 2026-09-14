///|
fn join(root : String, relative : String) -> String {
  if root.has_suffix("/") || root.has_suffix("\\") {
    root + relative
  } else {
    root + "/" + relative
  }
}

///|
fn collect(root : String) -> Array[@lib.SourceFile] {
  let files : Array[@lib.SourceFile] = []
  let names = [
    "package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock",
    "bun.lockb", "pyproject.toml", "Cargo.toml", "moon.mod", "cmd/main/moon.pkg",
    "compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml", "Dockerfile",
  ]
  for name in names {
    let path = join(root, name)
    if @fs.path_exists(path) && (@fs.is_file(path) catch { _ => false }) {
      let content = @fs.read_file_to_string(path) catch { _ => "" }
      files.push(@lib.source_file(name, content))
    }
  }
  files
}

///|
fn print_help() -> Unit {
  println(
    (
      #|RepoWayfinder MB - evidence-backed repository launch discovery
      #|
      #|Usage:
      #|  moon run cmd/main -- [PATH] [--format json|markdown]
      #|
      #|The scanner reads supported manifests but never executes project commands.
    ),
  )
}

///|
fn main {
  let args = @env.args()
  if args.any(arg => arg == "--help" || arg == "-h") {
    print_help()
    return
  }
  let root = if args.length() > 1 && !args[1].has_prefix("--") {
    args[1]
  } else {
    "."
  }
  let format = if args.length() > 3 && args[2] == "--format" {
    args[3]
  } else if args.length() > 2 && args[1] == "--format" {
    args[2]
  } else {
    "json"
  }
  let contract = @lib.scan(root, collect(root))
  if format == "markdown" {
    println(@lib.render_markdown(contract))
  } else {
    println(@lib.render_json(contract))
  }
}
