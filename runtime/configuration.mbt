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

///|
pub async fn configure_interactive(root : String) -> Json {
  let root = @afs.realpath(root[:])
  guard @host.windows() else {
    raise DeploymentError(
      "Interactive project secret entry requires Windows; edit the target configuration locally.",
    )
  }
  guard @host.resolve("powershell") is Some(powershell) else {
    raise DeploymentError("Windows PowerShell is unavailable.")
  }
  let templates = configure_project(root, true)
  guard templates is Object(fields) &&
    fields.get("configuration") is Some(Array(configs)) else {
    return templates
  }
  let results : Array[Json] = []
  for config in configs {
    guard config is Object(info) &&
      info.get("target") is Some(String(target)) &&
      info.get("fields") is Some(Array(keys)) else {
      continue
    }
    let path = @host.join(root, target)
    let canonical_target = @afs.realpath(path[:])
    if canonical_target.replace_all(old="\\", new="/").to_lower() !=
      path.replace_all(old="\\", new="/").to_lower() {
      raise DeploymentError(
        "Refusing to write project secrets through a redirected configuration path.",
      )
    }
    for key in keys {
      guard key is String(name) && @host.sensitive_name(name) else { continue }
      let quote = (s : String) => "'" + s.replace_all(old="'", new="''") + "'"
      // Values stay inside PowerShell memory and the explicitly selected target config.
      // The credential dialog's password field is not echoed or returned to this process.
      let script = "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; $p=" +
        quote(path) +
        "; $k=" +
        quote(name) +
        "; " +
        (
          #|$initial=[IO.File]::ReadAllText($p); $lines=[IO.File]::ReadAllLines($p); $pattern='^\s*'+[regex]::Escape($k)+'\s*='; $keyLines=@(0..($lines.Length-1) | Where-Object { $lines[$_] -match $pattern });
          #|if($keyLines.Count -ne 1) { Write-Output 'preserved_ambiguous_key'; exit 0 };
          #|$credential=Get-Credential -UserName $k -Message ('Set '+$k+' in target project '+$p+'. Cancel preserves its current value.');
          #|if($null -eq $credential) { Write-Output 'preserved_cancelled'; exit 0 };
          #|$value=$credential.GetNetworkCredential().Password;
          #|if([string]::IsNullOrEmpty($value)) { Write-Output 'preserved_empty'; exit 0 };
          #|$encoded=ConvertTo-Json -InputObject $value -Compress;
          #|$lines[$keyLines[0]]=$k+'='+$encoded;
          #|if([IO.File]::ReadAllText($p) -ne $initial) { Write-Output 'preserved_concurrent_edit'; exit 0 };
          #|[IO.File]::WriteAllLines($p,$lines,[Text.UTF8Encoding]::new($false));
          #|Write-Output 'updated';
        )
      let result = @host.run(
        powershell,
        ["-NoLogo", "-NoProfile", "-Command", script],
        root,
        300000,
      )
      results.push({
        "target": target,
        "field": name,
        "status": if result.code == 0 {
          result.output.trim().to_owned()
        } else {
          "not_updated"
        },
      })
    }
  }
  {
    "configuration": results,
    "note": "Only target-project values entered by the user are written. Assistant credentials are never copied.",
  }
}
