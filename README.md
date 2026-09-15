# RepoWayfinder MB

把一个陌生仓库，从“下载后不知道怎么运行”推进到有依据、可复查的运行结果。

RepoWayfinder MB 是使用 MoonBit 编写的部署助手。它读取仓库里的启动配置，准备项目依赖、运行启动命令、检查本地服务，并记录每一步的结果。多个入口会保留供选择；缺少环境、项目失败和服务已验证是不同状态，不会混为“成功”。

## 开始使用

Windows 发布包解压后，双击 **点我启动RepoWayfinder-MB.bat**，输入 GitHub 仓库地址或本地项目路径。发布包优先运行内置原生程序，不要求为了启动助手再装 Python 或 MoonBit。

使用源码时需要 MoonBit 工具链和原生编译环境：

```powershell
moon update
moon run cmd/main -- deploy examples/python-cli --execute --trust-project
```

第一次运行失败时，使用 **首次运行失败时点我修复环境.bat**。它检查现有工具和路径，缺少环境时先说明原因；不会反复覆盖已经安装的工具。系统安装、许可证、UAC 和重启仍由你确认。

## 常用操作

```powershell
# 先看入口与来源，不执行项目代码
moon run cmd/main -- scan C:\projects\demo --format markdown

# 查看计划；远程仓库会先获取到独立目录
moon run cmd/main -- deploy owner/repo

# 安装项目依赖并运行；缺少系统工具时允许询问安装
moon run cmd/main -- deploy C:\projects\demo --execute --trust-project --install

# 多入口时明确选择第 1 条；验证服务并结束本次测试进程
moon run cmd/main -- deploy examples/node-http --candidate 1 --execute --trust-project --health-url http://127.0.0.1:18765/

# 保持前台运行，Ctrl+C 停止
moon run cmd/main -- deploy examples/node-http --execute --trust-project --serve

# 根据报告继续，或先查看失败原因
moon run cmd/main -- resume <report-directory>/deployment.json --execute --trust-project
moon run cmd/main -- diagnose <report-directory>/deployment.json

# 环境检查、配置模板和仓库搜索
moon run cmd/main -- doctor
moon run cmd/main -- config C:\projects\demo --write-config
moon run cmd/main -- config C:\projects\demo --edit-config
moon run cmd/main -- search "moonbit"
```

部署会保存 `.repowayfinder-reports/<id>/deployment.json` 和中文说明。续跑重新检查入口和环境，保留上一份报告；新版本仓库另存，已有配置和本地修改不被重置。中文启动器保留根目录 `run.md`，再次运行前归档旧日志。

Windows 报告目录还提供“准备好环境后点我继续”“查看诊断”“获取新版并运行”三个入口。运行前会确认第三方代码执行；更新后的多个候选需重新选择，不套用旧编号。启动助手移动位置后，需要用新位置的程序重新生成报告入口。

明确的安装／构建网络故障最多重试一次；Python 启动报错涉及已知依赖时，可确认后只向项目虚拟环境补装并重试。未知模块名不直接当作包名安装。

## 目前支持的运行路线

| 路线 | 实际执行内容 |
| --- | --- |
| Node.js | 根据锁文件选择 npm/pnpm/yarn/bun，安装依赖、按需 build、运行显式脚本 |
| Python | 创建项目虚拟环境，安装 requirements 或项目包，运行 console script、main/app 或受支持的 Procfile 命令 |
| MoonBit | 更新依赖、构建、运行 `cmd/main` |
| Rust | Cargo 依赖获取、构建和运行；系统工具缺失时等待 |
| Docker | 构建独立命名镜像、启动任务容器、回收本次容器 |
| Compose | 解析实际配置并检查权限，使用独立项目名启动和清理 |

环境模块可复用既有工具；受支持的缺失工具通过精确系统包标识或应用本地安装处理。卸载只处理有有效安装记录、身份仍匹配的工具，不把预先安装的环境归为己有。

Windows x64 没有 winget 时，可以使用官方 MinGit／Node 便携包，或签名验证后的 python.org 安装程序；下载需通过来源和完整性检查。便携 Git／Node 没有逐文件未修改证明时，卸载会保留目录并说明原因。`--edit-config` 只把你输入的值写入目标项目的配置文件（通常是明文），不会复制助手密钥，取消则保留原值。

## AI 辅助

AI 是可选项，不配置也能走确定性部署。它可以解释 README、建议现有启动路线和辅助分析报告；模型输出不会直接交给 shell 执行。

```powershell
moon run cmd/main -- ai-config
moon run cmd/main -- ai-config --endpoint https://api.deepseek.com --model deepseek-chat
moon run cmd/main -- analyze C:\projects\demo --allow-send
moon run cmd/main -- deploy C:\projects\demo --ai --allow-send
moon run cmd/main -- deploy C:\projects\demo --ai-plan --allow-send
moon run cmd/main -- diagnose <report-directory>/deployment.json --allow-send
```

Windows 配置使用系统凭据窗口和当前用户 DPAPI 加密。也可通过 `REPOWAYFINDER_AI_API_KEY`、`REPOWAYFINDER_AI_BASE_URL`、`REPOWAYFINDER_AI_MODEL` 配置。发送前需要 `--allow-send`；上下文仅取有限长度 README 与约定配置文件，不读取 `.env`。项目执行环境剔除助手的密钥和令牌。

`--ai` 选择已发现候选；`--ai-plan` 可生成 README 明确记载的结构化步骤，默认只展示。加上 `--execute --trust-project` 后仍需审阅确认。执行器补齐环境检查，把 Python 绑定到项目虚拟环境；续跑使用保存的提案重新验证 README，不重新调用模型。工作目录目前限定为仓库根目录；容器仍使用标准 Docker／Compose 路线以保留权限检查与资源回收。

## 结果与边界

成功报告内可双击“重新运行已验证入口.bat”再次启动。需要把作者 README 翻译、化简为中文时，使用报告内“生成中文小白指南.bat”；发送前会说明范围并确认，使用现有 AI 配置，失败保留离线指南。也可运行 `guide <deployment.json>`。

- `WAITING_ENVIRONMENT`：环境未准备好，项目命令未开始。
- `LEARN`：没有明确可运行入口，转为阅读说明和示例，不冒充部署失败。
- `BLOCKED_SECURITY`：检查阻止了执行，需要人工核对具体风险。
- `FAILED`：安装、构建或启动步骤确实失败。
- `SUCCEEDED`：程序正常退出，不代表所有业务功能已验收。
- `VERIFIED_HTTP`：启动后本地 HTTP 检查通过；验证模式随后停止程序。
- `UNVERIFIED_RUNTIME`：进程未退出但缺少健康证据，不算部署成功。

这不是沙箱。依赖安装与启动都会执行仓库代码；请先确认来源。Compose 仅自动接受实际路径位于项目内的目录挂载，项目外目录和 Docker 控制接口仍会被阻止；运行配置使用独立名称、本地端口和不自动重启策略，不改写原项目配置。自动识别仍有范围限制，复杂 monorepo、非标准 README 步骤和特殊系统组件不能承诺无人值守。具体验证状态见 [验证记录](docs/verification.md)，后续工作见 [ROADMAP](ROADMAP.md)。

## 开发与库接口

```powershell
moon fmt --check
moon check --deny-warn
moon test --deny-warn
moon build --target native --release
```

纯 `scan(root, files)` 输出带文件、行号、前提和理由的候选；`plan_deployment` 生成结构化 argv 步骤。`host` 负责进程边界，`environment` 负责环境生命周期，`repository` 负责来源获取，`runtime` 负责执行和报告，`advisor` 负责可选模型接入。扫描 JSON Schema 位于 `schema/run-contract.schema.json`。

许可证：Apache-2.0。
