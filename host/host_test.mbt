///|
test "sensitive environment values are not passed to project processes" {
  assert_true(@host.sensitive_name("OPENROUTER_API_KEY"))
  assert_true(@host.sensitive_name("GITHUB_TOKEN"))
  assert_false(@host.sensitive_name("PATH"))
  for name, _ in @host.safe_env() {
    assert_false(@host.sensitive_name(name))
  }
}

///|
test "Windows UTF16 status text is readable" {
  let encoded = @utf16.encode("WSL 需要更新"[:], endianness=Little)
  assert_eq(@host.decode_output(encoded), "WSL 需要更新")
}

///|
async test "timeout is not command success" {
  let program = if @host.windows() { "ping" } else { "sleep" }
  let args = if @host.windows() { ["-n", "10", "127.0.0.1"] } else { ["10"] }
  let result = @host.run(program, args, ".", 100)
  assert_true(result.timed_out)
  assert_eq(result.code, 124)
}

///|
async test "native process preserves argv and captures output" {
  let program = if @host.windows() { "cmd" } else { "printf" }
  let args = if @host.windows() {
    ["/d", "/c", "echo", "host-process-ok"]
  } else {
    ["host-process-ok"]
  }
  let result = @host.run(program, args, ".", 5000)
  assert_true(result.code == 0, msg=result.output)
  assert_true(result.output.contains("host-process-ok"))
}
