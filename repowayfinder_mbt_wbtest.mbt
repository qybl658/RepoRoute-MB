///|
test "empty snapshot reports an honest no-entrypoint finding" {
  let contract = scan("empty", [])
  assert_eq(contract.candidates.length(), 0)
  assert_eq(contract.findings.length(), 1)
  assert_eq(contract.findings[0].code, "no-explicit-entrypoint")
}
