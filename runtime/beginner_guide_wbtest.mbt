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
