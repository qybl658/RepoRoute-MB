///|
test "detect only selected default Bullseye recipe with live sources" {
  let recipe =
    #|FROM python:3.11-slim-bullseye
    #|RUN echo "deb http://deb.debian.org/debian bullseye main" > /etc/apt/sources.list && \
    #|    echo "deb http://security.debian.org/debian-security bullseye-security main" >> /etc/apt/sources.list
  assert_true(@runtime.detect_eol_debian_dockerfile(recipe, true) is Some(_))
  assert_eq(@runtime.detect_eol_debian_dockerfile(recipe, false), None)
  assert_eq(
    @runtime.detect_eol_debian_dockerfile(
      "FROM python:3.11-slim-bullseye\nRUN echo no-live-suite", true,
    ),
    None,
  )
  assert_eq(
    @runtime.detect_eol_debian_dockerfile(
      "FROM python:3.11-slim-bookworm\nRUN echo bullseye-security", true,
    ),
    None,
  )
  assert_eq(
    @runtime.detect_eol_debian_dockerfile(
      "FROM python:3.11-slim-bullseye@sha256:deadbeef\nRUN echo bullseye-security",
      true,
    ),
    None,
  )
  assert_eq(
    @runtime.detect_eol_debian_dockerfile(
      "FROM python:3.11-slim-bullseye\n# bullseye-security is historical", true,
    ),
    None,
  )
}

///|
test "repair is report-local and preserves source recipe" {
  let base = @host.join(
    @env.get_env_var("TEMP").unwrap_or(@env.current_dir().unwrap_or(".")),
    "repowayfinder-docker-repair-test-" + @env.now().to_string(),
  )
  let source_dir = @host.join(base, "source")
  let report_dir = @host.join(base, "report")
  for path in [base, source_dir, report_dir] {
    if !@fs.path_exists(path) {
      @fs.create_dir(path)
    }
  }
  let source = @host.join(source_dir, "Dockerfile")
  let original =
    #|FROM python:3.11-slim-bullseye
    #|RUN echo "deb http://security.debian.org/debian-security bullseye-security main"
    #|RUN echo keep-notbullseye-name
  @fs.write_string_to_file(source, original)
  let waiting = @runtime.prepare_eol_docker_repair(
    source, report_dir, true, false,
  )
  assert_eq(waiting.status, "confirmation_required")
  assert_false(@fs.path_exists(@host.join(report_dir, "repairs")))
  let result = @runtime.prepare_eol_docker_repair(
    source, report_dir, true, true,
  )
  assert_eq(result.status, "isolated_repair_created")
  assert_eq(@fs.read_file_to_string(source), original)
  let repaired = @fs.read_file_to_string(result.repair_path)
  assert_true(repaired.contains("python:3.11-slim-bookworm"[:]))
  assert_true(repaired.contains("bookworm-security"[:]))
  assert_true(repaired.contains("keep-notbullseye-name"[:]))
}
