///|
fn sample_ai_plan() -> Json {
  {
    "action": "DEPLOY",
    "reason": "README documents npm install and npm start.",
    "evidence": ["README.md: npm install, then npm start"],
    "steps": [
      {
        "phase": "install",
        "program": "npm",
        "args": ["install", "--no-audit", "--no-fund"],
        "workdir": ".",
        "purpose": "Install the documented Node dependencies.",
      },
      {
        "phase": "start",
        "program": "npm",
        "args": ["start"],
        "workdir": ".",
        "purpose": "Start the documented application.",
      },
    ],
  }
}

///|
test "AI plan becomes typed argv only after explicit authorization" {
  let proposal = match
    parse_ai_deployment_proposal(
      sample_ai_plan(),
      "D:/owned/repository",
      "Install with npm install --no-audit --no-fund, then run npm start.",
    ) {
    Ok(value) => value
    Err(error) => abort(error)
  }
  let review = proposal.to_json().stringify()
  assert_true(review.contains("review_required"))
  assert_true(review.contains("npm"))
  assert_true(proposal.authorize(false) is Err(_))
  guard proposal.authorize(true) is Ok(steps) else {
    abort("expected authorized typed steps")
  }
  assert_eq(steps.length(), 2)
  assert_eq(steps[1].program, "npm")
  assert_eq(steps[1].args, ["start"])
}

///|
test "AI plan rejects shell syntax, raw interpreters, and secret arguments" {
  let shell = sample_ai_plan()
  guard shell is Object(shell_object) else { abort("expected object") }
  shell_object["steps"] = [
    {
      "phase": "start",
      "program": "npm",
      "args": ["start", "&&", "whoami"],
      "workdir": ".",
      "purpose": "unsafe",
    },
  ]
  assert_true(
    parse_ai_deployment_proposal(shell, "D:/owned/repository", "npm start")
    is Err(_),
  )
  let interpreter : Json = {
    "action": "DEPLOY",
    "reason": "not accepted",
    "steps": [
      {
        "phase": "start",
        "program": "powershell",
        "args": ["-Command", "Write-Host ok"],
        "workdir": ".",
        "purpose": "raw shell",
      },
    ],
  }
  assert_true(
    parse_ai_deployment_proposal(
      interpreter, "D:/owned/repository", "powershell -Command Write-Host ok",
    )
    is Err(_),
  )
  let secret = sample_ai_plan()
  guard secret is Object(secret_object) else { abort("expected object") }
  secret_object["steps"] = [
    {
      "phase": "start",
      "program": "python",
      "args": ["app.py", "--token=secret"],
      "workdir": ".",
      "purpose": "unsafe secret",
    },
  ]
  assert_true(
    parse_ai_deployment_proposal(
      secret, "D:/owned/repository", "python app.py --token=secret",
    )
    is Err(_),
  )
  let raw_shell = sample_ai_plan()
  guard raw_shell is Object(raw_shell_object) else { abort("expected object") }
  raw_shell_object["shell"] = "npm start && whoami"
  assert_true(
    parse_ai_deployment_proposal(
      raw_shell, "D:/owned/repository", "npm install --no-audit --no-fund; npm start",
    )
    is Err(_),
  )
}

///|
test "AI plan is bounded to the canonical repository root" {
  let outside = sample_ai_plan()
  guard outside is Object(object) else { abort("expected object") }
  object["steps"] = [
    {
      "phase": "start",
      "program": "python",
      "args": ["../outside.py"],
      "workdir": ".",
      "purpose": "escape",
    },
  ]
  assert_true(
    parse_ai_deployment_proposal(
      outside, "D:/owned/repository", "python ../outside.py",
    )
    is Err(_),
  )
  let workdir = sample_ai_plan()
  guard workdir is Object(workdir_object) else { abort("expected object") }
  workdir_object["steps"] = [
    {
      "phase": "start",
      "program": "npm",
      "args": ["start"],
      "workdir": "frontend",
      "purpose": "unbound workdir",
    },
  ]
  assert_true(
    parse_ai_deployment_proposal(workdir, "D:/owned/repository", "npm start")
    is Err(_),
  )
}

///|
test "AI plan requires one final start and bounds non-deploy actions" {
  let no_start : Json = {
    "action": "DEPLOY",
    "reason": "incomplete",
    "steps": [
      {
        "phase": "build",
        "program": "cargo",
        "args": ["build"],
        "workdir": ".",
        "purpose": "build only",
      },
    ],
  }
  assert_true(
    parse_ai_deployment_proposal(no_start, "D:/owned/repository", "cargo build")
    is Err(_),
  )
  let learn : Json = {
    "action": "LEARN",
    "reason": "README does not document a non-interactive start command.",
    "evidence": ["README only describes the library API"],
    "steps": [],
  }
  guard parse_ai_deployment_proposal(learn, "D:/owned/repository", "")
    is Ok(value) else {
    abort("expected bounded LEARN result")
  }
  assert_true(value.authorize(true) is Err(_))
}

///|
test "AI plan rejects commands not literally backed by README evidence" {
  assert_true(
    parse_ai_deployment_proposal(
      sample_ai_plan(),
      "D:/owned/repository",
      "Install dependencies and start the app.",
    )
    is Err(_),
  )
}

///|
test "AI plan rejects interactive and host-wide command variants" {
  let interactive : Json = {
    "action": "DEPLOY",
    "reason": "interactive runtimes are not deployment steps",
    "steps": [
      {
        "phase": "start",
        "program": "node",
        "args": [],
        "workdir": ".",
        "purpose": "opens a REPL",
      },
    ],
  }
  assert_true(
    parse_ai_deployment_proposal(interactive, "D:/owned/repository", "Run node")
    is Err(_),
  )
  let global_install : Json = {
    "action": "DEPLOY",
    "reason": "global install is outside the repository",
    "steps": [
      {
        "phase": "start",
        "program": "npm",
        "args": ["install", "-g", "tool"],
        "workdir": ".",
        "purpose": "global mutation",
      },
    ],
  }
  assert_true(
    parse_ai_deployment_proposal(
      global_install, "D:/owned/repository", "npm install -g tool",
    )
    is Err(_),
  )
  let pip_uninstall : Json = {
    "action": "DEPLOY",
    "reason": "package removal is not a deployment operation",
    "steps": [
      {
        "phase": "start",
        "program": "python",
        "args": ["-m", "pip", "uninstall", "package"],
        "workdir": ".",
        "purpose": "remove package",
      },
    ],
  }
  assert_true(
    parse_ai_deployment_proposal(
      pip_uninstall, "D:/owned/repository", "python -m pip uninstall package",
    )
    is Err(_),
  )
}
