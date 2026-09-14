///|
async test "project bind is allowed but external bind is refused" {
  let path = @afs.realpath("."[:])
  let config : Json = {
    "services": {
      "app": {
        "image": "node:22-alpine",
        "container_name": "user-collision",
        "restart": "always",
        "volumes": [{ "type": "bind", "source": path, "target": "/work" }],
      },
    },
  }
  let result = prepare_compose(config, path, true)
  guard result is Object(root) &&
    root.get("services") is Some(Object(services)) &&
    services.get("app") is Some(Object(app)) else {
    fail("missing service")
  }
  assert_eq(app.get("container_name"), None)
  assert_eq(app.get("restart"), Some(Json("no")))
  let outside = @afs.realpath(".."[:])
  try
    prepare_compose(
      {
        "services": {
          "app": {
            "volumes": [
              { "type": "bind", "source": outside, "target": "/host" },
            ],
          },
        },
      },
      path,
      true,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("external bind accepted")
  }
}
