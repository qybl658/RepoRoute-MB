///|
pub(all) struct CommandResult {
  code : Int
  output : String
  timed_out : Bool
} derive(Eq, Debug, ToJson)

///|
pub fn windows() -> Bool {
  @env.get_env_var("OS") == Some("Windows_NT")
}

///|
pub fn join(root : String, leaf : String) -> String {
  root +
  (if root.has_suffix("/") || root.has_suffix("\\") { "" } else { "/" }) +
  leaf
}

///|
pub fn app_root() -> String {
  @env.get_env_var("REPOWAYFINDER_HOME").unwrap_or(
    @env.current_dir().unwrap_or("."),
  )
}

///|
pub fn tool_root() -> String {
  join(app_root(), ".repowayfinder-tools")
}

///|
pub fn windows_launcher(
  executable : String,
  args : Array[String],
  app : String,
  confirm : Bool,
) -> String {
  let quote = (s : String) => "'" + s.replace_all(old="'", new="''") + "'"
  let tokens = [executable]
  tokens.append(args)
  let script = "$ErrorActionPreference='Stop'; $env:REPOWAYFINDER_HOME=" +
    quote(app) +
    "; " +
    (if confirm {
      "if ((Read-Host 'Run this project and its dependency code on this computer? [y/N]') -notin @('y','Y')) { exit 20 }; "
    } else {
      ""
    }) +
    "& " +
    tokens.map(quote).join(" ") +
    "; exit $LASTEXITCODE"
  let encoded = @base64.encode(@utf16.encode(script[:], endianness=Little)[:])
  "@echo off\r\nsetlocal\r\n\"%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe\" -NoProfile -EncodedCommand " +
  encoded +
  "\r\nset \"result=%errorlevel%\"\r\nif not defined REPOWAYFINDER_NO_PAUSE pause\r\nexit /b %result%\r\n"
}

///|
pub fn sensitive_name(name : String) -> Bool {
  let name = name.to_upper()
  [
    "TOKEN", "SECRET", "PASSWORD", "CREDENTIAL", "API_KEY", "APIKEY", "PRIVATE_KEY",
    "AUTH", "COOKIE",
  ].any(part => name.contains(part[:]))
}

///|
pub fn safe_env() -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for key, value in @env.get_env_vars() {
    let upper = key.to_upper()
    if !sensitive_name(upper) &&
      !upper.has_prefix("CODEX") &&
      !upper.has_prefix("OPENAI") &&
      !upper.has_prefix("REPOWAYFINDER") &&
      !upper.has_prefix("REPOSCOUT") &&
      ![
        "PSMODULEPATH", "NODE_OPTIONS", "PYTHONSTARTUP", "PYTHONPATH", "BASH_ENV",
        "ENV", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT", "GIT_SSH_COMMAND",
      ].contains(upper) &&
      !upper.has_prefix("GIT_CONFIG_KEY_") &&
      !upper.has_prefix("GIT_CONFIG_VALUE_") &&
      !(upper.contains("PROXY") && value.contains("@")) {
      result[key] = value
    }
  }
  result["GIT_TERMINAL_PROMPT"] = "0"
  result["GIT_CONFIG_NOSYSTEM"] = "1"
  result["PYTHONIOENCODING"] = "utf-8"
  result["NO_COLOR"] = "1"
  let dirs : Array[String] = []
  for leaf in ["git/cmd", "git/usr/bin", "node", "python"] {
    let path = join(tool_root(), leaf)
    if @fs.path_exists(path) && (@fs.is_dir(path) catch { _ => false }) {
      dirs.push(path)
    }
  }
  for
    program in [
      "node", "python", "git", "moon", "docker", "pnpm", "yarn", "bun",
    ] {
    if resolve(program) is Some(exe) {
      let parts = exe
        .replace_all(old="\\", new="/")
        .split("/")
        .map(p => p.to_owned())
        .collect()
      let _ = parts.pop()
      let dir = parts.join("/")
      if !dirs.contains(dir) {
        dirs.push(dir)
      }
    }
  }
  if windows() && @env.get_env_var("SystemRoot") is Some(root) {
    dirs.push(join(root, "System32"))
  }
  let inherited = result.get("PATH").unwrap_or(result.get("Path").unwrap_or(""))
  result.remove("Path")
  result["PATH"] = dirs.join(if windows() { ";" } else { ":" }) +
    (if windows() { ";" } else { ":" }) +
    inherited
  let local_moon = join(tool_root(), "moon")
  if @fs.path_exists(join(local_moon, "bin/moon.exe")) {
    result["MOON_HOME"] = local_moon
  }
  result
}

///|
pub fn redact(text : String) -> String {
  let mut result = text
  for key, value in @env.get_env_vars() {
    if sensitive_name(key) && value.length() >= 6 {
      result = result.replace_all(old=value[:], new="[REDACTED]")
    }
  }
  result
}

///|
pub fn decode_output(bytes : Bytes) -> String {
  let mut zeros = 0
  for byte in bytes {
    if byte == 0 {
      zeros += 1
    }
  }
  if bytes.length() >= 4 &&
    (zeros > bytes.length() / 8 || (bytes[0] == 255 && bytes[1] == 254)) {
    @utf16.decode_lossy(bytes[:], endianness=Little)
  } else {
    @utf8.decode_lossy(bytes[:])
  }
}

///|
pub fn resolve(program : String) -> String? {
  if program.contains("/") || program.contains("\\") {
    return if @fs.path_exists(program) { Some(program) } else { None }
  }
  let dirs : Array[String] = [
    tool_root(),
    join(tool_root(), "moon/bin"),
    join(tool_root(), "node_modules/.bin"),
    join(tool_root(), "git/cmd"),
    join(tool_root(), "git/usr/bin"),
    join(tool_root(), "node"),
    join(tool_root(), "python"),
  ]
  if @env.get_env_var("MOON_HOME") is Some(home) {
    dirs.push(join(home, "bin"))
  }
  let path = @env.get_env_var("PATH").unwrap_or(
    @env.get_env_var("Path").unwrap_or(""),
  )
  for dir in path.split(if windows() { ";" } else { ":" }) {
    if !dir.is_empty() && dir != "." {
      dirs.push(dir.trim(chars="\"").to_owned())
    }
  }
  if windows() {
    if @env.get_env_var("SystemRoot") is Some(root) {
      dirs.push(join(root, "System32"))
      dirs.push(join(root, "System32/WindowsPowerShell/v1.0"))
    }
    if @env.get_env_var("ProgramFiles") is Some(root) {
      for leaf in ["nodejs", "Git/cmd", "Docker/Docker/resources/bin"] {
        dirs.push(join(root, leaf))
      }
    }
    if @env.get_env_var("LOCALAPPDATA") is Some(root) {
      for ver in ["Python314", "Python313", "Python312", "Python311"] {
        dirs.push(join(root, "Programs/Python/" + ver))
      }
    }
  }
  let home = @env.get_env_var("USERPROFILE").unwrap_or(
    @env.get_env_var("HOME").unwrap_or(""),
  )
  if !home.is_empty() {
    dirs.push(join(home, ".moon/bin"))
    dirs.push(join(home, ".cargo/bin"))
  }
  let names = if windows() &&
    !program.to_lower().has_suffix(".exe") &&
    !program.to_lower().has_suffix(".cmd") {
    [program + ".exe", program + ".cmd", program + ".bat"]
  } else {
    [program]
  }
  for dir in dirs {
    for name in names {
      let path = join(dir, name)
      if @fs.path_exists(path) && (@fs.is_file(path) catch { _ => false }) {
        return Some(path)
      }
    }
  }
  None
}

///|
pub fn command(
  program : String,
  args : Array[String],
  cwd : String,
) -> Result[(String, Array[String]), String] {
  let resolved = if program.contains("/") || program.contains("\\") {
    let path = if program.has_prefix("/") || program.contains(":") {
      program
    } else {
      join(cwd, program)
    }
    resolve(path)
  } else {
    resolve(program)
  }
  guard resolved is Some(exe) else {
    return Err("Missing executable: " + program)
  }
  let exe = if windows() { exe.replace_all(old="/", new="\\") } else { exe }
  if windows() &&
    (exe.to_lower().has_suffix(".cmd") || exe.to_lower().has_suffix(".bat")) {
    // A single quoted cmd payload: reject expansion/control syntax rather than guessing escaping.
    let tokens = [exe]
    tokens.append(args)
    if tokens.any(token => {
        token
        .iter()
        .any(c => {
          c == '"' ||
          c == '%' ||
          c == '!' ||
          c == '\r' ||
          c == '\n' ||
          c == '^' ||
          c == '&' ||
          c == '|' ||
          c == '<' ||
          c == '>'
        })
      }) {
      return Err(
        "Unsafe characters for a Windows batch wrapper; use an executable or a simpler path.",
      )
    }
    guard resolve("powershell") is Some(shell) else {
      return Err("Windows PowerShell not found.")
    }
    let script = "$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new(); & " +
      tokens.map(t => "'" + t.replace_all(old="'", new="''") + "'").join(" ") +
      "; exit $LASTEXITCODE"
    let encoded = @base64.encode(@utf16.encode(script[:], endianness=Little)[:])
    Ok((shell, ["-NoProfile", "-NonInteractive", "-EncodedCommand", encoded]))
  } else {
    Ok((exe, args))
  }
}

///|
async fn cancel_tree(pid : Int) -> Unit {
  if windows() {
    if resolve("taskkill") is Some(taskkill) {
      let _ = @process.collect_output(
        taskkill[:],
        ["/PID", pid.to_string(), "/T", "/F"],
        inherit_env=false,
        extra_env=safe_env(),
        no_console_window=true,
      ) catch {
        _ => (1, "", "")
      }
    }
  }
  (@process.hard_cancel().0)(pid)
}

///|
pub async fn run(
  program : String,
  args : Array[String],
  cwd : String,
  timeout_ms : Int,
  on_output? : (String) -> Unit = _ => (),
) -> CommandResult {
  let (exe, argv) = match command(program, args, cwd) {
    Ok(pair) => pair
    Err(message) => return { code: 127, output: message, timed_out: false, }
  }
  let mut output = ""
  let result = @async.with_timeout_opt(timeout_ms, () => {
    let (reader, writer) = @process.read_from_process()
    @async.with_task_group() <| group => {
      defer reader.close()
      let child = group.spawn(() => {
        @process.run(
          exe[:],
          argv[:],
          cwd=cwd[:],
          inherit_env=false,
          extra_env=safe_env(),
          stdout=writer,
          stderr=writer,
          no_console_window=true,
          cancel_handler=@process.CancellationHandler(cancel_tree),
        )
      })
      while reader.read_some(max_len=4096) is Some(bytes) {
        output = output + decode_output(bytes)
        if output.length() > 65536 {
          output = output[output.length() - 65536:].to_owned()
        }
        on_output(redact(output))
      }
      child.wait()
    }
  }) catch {
    error => return { code: 126, output: redact("\{error}"), timed_out: false, }
  }
  match result {
    Some(code) => { code, output: redact(output), timed_out: false, }
    None =>
      {
        code: 124,
        output: redact(
          output +
          "\nProcess timeout; cancellation requested for owned process.",
        ),
        timed_out: true,
      }
  }
}

///|
pub async fn prompt(message : String) -> Bool {
  println(message + " [y/N]")
  let answer = @stdio.stdin.read_until("\n") catch { _ => None }
  match answer {
    Some(value) => value.trim(chars=" \t\r\n").to_lower() == "y"
    None => false
  }
}
