///|
test "README Python plans get local venv and mandatory preflight" {
  let raw : Json = {
    "action": "DEPLOY",
    "reason": "Documented script",
    "evidence": ["python demo.py"],
    "steps": [
      {
        "phase": "start",
        "program": "python",
        "args": ["demo.py"],
        "workdir": ".",
        "purpose": "run demo",
      },
    ],
  }
  let proposal = @lib.parse_ai_deployment_proposal(raw, ".", "python demo.py").unwrap()
  let plan = normalize_ai_plan(proposal, true)
  assert_eq(plan.steps[0].phase, "preflight")
  assert_eq(plan.steps[1].args, ["-m", "venv", ".repowayfinder-venv"])
  assert_true(plan.steps[2].program.has_prefix(".repowayfinder-venv/"))
  try normalize_ai_plan(proposal, false) catch {
    _ => ()
  } noraise {
    _ => fail("Unauthorized plan was accepted")
  }
}

///|
async test "validated AI plan executes and resumes without a second model call" {
  if !@host.windows() {
    return
  }
  let root = @host.join(
    report_base(),
    "ai-lifecycle-test-" + @env.now().to_string(),
  )
  ensure_dir(root)
  @fs.write_string_to_file(
    @host.join(root, "demo.py"),
    "print('offline-ai-plan-ok')\n",
  )
  @fs.write_string_to_file(@host.join(root, "README.md"), "python demo.py\n")
  let canonical = @afs.realpath(root[:])
  let raw : Json = {
    "action": "DEPLOY",
    "reason": "Documented script",
    "evidence": ["python demo.py"],
    "steps": [
      {
        "phase": "start",
        "program": "python",
        "args": ["demo.py"],
        "workdir": ".",
        "purpose": "run demo",
      },
    ],
  }
  let proposal = @lib.parse_ai_deployment_proposal(
    raw, canonical, "python demo.py",
  ).unwrap()
  let report = deploy_ai(proposal, true, false, "", false, true)
  guard report is Object(fields) &&
    fields.get("status") == Some(Json("SUCCEEDED")) &&
    fields.get("report_dir") is Some(String(directory)) else {
    fail("AI execution failed: " + report.stringify())
  }
  let resumed = resume_deployment(
    @host.join(directory, "deployment.json"),
    true,
    true,
    false,
    false,
  )
  guard resumed is Object(result) else { fail("Invalid resume result") }
  assert_eq(result.get("status"), Some(Json("SUCCEEDED")))
  @fs.write_string_to_file(
    @host.join(root, "README.md"),
    "The script is no longer documented.\n",
  )
  try
    resume_deployment(
      @host.join(directory, "deployment.json"),
      true,
      true,
      false,
      false,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("Changed README was accepted")
  }
}
