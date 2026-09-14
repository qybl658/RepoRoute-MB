///|
test "Node plan installs lockfile dependencies and builds before starting" {
  let files = [
    @repowayfinder_mbt.source_file(
      "package.json", "{\"scripts\":{\"start\":\"node app.js\",\"build\":\"node build.js\"}}",
    ),
    @repowayfinder_mbt.source_file("package-lock.json", "{}"),
  ]
  let plan = @repowayfinder_mbt.plan_deployment(
    @repowayfinder_mbt.scan("demo", files),
    files,
    None,
    true,
  ).unwrap()
  assert_eq(plan.steps[2].args[0], "ci")
  assert_eq(plan.steps[3].phase, "build")
  assert_eq(plan.steps[4].args, ["run", "start"])
}

///|
test "Multiple entries need a choice and invalid indices never execute" {
  let files = [
    @repowayfinder_mbt.source_file(
      "package.json", "{\"scripts\":{\"start\":\"node a\",\"dev\":\"node b\"}}",
    ),
  ]
  let contract = @repowayfinder_mbt.scan(".", files)
  assert_true(
    @repowayfinder_mbt.plan_deployment(contract, files, None, true) is Err(_),
  )
  assert_true(
    @repowayfinder_mbt.plan_deployment(contract, files, Some(-1), true)
    is Err(_),
  )
  assert_true(
    @repowayfinder_mbt.plan_deployment(contract, files, Some(2), true) is Err(_),
  )
}

///|
test "Python uses project local environment and rejects path entries" {
  let files = [
    @repowayfinder_mbt.source_file(
      "pyproject.toml", "[project.scripts]\nhello = 'demo:main'",
    ),
  ]
  let plan = @repowayfinder_mbt.plan_deployment(
    @repowayfinder_mbt.scan(".", files),
    files,
    None,
    true,
  ).unwrap()
  assert_eq(plan.steps[1].args, ["-m", "venv", ".repowayfinder-venv"])
  assert_eq(plan.steps[3].program, ".repowayfinder-venv/Scripts/hello.exe")
  assert_false(@repowayfinder_mbt.safe_entry_name("../bad"))
  assert_false(@repowayfinder_mbt.safe_entry_name("x & whoami"))
  assert_false(@repowayfinder_mbt.safe_entry_name("-bad"))
}
