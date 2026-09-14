///|
test "node lockfile and scripts produce evidence-backed candidates" {
  let contract = @reporoute_mbt.scan("fixture/node", [
    @reporoute_mbt.source_file(
      "package.json", "{\n  \"scripts\": {\n    \"start\": \"node server.js\",\n    \"dev\": \"vite\"\n  }\n}",
    ),
    @reporoute_mbt.source_file("pnpm-lock.yaml", "lockfileVersion: '9.0'"),
  ])
  assert_eq(contract.candidates.length(), 2)
  assert_eq(contract.candidates[0].command, "pnpm start")
  assert_eq(contract.candidates[0].evidence.line, 3)
  assert_eq(contract.findings[0].code, "multiple-entrypoints")
}

///|
test "python project scripts are parsed without executing code" {
  let contract = @reporoute_mbt.scan("fixture/python", [
    @reporoute_mbt.source_file(
      "pyproject.toml", "[project]\nname = \"demo\"\n\n[project.scripts]\ndemo = \"demo.cli:main\"\n",
    ),
  ])
  assert_eq(contract.candidates.length(), 1)
  assert_eq(contract.candidates[0].command, "demo")
  assert_eq(contract.candidates[0].evidence.line, 5)
}

///|
test "invalid package json is an honest error" {
  let contract = @reporoute_mbt.scan("fixture/broken", [
    @reporoute_mbt.source_file("package.json", "{ nope"),
  ])
  assert_eq(contract.candidates.length(), 0)
  assert_eq(contract.findings[0].code, "invalid-package-json")
  assert_eq(contract.findings[1].code, "no-explicit-entrypoint")
}

///|
test "multiple ecosystems stay explicit instead of being silently ranked" {
  let contract = @reporoute_mbt.scan("fixture/mixed", [
    @reporoute_mbt.source_file("Cargo.toml", "[package]\nname = \"demo\"\n"),
    @reporoute_mbt.source_file("Dockerfile", "FROM scratch\nCMD [\"/demo\"]\n"),
  ])
  assert_eq(contract.candidates.length(), 2)
  assert_eq(contract.findings[0].code, "multiple-entrypoints")
}

///|
test "markdown includes command and exact evidence location" {
  let contract = @reporoute_mbt.scan("fixture/moonbit", [
    @reporoute_mbt.source_file("moon.mod", "name = \"demo/app\"\n"),
    @reporoute_mbt.source_file(
      "cmd/main/moon.pkg", "pkgtype(kind: \"executable\")\n",
    ),
  ])
  let markdown = @reporoute_mbt.render_markdown(contract)
  assert_true(markdown.contains("moon run cmd/main"))
  assert_true(markdown.contains("moon.mod:1"))
}

///|
test "Windows and explicitly relative paths are normalized" {
  let contract = @reporoute_mbt.scan("fixture/windows", [
    @reporoute_mbt.source_file(
      ".\\package.json", "{\"scripts\": {\"start\": \"node index.js\"}}",
    ),
    @reporoute_mbt.source_file(".\\pnpm-lock.yaml", "lockfileVersion: '9.0'"),
  ])
  assert_eq(contract.candidates.length(), 1)
  assert_eq(contract.candidates[0].command, "pnpm start")
  assert_eq(contract.candidates[0].evidence.file, "package.json")
}

///|
test "node evidence points inside scripts with CRLF input" {
  let contract = @reporoute_mbt.scan("fixture/evidence", [
    @reporoute_mbt.source_file(
      "package.json", "{\r\n  \"start\": false,\r\n  \"scripts\": {\r\n    \"start\": \"node server.js\"\r\n  }\r\n}",
    ),
  ])
  assert_eq(contract.candidates.length(), 1)
  assert_eq(contract.candidates[0].evidence.line, 4)
  assert_eq(
    contract.candidates[0].evidence.excerpt,
    "\"start\": \"node server.js\"",
  )
}

///|
test "conflicting Node lockfiles are reported with stable precedence" {
  let contract = @reporoute_mbt.scan("fixture/lock-conflict", [
    @reporoute_mbt.source_file(
      "package.json", "{\"scripts\": {\"start\": \"node index.js\"}}",
    ),
    @reporoute_mbt.source_file("package-lock.json", "{}"),
    @reporoute_mbt.source_file("yarn.lock", ""),
  ])
  assert_eq(contract.candidates[0].command, "yarn start")
  assert_eq(contract.findings[0].code, "multiple-node-lockfiles")
}
