///|
test "README guide selects author usage without inventing commands" {
  let excerpt = readme_usage_excerpt(
    "# Demo\nintro\n## Installation\nnpm ci\n## Usage\nnpm start\n## Credits\nnot usage",
  )
  assert_true(excerpt.contains("npm ci"))
  assert_true(excerpt.contains("npm start"))
  assert_false(excerpt.contains("not usage"))
  assert_false(readme_usage_excerpt("# Empty").contains("npm"))
}

///|
test "translated guide keeps evidence and unverified boundary" {
  let guide = render_chinese_guide({
    "summary": "示例工具",
    "recommendation": "先配置，再打开作者提供的页面。",
    "evidence": ["README Usage"],
    "risks": ["需要 API 密钥"],
  })
  assert_true(guide.contains("未经执行验证"))
  assert_true(guide.contains("README Usage"))
  assert_true(guide.contains("先配置"))
  try render_chinese_guide({ "summary": "incomplete" }) catch {
    _ => ()
  } noraise {
    _ => fail("invalid AI guide accepted")
  }
}
