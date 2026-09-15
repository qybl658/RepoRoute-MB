///|
test "Python versions are reduced to major.minor" {
  assert_eq(
    @runtime.python_version_from_output("Python 3.12.7\r\n"),
    Some("3.12"),
  )
  assert_eq(@runtime.python_version_from_output("cpython-3.11.9"), Some("3.11"))
  assert_eq(@runtime.python_version_from_output("not a version"), None)
}

///|
test "required Python mismatch waits before touching a venv" {
  assert_eq(
    @runtime.python_environment_action(
      Some("3.11"),
      Some("3.12"),
      true,
      Some("3.12"),
    ),
    "waiting_python_version",
  )
  assert_eq(
    @runtime.python_environment_action(
      Some("3.12"),
      Some("3.12"),
      true,
      Some("3.11"),
    ),
    "ready_rebuild",
  )
  assert_eq(
    @runtime.python_environment_action(
      Some("3.12"),
      Some("3.12"),
      true,
      Some("3.12"),
    ),
    "ready_reuse",
  )
  assert_eq(
    @runtime.python_environment_action(None, Some("3.12"), false, None),
    "ready_create",
  )
}

///|
test "python version file uses only a bounded major.minor request" {
  let base = @host.join(
    @env.get_env_var("TEMP").unwrap_or(@env.current_dir().unwrap_or(".")),
    "repowayfinder-python-version-test-" + @env.now().to_string(),
  )
  @fs.create_dir(base)
  @fs.write_string_to_file(@host.join(base, ".python-version"), "3.11.8\n")
  assert_eq(@runtime.read_python_version_file(base), Some("3.11"))
}

///|
async test "project without version pin keeps caller selected Python" {
  let base = @host.join(
    @env.get_env_var("TEMP").unwrap_or(@env.current_dir().unwrap_or(".")),
    "repowayfinder-python-select-test-" + @env.now().to_string(),
  )
  @fs.create_dir(base)
  assert_eq(
    @runtime.select_project_python(base, "already-selected-python"),
    "already-selected-python",
  )
}

///|
async test "venv rebuild archives canonical directory and writes rollback" {
  let base = @host.join(
    @env.get_env_var("TEMP").unwrap_or(@env.current_dir().unwrap_or(".")),
    "repowayfinder-python-venv-test-" + @env.now().to_string(),
  )
  let report = @host.join(base, "report")
  let venv = @host.join(base, ".repowayfinder-venv")
  for path in [base, report, venv] {
    @fs.create_dir(path)
  }
  @fs.write_string_to_file(@host.join(venv, "keep.txt"), "preserve me")
  let (backup, rollback) = @runtime.archive_project_python_venv(base, report)
  assert_false(@fs.path_exists(venv))
  assert_true(@fs.path_exists(backup))
  assert_eq(
    @fs.read_file_to_string(@host.join(backup, "keep.txt")),
    "preserve me",
  )
  assert_true(@fs.path_exists(rollback))
  let rollback_source = @fs.read_file_to_string(rollback)
  assert_true(rollback_source.contains("Move-Item -LiteralPath $backup"[:]))
  assert_false(rollback_source.contains("Remove-Item"[:]))
}
