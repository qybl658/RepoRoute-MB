///|
pub fn render_json(contract : RunContract) -> String {
  contract.to_json().stringify(indent=2)
}

///|
pub fn render_markdown(contract : RunContract) -> String {
  let out = StringBuilder()
  out.write_string("# Repository launch contract\n\n")
  out.write_string("Root: `\{contract.root}`\n\n")
  if contract.candidates.is_empty() {
    out.write_string("No supported explicit launch entrypoint was found.\n")
  } else {
    out.write_string("## Candidates\n\n")
    for index, candidate in contract.candidates {
      out.write_string(
        "\{index + 1}. `\{candidate.command}` — \{candidate.reason}\n",
      )
      out.write_string(
        "   Evidence: `\{candidate.evidence.file}:\{candidate.evidence.line}` (`\{candidate.evidence.excerpt}`); confidence \{candidate.confidence}/100.\n",
      )
    }
  }
  if !contract.findings.is_empty() {
    out.write_string("\n## Findings\n\n")
    for finding in contract.findings {
      out.write_string(
        "- **\{finding.level} / \{finding.code}:** \{finding.message}\n",
      )
    }
  }
  out.to_string()
}
