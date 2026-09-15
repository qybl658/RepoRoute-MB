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
  assert_true(is_github_target("owner/repository"))
  assert_false(is_github_target("AI Agent"))
  assert_true(is_local_path_hint("D:\\projects\\agent"))
  assert_true(is_local_path_hint("./local-agent"))
  assert_false(is_local_path_hint("AI Agent"))
}

///|
test "search results become bounded safe interactive candidates" {
  let candidates = search_candidates({
    "items": [
      {
        "full_name": "owner/agent-one",
        "description": "First agent",
        "language": "Python",
        "stargazers_count": 42,
        "archived": false,
      },
      { "full_name": "unsafe extra path/name", "stargazers_count": 99 },
      { "full_name": "owner/agent-two", "description": null, "archived": true },
    ],
  })
  assert_eq(candidates.length(), 2)
  assert_eq(candidates[0].full_name, "owner/agent-one")
  assert_eq(candidates[0].stars, 42)
  assert_eq(candidates[1].language, "未知")
  assert_true(candidates[1].archived)
  assert_eq(search_candidates({ "items": "invalid" }), [])
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
test "GitClone fallback is restricted to transport failures" {
  assert_true(retryable_git_transport_failure("fatal: early EOF", false))
  assert_true(
    retryable_git_transport_failure(
      "fatal: unable to access: Could not resolve host", false,
    ),
  )
  assert_true(retryable_git_transport_failure("anything", true))
  assert_false(
    retryable_git_transport_failure(
      "fatal: repository not found or authentication failed", false,
    ),
  )
}

///|
test "GitClone command is anonymous, bounded, and option-safe" {
  let destination = if @host.windows() {
    "D:/isolated/task/checkout"
  } else {
    "/isolated/task/checkout"
  }
  let args = anonymous_mirror_git_args(
    "octocat", "Hello-World", "master", destination,
  ).unwrap()
  assert_true(args.contains("credential.helper="))
  assert_true(args.contains("credential.interactive=never"))
  assert_true(args.contains("core.askPass="))
  assert_true(args.contains("--depth"))
  assert_true(args.contains("--single-branch"))
  assert_eq(
    args[args.length() - 2],
    "https://gitclone.com/github.com/octocat/Hello-World.git",
  )
  assert_eq(args[args.length() - 1], destination)
  assert_eq(gitclone_mirror_url("--upload-pack=x", "repo"), None)
}

///|
test "GitClone acceptance requires exact official SHA and restored origin" {
  let official = "0123456789abcdef0123456789abcdef01234567"
  assert_eq(verified_mirror_revision(official + "\n", official), Some(official))
  assert_eq(
    verified_mirror_revision(
      "1123456789abcdef0123456789abcdef01234567", official,
    ),
    None,
  )
  assert_eq(verified_mirror_revision("not-a-sha", official), None)
  let url = "https://github.com/octocat/Hello-World.git"
  assert_true(official_origin_was_restored(0, false, url + "\n", url))
  assert_false(
    official_origin_was_restored(
      0, false, "https://gitclone.com/github.com/octocat/Hello-World.git", url,
    ),
  )
  assert_false(official_origin_was_restored(1, false, url, url))
}

///|
test "public GitHub curl calls disable user curl configuration first" {
  let api = github_api_curl_args("https://api.github.com/repos/o/r")
  let archive = github_archive_curl_args(
    "https://codeload.github.com/o/r/zip/revision", "checkout.zip",
  )
  assert_eq(api[0], "--disable")
  assert_eq(archive[0], "--disable")
  assert_eq(api[api.length() - 2], "--")
  assert_eq(archive[archive.length() - 2], "--")
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
  let parent = if @host.windows() { "C:/work" } else { "/work" }
  let root = parent + "/project"
  let other = if @host.windows() { "D:/downloads" } else { "/downloads" }
  assert_eq(
    normalized_path_text(safe_update_workspace(root + "/downloads", root)),
    normalized_path_text(parent),
  )
  assert_eq(
    normalized_path_text(safe_update_workspace(other, root)),
    normalized_path_text(other),
  )
}
