# repository package

Public API:

- `acquire(target, workspace, update)` accepts an existing local directory or a
  strict public GitHub `owner/repo`/HTTPS target. A local update validates its
  public HTTPS GitHub origin and compares local `HEAD` with `git ls-remote HEAD`;
  an unchanged checkout is reused read-only, while a changed one is acquired in
  a new workspace directory with all existing edits preserved.
- Remote acquisition starts with a shallow Git clone and one bounded HTTP/1.1
  compatibility retry. If both fail, the package resolves the immutable default
  branch SHA through GitHub's public API, downloads the official codeload ZIP,
  validates entry count, compressed/expanded size, traversal, duplicate paths,
  symlinks/reparse points and compression ratio, then extracts each file with
  exclusive creation. Archive receipts explicitly set `git_metadata: false`;
  no history is fabricated.
- `search(query)` calls the public GitHub repository search API through bounded
  `curl` arguments without a token and returns the parsed JSON response. One
  star-sorted result is requested so the host's bounded output remains intact.

The package never persists Git configuration and rejects credential-bearing,
HTTP, non-GitHub, private, or option-shaped URL inputs. Existing paths are never
reset, renamed, overwritten, or deleted.
