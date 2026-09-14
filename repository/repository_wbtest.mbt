///|
test "accepts only safe public GitHub targets" {
  assert_eq(
    parse_github_target("octocat/Hello-World"),
    Some(("octocat", "Hello-World")),
  )
  assert_eq(
    parse_github_target("https://github.com/moonbitlang/moon.git/"),
    Some(("moonbitlang", "moon")),
  )
  assert_eq(parse_github_target("http://github.com/a/b"), None)
  assert_eq(parse_github_target("https://user:secret@github.com/a/b"), None)
  assert_eq(parse_github_target("https://github.com/a/--upload-pack=x"), None)
  assert_eq(parse_github_target("https://github.com/a/b/extra"), None)
}

///|
test "revision and output validation are bounded" {
  assert_true(valid_sha("0123456789abcdef0123456789abcdef01234567"))
  assert_false(valid_sha("not-a-sha"))
  assert_eq(
    revision_from_ls_remote("0123456789abcdef0123456789abcdef01234567\tHEAD\n"),
    Some("0123456789abcdef0123456789abcdef01234567"),
  )
  assert_eq(revision_from_ls_remote("not-a-sha\tHEAD\n"), None)
  assert_true(safe_detail("x\n" + "a".repeat(1000)).length() <= 803)
}

///|
test "archive entry validation rejects traversal and filesystem tricks" {
  let root = "Hello-World-0123456789abcdef0123456789abcdef01234567"
  assert_true(valid_zip_entry_name(root + "/README.md", root))
  assert_true(valid_zip_entry_name(root + "/src/", root))
  assert_false(valid_zip_entry_name(root + "/../outside.txt", root))
  assert_false(valid_zip_entry_name(root + "/./inside.txt", root))
  assert_false(valid_zip_entry_name(root + "\\outside.txt", root))
  assert_false(valid_zip_entry_name("/" + root + "/file", root))
  assert_false(valid_zip_entry_name(root + "/C:payload", root))
  assert_false(valid_zip_entry_name(root + "//file", root))
  assert_false(valid_zip_entry_name("different-root/file", root))
  assert_false(valid_zip_entry_name(root + "/bad\u{0001}name", root))
}

///|
test "local update workspace never nests a replacement inside the checkout" {
  let root = "C:\\work\\project"
  assert_eq(
    normalized_path_text(
      safe_update_workspace("C:\\work\\project\\downloads", root),
    ),
    normalized_path_text("C:\\work"),
  )
  assert_eq(
    normalized_path_text(safe_update_workspace("D:\\downloads", root)),
    normalized_path_text("D:\\downloads"),
  )
}
