///|
pub fn configure_project(root : String, write_templates : Bool) -> Json raise {
  let results : Array[Json] = []
  for
    (example, target) in [
      (".env.example", ".env"),
      ("config.example.toml", "config.toml"),
    ] {
    let source = @host.join(root, example)
    let destination = @host.join(root, target)
    if !@fs.path_exists(source) {
      continue
    }
    let content = @fs.read_file_to_string(source)
    let fields : Array[String] = []
    for raw in content.split("\n") {
      let line = raw.trim(chars=" \t\r")
      if line.has_prefix("#") || line.has_prefix("[") {
        continue
      }
      if line.split_once("=") is Some((key, _)) {
        let key = key.trim(chars=" \t").to_owned()
        if @lib.safe_entry_name(key) {
          fields.push(key)
        }
      }
    }
    let exists = @fs.path_exists(destination)
    if write_templates && !exists {
      @fs.write_string_to_file(destination, content)
    }
    results.push({
      "template": example,
      "target": target,
      "fields": fields,
      "status": if exists {
        "preserved_existing"
      } else if write_templates {
        "created_from_template"
      } else {
        "available"
      },
      "note": "Review placeholder values locally. Keys belonging to RepoWayfinder are never copied into target configuration.",
    })
  }
  { "configuration": results }
}
