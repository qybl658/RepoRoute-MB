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

///|
test "Python nested demo installs its declared package before running" {
  let files = [
    @repowayfinder_mbt.source_file(
      "examples/demo.py", "if __name__ == '__main__': print('demo')",
    ),
    @repowayfinder_mbt.source_file(
      "setup.py", "from setuptools import setup; setup(name='demo')",
    ),
  ]
  let plan = @repowayfinder_mbt.plan_deployment(
    @repowayfinder_mbt.scan(".", files),
    files,
    None,
    true,
  ).unwrap()
  assert_eq(plan.steps[2].args, ["-m", "pip", "install", "."])
  assert_eq(plan.steps[3].args, ["examples/demo.py"])
  assert_false(@repowayfinder_mbt.safe_relative_entry("../outside.py"))
  assert_false(@repowayfinder_mbt.safe_relative_entry("/outside.py"))
  assert_false(@repowayfinder_mbt.safe_relative_entry("examples/../outside.py"))
}

///|
test "Docker publishes only valid explicitly exposed TCP ports" {
  assert_eq(
    @repowayfinder_mbt.docker_exposed_ports(
      "EXPOSE 8080 8080/tcp 53/udp $PORT 99999\n# EXPOSE 7777\nEXPOSE 3000 # 4000",
    ),
    ["8080", "3000"],
  )
  let files = [
    @repowayfinder_mbt.source_file(
      "Dockerfile", "FROM node:22-alpine\nEXPOSE 8080\nCMD [\"node\",\"server.js\"]",
    ),
  ]
  let plan = @repowayfinder_mbt.plan_deployment(
    @repowayfinder_mbt.scan(".", files),
    files,
    None,
    true,
  ).unwrap()
  assert_eq(plan.steps[2].args, [
    "run", "--rm", "--publish", "127.0.0.1:8080:8080", "repowayfinder-mb-app",
  ])
}
