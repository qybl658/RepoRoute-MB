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
}
