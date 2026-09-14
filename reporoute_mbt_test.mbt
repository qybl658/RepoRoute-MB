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

///|
test "Compose variants use stable precedence and services evidence" {
  let contract = @reporoute_mbt.scan("fixture/compose", [
    @reporoute_mbt.source_file(
      "compose.yml", "name: demo\n\nservices:\n  web:\n    image: nginx\n",
    ),
    @reporoute_mbt.source_file(
      "docker-compose.yaml", "services:\n  worker:\n    image: busybox\n",
    ),
  ])
  assert_eq(contract.candidates.length(), 1)
  assert_eq(contract.candidates[0].ecosystem, "docker-compose")
  assert_eq(contract.candidates[0].evidence.file, "compose.yml")
  assert_eq(contract.candidates[0].evidence.line, 3)
  assert_eq(contract.findings[0].code, "multiple-compose-files")
}

///|
test "Dockerfile comments do not masquerade as runtime instructions" {
  let contract = @reporoute_mbt.scan("fixture/docker", [
    @reporoute_mbt.source_file(
      "Dockerfile", "FROM alpine\n# CMD is intentionally omitted\nRUN echo ready\n",
    ),
  ])
  assert_eq(contract.candidates[0].confidence, 70)
  assert_eq(contract.candidates[0].evidence.line, 1)
  assert_eq(contract.findings[0].code, "dockerfile-no-runtime-command")
}

///|
test "Docker runtime evidence follows the first real instruction" {
  let contract = @reporoute_mbt.scan("fixture/docker-entrypoint", [
    @reporoute_mbt.source_file(
      "Dockerfile", "FROM alpine\nRUN echo CMD\nENTRYPOINT [\"/app\"]\nCMD [\"serve\"]\n",
    ),
  ])
  assert_eq(contract.candidates[0].confidence, 88)
  assert_eq(contract.candidates[0].evidence.line, 3)
  assert_true(contract.candidates[0].reason.contains("ENTRYPOINT"))
}

///|
test "PEP 621 console and GUI scripts both produce clean commands" {
  let contract = @reporoute_mbt.scan("fixture/python-scripts", [
    @reporoute_mbt.source_file(
      "pyproject.toml", "[project.scripts]\n'route-cli' = 'demo.cli:main'\n\n[project]\nname = \"demo\"\n\n[project.gui-scripts]\n\"route-ui\" = \"demo.ui:main\"\n",
    ),
  ])
  assert_eq(contract.candidates.length(), 2)
  assert_eq(contract.candidates[0].command, "route-cli")
  assert_eq(contract.candidates[1].command, "route-ui")
  assert_true(contract.candidates[1].reason.contains("GUI"))
  assert_eq(contract.candidates[1].evidence.line, 8)
}

///|
test "Node preview is runnable while empty scripts stay findings" {
  let contract = @reporoute_mbt.scan("fixture/node-preview", [
    @reporoute_mbt.source_file(
      "package.json", "{\n  \"scripts\": {\n    \"start\": \"  \",\n    \"preview\": \"vite preview\"\n  }\n}",
    ),
  ])
  assert_eq(contract.candidates.length(), 1)
  assert_eq(contract.candidates[0].command, "npm run preview")
  assert_eq(contract.candidates[0].confidence, 75)
  assert_eq(contract.findings[0].code, "empty-node-script")
}
