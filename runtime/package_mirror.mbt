///|
/// Port of the original package_mirror_command, using argv instead of shell text.
pub fn package_mirror_args(
  program : String,
  args : Array[String],
) -> Array[String]? {
  let name = program
    .replace_all(old="\\", new="/")
    .split("/")
    .last()
    .unwrap_or("")
    .to_lower()
    .to_owned()
  if args.any(arg => {
      arg == "-i" ||
      arg.has_prefix("--index-url") ||
      arg.has_prefix("--extra-index-url") ||
      arg.has_prefix("--registry")
    }) {
    return None
  }
  let result = args.copy()
  if args.length() >= 3 &&
    args[0] == "-m" &&
    args[1] == "pip" &&
    ["install", "download", "wheel"].contains(args[2]) {
    result.insert(
      3, "--index-url=https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple",
    )
    Some(result)
  } else if ["npm", "npm.cmd", "pnpm", "pnpm.cmd", "yarn", "yarn.cmd"].contains(
      name,
    ) &&
    args.length() > 0 &&
    ["install", "ci", "add"].contains(args[0]) {
    result.insert(1, "--registry=https://registry.npmmirror.com")
    Some(result)
  } else {
    None
  }
}

///|
/// Custom indexes and private package configuration always take precedence.
fn has_custom_package_source(root : String, python : Bool) -> Bool {
  let keys = if python {
    ["PIP_INDEX_URL", "PIP_EXTRA_INDEX_URL", "PIP_CONFIG_FILE"]
  } else {
    ["NPM_CONFIG_REGISTRY", "npm_config_registry", "YARN_REGISTRY"]
  }
  for key in keys {
    if @env.get_env_var(key) is Some(value) && !value.is_empty() {
      return true
    }
  }
  let names = if python {
    ["pip.ini", "pip.conf"]
  } else {
    [".npmrc", ".yarnrc", ".yarnrc.yml"]
  }
  let home = @env.get_env_var("USERPROFILE").unwrap_or(
    @env.get_env_var("HOME").unwrap_or(""),
  )
  for name in names {
    if @fs.path_exists(@host.join(root, name)) {
      return true
    }
    if !home.is_empty() && @fs.path_exists(@host.join(home, name)) {
      return true
    }
  }
  false
}

///|
/// A local/modified checkout can contain private dependency names even when its
/// origin is public, so crossing to a new public registry requires confirmation.
async fn retry_package_mirror(
  root : String,
  step : @lib.DeploymentStep,
  failure : @host.CommandResult,
  allow_install : Bool,
) -> (@host.CommandResult, Array[String])? {
  guard step.phase == "install" &&
    allow_install &&
    transient_network_failure(failure.output) &&
    !has_custom_package_source(root, step.args.contains("pip")) else {
    return None
  }
  guard package_mirror_args(step.program, step.args) is Some(args) else {
    return None
  }
  guard @host.prompt(
    "官方依赖源出现网络错误。是否确认依赖均为公开包，并允许仅本次改用清华 PyPI / npmmirror？镜像会收到包名及下载请求；私有依赖请选择否，不会修改全局配置。",
  ) else {
    return None
  }
  println(
    "正在通过一次性公共镜像重试依赖安装，不修改项目或全局源配置。",
  )
  Some(
    (
      @host.run(step.program, args, root, 600000, on_chunk=chunk => {
        println(chunk)
      }),
      args,
    ),
  )
}
