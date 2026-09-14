///|
/// Errors reported while validating, searching for, or acquiring a repository.
pub suberror Failure {
  Failure(String)
} derive(Debug, ToJson)

///|
fn[T] fail(message : String) -> T raise Failure {
  raise Failure(message)
}

///|
fn valid_atom(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 100 &&
  value != "." &&
  value != ".." &&
  !value.has_prefix("-") &&
  value
  .iter()
  .all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '.' ||
    c == '_' ||
    c == '-'
  })
}

///|
/// Parse only the two public GitHub spellings RepoWayfinder supports.
fn parse_github_target(target : String) -> (String, String)? {
  let value = target.trim(chars=" \t\r\n").to_owned()
  let relative = if value.has_prefix("https://github.com/") {
    let rest = value["https://github.com/".length():].to_owned()
    if rest.contains("?") ||
      rest.contains("#") ||
      rest.contains("@") ||
      rest.contains("\\") {
      return None
    }
    rest
  } else if value.has_prefix("http://") ||
    value.contains("://") ||
    value.contains("@") ||
    value.contains("\\") {
    return None
  } else {
    value
  }
  let clean = if relative.has_suffix("/") {
    relative[:relative.length() - 1].to_owned()
  } else {
    relative
  }
  let parts = clean.split("/").collect()
  guard parts.length() == 2 else { return None }
  let owner = parts[0].to_owned()
  let raw_name = parts[1].to_owned()
  let name = if raw_name.has_suffix(".git") {
    raw_name[:raw_name.length() - 4].to_owned()
  } else {
    raw_name
  }
  if valid_atom(owner) && valid_atom(name) {
    Some((owner, name))
  } else {
    None
  }
}

///|
fn valid_sha(value : String) -> Bool {
  value.length() == 40 &&
  value
  .iter()
  .all(c => {
    (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
  })
}

///|
fn safe_detail(value : String) -> String {
  let clean = @host.redact(value)
    .replace_all(old="\r", new=" ")
    .replace_all(old="\n", new=" ")
  if clean.length() > 800 {
    clean[:800].to_owned() + "..."
  } else {
    clean
  }
}

///|
async fn unique_destination(
  workspace : String,
  owner : String,
  name : String,
) -> String {
  let stamp = @env.now().to_string()
  let base = @host.join(workspace, owner + "-" + name + "-" + stamp)
  let mut candidate = base
  let mut suffix = 2
  while @fs.exists(candidate[:]) ||
        @fs.exists((candidate + ".download.zip")[:]) ||
        @fs.exists((candidate + ".source.json")[:]) {
    candidate = base + "-" + suffix.to_string()
    suffix += 1
  }
  candidate
}

///|
fn ps_quote(value : String) -> String {
  "'" + value.replace_all(old="'", new="''") + "'"
}

///|
fn encoded_powershell(script : String) -> String {
  @base64.encode(@utf16.encode(script[:], endianness=Little)[:])
}

///|
fn valid_zip_entry_name(name : String, expected_root : String) -> Bool {
  if name.is_empty() ||
    name.contains("\\") ||
    name.contains(":") ||
    name.has_prefix("/") ||
    name.contains("//") ||
    name.iter().any(c => c.to_int() < 32) {
    return false
  }
  let clean = if name.has_suffix("/") {
    name[:name.length() - 1].to_owned()
  } else {
    name
  }
  let parts = clean.split("/").collect()
  !parts.is_empty() &&
  parts[0] == expected_root &&
  parts.all(part => part != "" && part != "." && part != "..")
}

///|
async fn prepare_workspace(workspace : String) -> String {
  let raw = workspace.trim(chars=" \t\r\n").to_owned()
  guard !raw.is_empty() else { fail("Workspace is empty.") }
  if !@fs.exists(raw[:]) {
    @fs.mkdir(raw[:], recursive=true) catch {
      _ => fail("Could not create the repository workspace.")
    }
  }
  guard (@fs.kind(raw[:]) catch { _ => Unknown }) == Directory else {
    fail("Repository workspace is not a directory.")
  }
  @fs.realpath(raw[:]) catch {
    _ => fail("Could not canonicalize the repository workspace.")
  }
}

///|
async fn github_json(url : String, label : String) -> Json {
  guard @host.resolve("curl") is Some(curl) else {
    fail("curl is required for " + label + " and is not available.")
  }
  let result = @host.run(
    curl,
    [
      "--fail-with-body", "--silent", "--show-error", "--location", "--max-time",
      "20", "--header", "Accept: application/vnd.github+json", "--header", "User-Agent: RepoWayfinder-MB/0.1",
      "--header", "X-GitHub-Api-Version: 2022-11-28", "--", url,
    ],
    @host.app_root(),
    25000,
  )
  guard result.code == 0 && !result.timed_out else {
    fail(label + " failed. " + safe_detail(result.output))
  }
  @json.parse(result.output) catch {
    _ => fail(label + " returned invalid or oversized JSON.")
  }
}

///|
async fn github_default_revision(
  owner : String,
  name : String,
) -> (String, String) {
  let repo = github_json(
    "https://api.github.com/repos/" + owner + "/" + name,
    "GitHub repository lookup",
  )
  guard repo is Object(fields) else {
    fail("GitHub repository lookup returned an unexpected response.")
  }
  if fields.get("private") is Some(True) {
    fail(
      "Private repositories are not supported by the public archive fallback.",
    )
  }
  guard fields.get("default_branch") is Some(String(branch)) &&
    !branch.is_empty() &&
    branch.length() <= 255 else {
    fail("GitHub repository has no usable default branch.")
  }
  let reference = github_json(
    "https://api.github.com/repos/" +
    owner +
    "/" +
    name +
    "/git/ref/heads/" +
    @percent.encode(branch),
    "GitHub default revision lookup",
  )
  guard reference is Object(ref_fields) else {
    fail("GitHub default revision lookup returned an invalid response.")
  }
  guard ref_fields.get("object") is Some(Object(object)) else {
    fail("GitHub default revision lookup returned no Git object.")
  }
  guard object.get("sha") is Some(String(revision)) && valid_sha(revision) else {
    fail("GitHub default revision lookup returned an invalid SHA.")
  }
  (branch, revision.to_lower())
}

///|
async fn extract_zip_safely(
  zip_path : String,
  destination : String,
  expected_root : String,
) -> String {
  guard @host.windows() else {
    fail("Secure GitHub ZIP fallback is currently available on Windows only.")
  }
  guard valid_zip_entry_name(expected_root + "/file", expected_root) else {
    fail("Archive root name is invalid.")
  }
  guard @host.resolve("powershell") is Some(powershell) else {
    fail("Windows PowerShell is required for secure archive extraction.")
  }
  let script = "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new(); " +
    "Add-Type -AssemblyName System.IO.Compression.FileSystem; $zip=" +
    ps_quote(zip_path) +
    "; $dest=" +
    ps_quote(destination) +
    "; $expected=" +
    ps_quote(expected_root) +
    "; if(Test-Path -LiteralPath $dest){throw 'exclusive destination already exists'}; " +
    "$archive=[IO.Compression.ZipFile]::OpenRead($zip); try{if($archive.Entries.Count -lt 1 -or $archive.Entries.Count -gt 20000){throw 'invalid archive entry count'}; " +
    "$destFull=[IO.Path]::GetFullPath($dest)+[IO.Path]::DirectorySeparatorChar; $seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); [int64]$total=0; " +
    "foreach($entry in $archive.Entries){$name=$entry.FullName; if([string]::IsNullOrWhiteSpace($name) -or $name.Contains([char]92) -or $name.Contains(':') -or $name.StartsWith('/') -or $name.Contains('//')){throw 'unsafe archive path'}; " +
    "$parts=$name.Split('/'); $last=$parts.Length-1; for($i=0;$i -lt $parts.Length;$i++){if(($parts[$i] -eq '' -and $i -ne $last) -or $parts[$i] -eq '.' -or $parts[$i] -eq '..'){throw 'archive traversal'}; foreach($ch in $parts[$i].ToCharArray()){if([char]::IsControl($ch)){throw 'archive control character'}}}; " +
    "if($parts[0] -cne $expected){throw 'unexpected archive root'}; $mode=($entry.ExternalAttributes -shr 16) -band 0xF000; if($mode -eq 0xA000 -or (($entry.ExternalAttributes -band 0x400) -ne 0)){throw 'archive link or reparse entry'}; " +
    "$total+=$entry.Length; if($entry.Length -gt 134217728 -or $total -gt 536870912){throw 'archive expanded size limit'}; if($entry.Length -gt 1048576 -and ($entry.CompressedLength -eq 0 -or ($entry.Length/[Math]::Max(1,$entry.CompressedLength)) -gt 500)){throw 'archive compression ratio limit'}; " +
    "$target=[IO.Path]::GetFullPath([IO.Path]::Combine($dest,$name.Replace('/',[IO.Path]::DirectorySeparatorChar))); if(-not $target.StartsWith($destFull,[StringComparison]::OrdinalIgnoreCase)){throw 'archive escaped destination'}; if(-not $seen.Add($target)){throw 'duplicate archive path'}}; " +
    "New-Item -ItemType Directory -Path $dest | Out-Null; foreach($entry in $archive.Entries){$target=[IO.Path]::GetFullPath([IO.Path]::Combine($dest,$entry.FullName.Replace('/',[IO.Path]::DirectorySeparatorChar))); if($entry.FullName.EndsWith('/')){New-Item -ItemType Directory -Path $target -Force | Out-Null}else{$parent=[IO.Path]::GetDirectoryName($target); New-Item -ItemType Directory -Path $parent -Force | Out-Null; $input=$entry.Open(); try{$output=New-Object IO.FileStream($target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None); try{$input.CopyTo($output)}finally{$output.Dispose()}}finally{$input.Dispose()}}}; " +
    "$root=[IO.Path]::Combine($dest,$expected); if(-not [IO.Directory]::Exists($root)){throw 'archive root missing'}; [Console]::Out.Write([IO.Path]::GetFullPath($root))}finally{$archive.Dispose()}"
  let result = @host.run(
    powershell,
    [
      "-NoProfile",
      "-NonInteractive",
      "-EncodedCommand",
      encoded_powershell(script),
    ],
    @host.app_root(),
    120000,
  )
  guard result.code == 0 && !result.timed_out else {
    fail(
      "Secure archive extraction failed; no existing path was replaced. " +
      safe_detail(result.output),
    )
  }
  let root = result.output.trim(chars=" \t\r\n").to_owned()
  guard @fs.exists(root[:]) &&
    (@fs.kind(root[:]) catch { _ => Unknown }) == Directory else {
    fail("Secure archive extraction did not produce the expected root.")
  }
  root
}

///|
async fn write_receipt(path : String, receipt : Json) -> Unit {
  @fs.write_file((path + ".source.json")[:], receipt.stringify()) catch {
    _ =>
      fail(
        "Acquisition succeeded but its provenance receipt could not be written beside " +
        path +
        ".",
      )
  }
}

///|
async fn github_archive_fallback(
  owner : String,
  name : String,
  workspace : String,
  update : Bool,
  git_failures : Array[String],
) -> String {
  let (branch, revision) = github_default_revision(owner, name)
  let container = unique_destination(workspace, owner, name)
  let zip_path = container + ".download.zip"
  guard @host.resolve("curl") is Some(curl) else {
    fail(
      "Git failed and curl is unavailable for the public GitHub archive fallback.",
    )
  }
  let url = "https://codeload.github.com/" +
    owner +
    "/" +
    name +
    "/zip/" +
    revision
  let downloaded = @host.run(
    curl,
    [
      "--fail", "--silent", "--show-error", "--location", "--max-time", "120", "--max-filesize",
      "104857600", "--output", zip_path, "--", url,
    ],
    workspace,
    130000,
  )
  guard downloaded.code == 0 && !downloaded.timed_out && @fs.exists(zip_path[:]) else {
    fail(
      "Git clone and the bounded GitHub archive download both failed. Git: " +
      git_failures.join(" | ") +
      "; archive: " +
      safe_detail(downloaded.output),
    )
  }
  let compressed_size = @fs.file_size(zip_path[:]) catch {
    _ => fail("Downloaded GitHub archive size could not be verified.")
  }
  guard compressed_size > 0L && compressed_size <= 104857600L else {
    fail("Downloaded GitHub archive is empty or exceeds 100 MiB.")
  }
  let expected_root = name + "-" + revision
  let root = extract_zip_safely(zip_path, container, expected_root)
  write_receipt(root, {
    "schema_version": 1,
    "source": "github_archive",
    "checkout": root,
    "origin": "https://github.com/" + owner + "/" + name,
    "default_branch": branch,
    "revision": revision,
    "git_metadata": false,
    "update_requested": update,
    "compressed_bytes": compressed_size,
  })
  // This exact file was created by the successful bounded download above. The
  // extracted root and receipt remain; pre-existing paths are never removed.
  @fs.remove(zip_path[:]) catch {
    _ => ()
  }
  root
}

///|
async fn acquire_github(
  owner : String,
  name : String,
  workspace : String,
  update : Bool,
) -> String {
  let workspace_real = prepare_workspace(workspace)
  guard @host.resolve("git") is Some(git) else {
    fail("Git is required for the primary repository acquisition path.")
  }
  let url = "https://github.com/" + owner + "/" + name + ".git"
  let variants : Array[Array[String]] = [
    [],
    ["-c", "http.version=HTTP/1.1", "-c", "core.compression=0"],
  ]
  let failures : Array[String] = []
  let mut destination = ""
  let mut cloned_ok = false
  for extra in variants {
    destination = unique_destination(workspace_real, owner, name)
    let args = ["-c", "core.longpaths=true"]
    if @host.windows() {
      args.append(["-c", "http.sslBackend=schannel"])
    }
    args.append(extra)
    args.append([
      "clone", "--depth", "1", "--single-branch", "--", url, destination,
    ])
    let cloned = @host.run(git, args, workspace_real, 120000)
    if cloned.code == 0 &&
      !cloned.timed_out &&
      @fs.exists(@host.join(destination, ".git")[:]) {
      cloned_ok = true
      break
    }
    failures.push(destination + ": " + safe_detail(cloned.output))
  }
  if !cloned_ok {
    return github_archive_fallback(
      owner, name, workspace_real, update, failures,
    )
  }
  let revision_result = @host.run(
    git,
    ["-C", destination, "rev-parse", "HEAD"],
    workspace_real,
    20000,
  )
  let revision = revision_result.output.trim(chars=" \t\r\n").to_owned()
  guard revision_result.code == 0 && valid_sha(revision) else {
    fail("The checkout succeeded but its Git revision could not be verified.")
  }
  write_receipt(destination, {
    "schema_version": 1,
    "source": "git",
    "checkout": destination,
    "origin": url,
    "revision": revision.to_lower(),
    "git_metadata": true,
    "update_requested": update,
  })
  destination
}

///|
fn revision_from_ls_remote(output : String) -> String? {
  let mut first = ""
  for line in output.split("\n") {
    if first.is_empty() && !line.trim().is_empty() {
      first = line.trim().to_owned()
    }
  }
  guard !first.is_empty() else { return None }
  let fields = first.split("\t").collect()
  let revision = if fields.length() > 0 {
    fields[0].trim().to_owned()
  } else {
    ""
  }
  if valid_sha(revision) {
    Some(revision.to_lower())
  } else {
    None
  }
}

///|
fn normalized_path_text(value : String) -> String {
  let path : @path.Path = value
  path.resolve().to_string().replace_all(old="\\", new="/").to_lower()
}

///|
fn path_is_inside(candidate : String, root : String) -> Bool {
  let candidate = normalized_path_text(candidate)
  let root = normalized_path_text(root)
  candidate == root || candidate.has_prefix((root + "/")[:])
}

///|
fn safe_update_workspace(requested : String, local_root : String) -> String {
  if path_is_inside(requested, local_root) {
    let root_path : @path.Path = local_root
    root_path.dirname().to_string()
  } else {
    requested
  }
}

///|
async fn update_local_checkout(
  local_path : String,
  workspace : String,
) -> String {
  let root = @fs.realpath(local_path[:]) catch {
    _ => fail("Could not canonicalize the local repository directory.")
  }
  guard @fs.exists(@host.join(root, ".git")[:]) else {
    fail(
      "A local update requires a Git checkout with public GitHub origin metadata.",
    )
  }
  guard @host.resolve("git") is Some(git) else {
    fail("Git is required to check a local repository update.")
  }
  let origin_result = @host.run(
    git,
    ["-C", root, "remote", "get-url", "origin"],
    root,
    20000,
  )
  let origin = origin_result.output.trim(chars=" \t\r\n").to_owned()
  guard origin_result.code == 0 &&
    origin.has_prefix("https://github.com/") &&
    parse_github_target(origin) is Some((owner, name)) else {
    fail("Local update requires a credential-free public HTTPS GitHub origin.")
  }
  let head_result = @host.run(
    git,
    ["-C", root, "rev-parse", "HEAD"],
    root,
    20000,
  )
  let local_head = head_result.output.trim(chars=" \t\r\n").to_owned()
  guard head_result.code == 0 && valid_sha(local_head) else {
    fail("Local Git HEAD could not be verified.")
  }
  let remote_result = @host.run(
    git,
    ["ls-remote", "--exit-code", "--", origin, "HEAD"],
    root,
    30000,
  )
  guard remote_result.code == 0 &&
    revision_from_ls_remote(remote_result.output) is Some(remote_head) else {
    fail(
      "Public origin HEAD could not be verified with git ls-remote; the local checkout was left unchanged.",
    )
  }
  if local_head.to_lower() == remote_head {
    return root
  }
  acquire_github(owner, name, safe_update_workspace(workspace, root), true)
}

///| Acquire a local directory or a public GitHub repository.

///|
/// Local directories are returned unchanged after canonicalization. A requested
/// update of a local directory is refused because this package never overwrites
/// local edits. GitHub acquisitions always clone into a new, uniquely named
/// sibling under `workspace`, preserving real Git semantics and old checkouts.
pub async fn acquire(
  target : String,
  workspace : String,
  update : Bool,
) -> String {
  let raw = target.trim(chars=" \t\r\n").to_owned()
  guard !raw.is_empty() else { fail("Repository target is empty.") }
  if @fs.exists(raw[:]) {
    guard (@fs.kind(raw[:]) catch { _ => Unknown }) == Directory else {
      fail("Local repository target is not a directory.")
    }
    if update {
      return update_local_checkout(raw, workspace)
    }
    return @fs.realpath(raw[:]) catch {
      _ => fail("Could not canonicalize the local repository directory.")
    }
  }
  guard parse_github_target(raw) is Some((owner, name)) else {
    fail(
      "Target must be an existing local directory, owner/repo, or https://github.com/owner/repo without credentials.",
    )
  }
  acquire_github(owner, name, workspace, update)
}

///|
/// Search public GitHub repositories without sending a private token.
pub async fn search(query : String) -> Json {
  let clean = query.trim(chars=" \t\r\n").to_owned()
  guard !clean.is_empty() else { fail("Search query is empty.") }
  guard clean.length() <= 256 else {
    fail("Search query exceeds 256 characters.")
  }
  let encoded = @percent.encode(clean)
  let url = "https://api.github.com/search/repositories?q=" +
    encoded +
    "&sort=stars&order=desc&per_page=1"
  guard @host.resolve("curl") is Some(curl) else {
    fail("curl is required for public GitHub search and is not available.")
  }
  let result = @host.run(
    curl,
    [
      "--fail-with-body", "--silent", "--show-error", "--location", "--max-time",
      "20", "--header", "Accept: application/vnd.github+json", "--header", "User-Agent: RepoWayfinder-MB/0.1",
      "--header", "X-GitHub-Api-Version: 2022-11-28", "--", url,
    ],
    @host.app_root(),
    25000,
  )
  guard result.code == 0 && !result.timed_out else {
    fail("GitHub search failed. " + safe_detail(result.output))
  }
  @json.parse(result.output) catch {
    _ => fail("GitHub search returned invalid JSON.")
  }
}
