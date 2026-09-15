///|
pub(all) struct DockerEolDiagnosis {
  suite : String
  successor : String
  public_lts_ended : String
} derive(Eq, Debug, ToJson)

///|
pub(all) struct DockerRepairResult {
  status : String
  diagnosis : DockerEolDiagnosis?
  repair_path : String
  replacement : String
  original_repository_modified : Bool
} derive(Eq, Debug, ToJson)

///|
fn bullseye_base_pinned(content : String) -> Bool {
  if content
    .split("\n")
    .any(raw => {
      let line = raw.trim().to_lower()
      line.has_prefix("from ") &&
      line.contains("bullseye") &&
      line.contains("@")
    }) {
    return false
  }
  for raw in content.split("\n") {
    let line = raw.trim(chars=" \t\r").to_lower()
    if !line.has_prefix("from ") {
      continue
    }
    let image = line
      .split(" ")
      .filter(part => !part.is_empty())
      .nth(1)
      .unwrap_or("")
    // A digest belongs to exact old image bytes; changing only its tag would
    // produce a misleading or invalid migration.
    if !image.contains("@"[:]) && image.has_suffix("bullseye") {
      return true
    }
  }
  false
}

///|
pub fn detect_eol_debian_dockerfile(
  content : String,
  uses_default_dockerfile : Bool,
) -> DockerEolDiagnosis? {
  guard uses_default_dockerfile && bullseye_base_pinned(content) else {
    return None
  }
  let mut live_suite_sources = false
  for raw in content.split("\n") {
    let line = raw.trim(chars=" \t\r").to_lower()
    if !line.has_prefix("#") &&
      (
        line.contains("bullseye-security"[:]) ||
        line.contains(" bullseye main"[:])
      ) {
      live_suite_sources = true
      break
    }
  }
  guard live_suite_sources else { return None }
  Some({
    suite: "bullseye",
    successor: "bookworm",
    public_lts_ended: "2026-08-31",
  })
}

///|
fn bounded_bullseye_migration(content : String) -> String {
  // These are the exact recipe tokens admitted by detection. Do not rewrite
  // arbitrary names, paths, or unrelated prose containing the suite name.
  content
  .replace_all(old="bullseye-security", new="bookworm-security")
  .replace_all(old="Bullseye-security", new="Bookworm-security")
  .replace_all(old="BULLSEYE-SECURITY", new="BOOKWORM-SECURITY")
  .replace_all(old="-bullseye", new="-bookworm")
  .replace_all(old=":bullseye", new=":bookworm")
  .replace_all(old=" bullseye main", new=" bookworm main")
  .replace_all(old=" Bullseye main", new=" Bookworm main")
  .replace_all(old=" BULLSEYE main", new=" BOOKWORM main")
}

///|
pub fn prepare_eol_docker_repair(
  source_path : String,
  report_dir : String,
  uses_default_dockerfile : Bool,
  approved : Bool,
) -> DockerRepairResult raise {
  let original = @fs.read_file_to_string(source_path)
  let diagnosis = detect_eol_debian_dockerfile(
    original, uses_default_dockerfile,
  )
  guard diagnosis is Some(info) else {
    return {
      status: "not_applicable",
      diagnosis: None,
      repair_path: "",
      replacement: "",
      original_repository_modified: false,
    }
  }
  guard approved else {
    return {
      status: "confirmation_required",
      diagnosis: Some(info),
      repair_path: "",
      replacement: "bullseye -> bookworm",
      original_repository_modified: false,
    }
  }
  let repaired = bounded_bullseye_migration(original)
  guard repaired != original else {
    return {
      status: "generation_failed",
      diagnosis: Some(info),
      repair_path: "",
      replacement: "bullseye -> bookworm",
      original_repository_modified: false,
    }
  }
  let repair_dir = @host.join(report_dir, "repairs")
  if !@fs.path_exists(repair_dir) {
    @fs.create_dir(repair_dir)
  }
  let repair_path = @host.join(repair_dir, "Dockerfile.bookworm")
  @fs.write_string_to_file(repair_path, repaired)
  {
    status: "isolated_repair_created",
    diagnosis: Some(info),
    repair_path,
    replacement: "bullseye -> bookworm",
    original_repository_modified: false,
  }
}
