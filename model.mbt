///|
pub(all) struct SourceFile {
  path : String
  content : String
} derive(Eq, Debug)

///|
pub(all) struct Evidence {
  file : String
  line : Int
  excerpt : String
} derive(Eq, Debug)

///|
pub(all) struct Candidate {
  ecosystem : String
  command : String
  workdir : String
  confidence : Int
  prerequisites : Array[String]
  reason : String
  evidence : Evidence
} derive(Eq, Debug)

///|
pub(all) struct Finding {
  level : String
  code : String
  message : String
  file : String
} derive(Eq, Debug)

///|
pub(all) struct RunContract {
  schema_version : Int
  root : String
  candidates : Array[Candidate]
  findings : Array[Finding]
} derive(Eq, Debug)

///|
pub fn source_file(path : String, content : String) -> SourceFile {
  let slash_path = path.replace_all(old="\\", new="/")
  let normalized = if slash_path.has_prefix("./") {
    slash_path[2:].to_owned()
  } else {
    slash_path
  }
  { path: normalized, content, }
}

///|
fn evidence_to_json(value : Evidence) -> Json {
  { "file": value.file, "line": value.line, "excerpt": value.excerpt }
}

///|
fn candidate_to_json(value : Candidate) -> Json {
  {
    "ecosystem": value.ecosystem,
    "command": value.command,
    "workdir": value.workdir,
    "confidence": value.confidence,
    "prerequisites": value.prerequisites,
    "reason": value.reason,
    "evidence": evidence_to_json(value.evidence),
  }
}

///|
fn finding_to_json(value : Finding) -> Json {
  {
    "level": value.level,
    "code": value.code,
    "message": value.message,
    "file": value.file,
  }
}

///|
pub fn RunContract::to_json(self : RunContract) -> Json {
  {
    "schema_version": self.schema_version,
    "root": self.root,
    "candidates": self.candidates.map(candidate_to_json),
    "findings": self.findings.map(finding_to_json),
  }
}
