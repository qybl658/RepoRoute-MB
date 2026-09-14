///|
test "validates endpoint and model settings" {
  assert_eq(
    normalize_base_url("https://api.deepseek.com/"),
    Some("https://api.deepseek.com"),
  )
  assert_eq(normalize_base_url("http://api.example.com/v1"), None)
  assert_eq(normalize_base_url("https://user:secret@example.com/v1"), None)
  assert_true(valid_model("deepseek/deepseek-chat"))
  assert_false(valid_model("model --unsafe"))
}

///|
test "configuration parser accepts Windows UTF-8 BOM" {
  assert_true(parse_config_text("\u{FEFF}{\"model\":\"test\"}") is Object(_))
  assert_true(parse_config_text("not json") is Null)
}

///|
test "extracts only the chat message" {
  let sample = @json.parse(
    "{\"choices\":[{\"message\":{\"content\":\"{\\\"candidate_index\\\":1}\"}}]}",
  )
  assert_eq(response_content(sample), Some("{\"candidate_index\":1}"))
  assert_eq(response_content({ "choices": [] }), None)
}

///|
test "redacts secrets and echoed authorization headers" {
  let secret = "sk-test-123456"
  let value = redact_with_secret(
    "request failed\nAuthorization: Bearer " + secret + "\napi_key=" + secret,
    secret,
  )
  assert_false(value.contains(secret[:]))
  assert_false(value.to_lower().contains("authorization"))
  assert_false(value.to_lower().contains("api_key"))
}

///|
test "strips JSON markdown fences" {
  assert_eq(strip_fence("```json\n{\"ok\":true}\n```"), "{\"ok\":true}")
  assert_eq(strip_fence("plain"), "plain")
}

///|
test "normalizes advisory output and discards executable fields" {
  let raw : Json = {
    "summary": "A small CLI",
    "evidence": ["package.json has a bin entry"],
    "risks": ["Needs configuration"],
    "recommendation": "Use candidate 1",
    "candidate_index": 1,
    "cmd": "untrusted command",
    "steps": [{ "shell": "untrusted" }],
  }
  guard normalize_answer(raw) is Some(answer) else {
    fail("expected normalized answer")
  }
  guard answer is Object(value) else { fail("expected normalized object") }
  assert_eq(value.get("cmd"), None)
  assert_eq(value.get("steps"), None)
  assert_eq(selected_index(answer, 2), Some(1))
  assert_eq(selected_index(answer, 1), None)
  assert_eq(selected_index({ "candidate_index": 0.5 }, 2), None)
}

///|
test "settings never expose an environment credential" {
  let name = "REPOWAYFINDER_AI_API_KEY"
  let previous = @env.get_env_var(name)
  defer (match previous {
    Some(value) => @env.set_env_var(name, value)
    None => @env.unset_env_var(name)
  })
  let secret = "sk-unit-test-secret"
  @env.set_env_var(name, secret)
  let visible = get_settings().stringify()
  assert_false(visible.contains(secret[:]))
  assert_true(visible.contains(name[:]))
}

///|
async test "DPAPI helper roundtrips only synthetic non-secret data" {
  if !@host.windows() {
    return
  }
  guard @host.resolve("powershell") is Some(powershell) else { return }
  let temp = @fs.tmpdir(prefix="repowayfinder-advisor-dpapi-")
  defer (@fs.rmdir(temp[:], recursive=true) catch { _ => () })
  let path = @host.join(temp, "test.json")
  let dummy = "synthetic-unit-test-not-a-secret"
  let script = "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new(); Import-Module Microsoft.PowerShell.Security; $secure=ConvertTo-SecureString " +
    ps_quote(dummy) +
    " -AsPlainText -Force; [ordered]@{api_key_dpapi=(ConvertFrom-SecureString $secure)} | ConvertTo-Json | Set-Content -LiteralPath " +
    ps_quote(path) +
    " -Encoding UTF8"
  let written = @host.run(
    powershell,
    [
      "-NoProfile",
      "-NonInteractive",
      "-EncodedCommand",
      encoded_powershell(script),
    ],
    temp,
    20000,
  )
  if written.code != 0 {
    abort("synthetic DPAPI setup failed: " + written.output)
  }
  assert_eq(decrypt_dpapi_file(powershell, path), dummy)
}
