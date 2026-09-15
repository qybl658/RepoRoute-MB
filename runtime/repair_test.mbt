///|
test "retry only transport failures and never authorization failures" {
  assert_true(@runtime.transient_network_failure("connection reset by peer"))
  assert_false(
    @runtime.transient_network_failure("permission denied; connection reset"),
  )
  assert_false(
    @runtime.transient_network_failure("failed to connect to the Docker API"),
  )
}

///|
test "missing imports are mapped, not blindly installed" {
  assert_eq(
    @runtime.missing_known_python_package(
      "ModuleNotFoundError: No module named 'yaml'",
    ),
    Some("PyYAML"),
  )
  assert_eq(
    @runtime.missing_known_python_package(
      "ModuleNotFoundError: No module named 'my_private_helper'",
    ),
    None,
  )
  assert_eq(
    @runtime.missing_known_python_package(
      "ImportError: No module named \"PIL.Image\"",
    ),
    Some("Pillow"),
  )
}

///|
test "dependency repairs cover only bounded known actions" {
  assert_eq(
    @runtime.infer_dependency_repair(
      "ModuleNotFoundError: No module named 'pip'",
    ),
    Some({ kind: "python-ensurepip", package_name: "", timeout_ms: 120000, }),
  )
  assert_eq(
    @runtime.infer_dependency_repair("ImportError: No module named \"pip\""),
    Some({ kind: "python-ensurepip", package_name: "", timeout_ms: 120000, }),
  )
  assert_eq(
    @runtime.infer_dependency_repair("pytest: command not found"),
    Some({ kind: "python-package", package_name: "pytest", timeout_ms: 300000, }),
  )
  assert_eq(
    @runtime.infer_dependency_repair("sh: vite: not found"),
    Some({ kind: "node-install", package_name: "", timeout_ms: 300000, }),
  )
  assert_eq(
    @runtime.infer_dependency_repair(
      "ModuleNotFoundError: No module named 'private_plugin'",
    ),
    None,
  )
  assert_eq(
    @runtime.infer_dependency_repair("please run pip install surprise"),
    None,
  )
}
