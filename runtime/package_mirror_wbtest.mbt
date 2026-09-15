///|
test "mirror routes preserve argv and do not override explicit registries" {
  assert_eq(
    package_mirror_args("npm", ["ci"]),
    Some(["ci", "--registry=https://registry.npmmirror.com"]),
  )
  assert_eq(
    package_mirror_args("python.exe", ["-m", "pip", "install", "--", "requests"]),
    Some([
      "-m", "pip", "install", "--index-url=https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple",
      "--", "requests",
    ]),
  )
  assert_eq(
    package_mirror_args("npm", ["ci", "--registry=https://private.example"]),
    None,
  )
  assert_eq(
    package_mirror_args("python", [
      "-m", "pip", "install", "--extra-index-url=x",
    ]),
    None,
  )
  assert_eq(package_mirror_args("docker", ["build", "."]), None)
  assert_false(transient_network_failure("permission denied ETIMEDOUT"))
  assert_true(transient_network_failure("npm ERR! ETIMEDOUT"))
}
