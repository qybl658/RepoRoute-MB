///|
test "security review selects route and never clears critical flags in compatibility mode" {
  let files = [
    @repowayfinder_mbt.source_file(
      "compose.yaml", "services:\n  x:\n    privileged: true",
    ),
  ]
  assert_true(
    @repowayfinder_mbt.security_review(files, "node", true).is_empty(),
  )
  assert_false(
    @repowayfinder_mbt.security_review(files, "docker-compose", false).is_empty(),
  )
}

///|
test "resolved Compose validates equivalent host privileges" {
  assert_true(
    @repowayfinder_mbt.validate_compose(
      { "services": { "app": { "image": "demo" } } },
      true,
    )
    is Ok(_),
  )
  assert_true(
    @repowayfinder_mbt.validate_compose(
      { "services": { "app": { "privileged": true } } },
      false,
    )
    is Err(_),
  )
  assert_true(
    @repowayfinder_mbt.validate_compose(
      {
        "services": {
          "app": { "volumes": [{ "type": "bind", "source": "/" }] },
        },
      },
      true,
    )
    is Err(_),
  )
}

///|
test "health checks cannot leak to external or credential URLs" {
  assert_true(
    @repowayfinder_mbt.local_health_url("http://127.0.0.1:8765/health"),
  )
  assert_false(
    @repowayfinder_mbt.local_health_url("http://127.0.0.1:80@evil.com/"),
  )
  assert_false(@repowayfinder_mbt.local_health_url("https://example.com"))
}
