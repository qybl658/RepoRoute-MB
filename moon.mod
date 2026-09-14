// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "qybl658/repowayfinder_mbt"

version = "0.2.0"

readme = "README.md"

repository = "https://github.com/qybl658/RepoWayfinder-MB"

license = "Apache-2.0"

keywords = [ "repository", "cli", "launch", "evidence", "devtools" ]

preferred_target = "native"

description = "Evidence-backed repository deployment, environment preparation and runtime verification in MoonBit"

import {
  "moonbitlang/x@0.5.5",
  "moonbitlang/async@0.21.3",
}
