# 行为对照与验证边界

更新：2026-09-15。对照原版提交 `966eb0eef672013151497d9819b5a6e9b08f9271`；不能用旧副本或单个仓库运行成功代替功能对照。

| 原版行为 / 代码入口 | MB 对应位置 | 当前证据与差异 |
| --- | --- | --- |
| 关键词搜索、Git 优先与 ZIP 获取 | `repository/`、`cmd/main/` | 公开搜索、克隆及 ZIP 边界已有测试；GitClone 回退已接入：匿名取得官方 SHA、精确匹配、恢复官方 origin，忽略 curl/Git 用户配置。镜像分支离线测试，不冒充真实网络镜像验收 |
| Node/Python/Docker/Compose 部署 | `deploy_plan.mbt`、`runtime/deploy.mbt` | 真实本地部署与 HTTP 检查；并非任意仓库兼容保证 |
| `visible_blocking_wait` | `host/host.mbt`、`scripts/bootstrap.ps1` | 先提示后输入；命令等待动态显示且不污染日志，交互回归已覆盖 |
| `package_mirror_command` | `runtime/package_mirror.mbt` | 识别网络错误后一次临时 PyPI/npm 镜像；保留显式源，不修改配置；私有依赖必须拒绝发送。离线替身验证完整重试与拒绝分支；未重新执行真实镜像下载 |
| `detect_eol_debian_dockerfile` / `prepare_eol_docker_repair` | `runtime/docker_repair.mbt`、部署入口 | 默认 Dockerfile 的已知 Bullseye 配方经确认生成报告内副本，构建显式使用 `--file`。原文件不变；摘要固定镜像和仅注释匹配不自动处理。源码及离线命令链通过，不等于新版镜像业务兼容已验证 |
| WSL 重启等待标记 / `resume_deployment.ps1` | `environment/environment.mbt`、`runtime.resume` | 已实现启动周期识别、防重复、重启后重新探测、不确定结果保留；已接入按证据选择 VirtualMachinePlatform/官方 WSL 命令及用户确认后的原生 UAC。真实新机/UAC/重启仍待对应环境验收，不自动重启、不重装现有 Docker |
| `local_readme_beginner_digest` / 下一步指导 | `runtime/beginner_guide.mbt` | 离线按状态给下一步并引用 README；`guide REPORT` 和报告内中文 BAT 可经确认调用已有 AI 翻译/化简，独立保存中文指南，失败保留离线版，不执行模型返回内容。实际付费请求需单独授权 |
| 项目配置保留、环境归属及卸载 | `runtime/configuration.mbt`、`environment/` | 已有配置保护与应用本地工具验证；系统级卸载仍需相应真实环境验收 |
| 报告、续跑、计划变更拒绝 | `runtime/deploy.mbt` | 八项部署回归及报告入口验证已覆盖；重启后仍需探测，不能从旧收据推断就绪 |
| 依赖缺失修复 / `infer_repair` | `runtime/repair.mbt` | 已覆盖单双引号 ImportError/ModuleNotFoundError、缺 pip/pytest/Vite，接入安装、构建和启动失败后的有界修复；故意保留已知包映射，不从任意错误文本推断陌生安装包 |
| Python 版本、虚拟环境备份/恢复 | `runtime/python_environment.mbt` | 读取 `.python-version`，选择已安装的匹配解释器；匹配 venv 复用，损坏或版本不符则保留备份和报告内恢复脚本，拒绝外链目录。找不到匹配解释器返回等待，不使用错误版本硬跑 |
| `write_start_script` | `runtime/deploy.mbt` | 成功报告生成“重新运行已验证入口.bat”，复用保存计划的校验/环境准备和前台服务逻辑，不复制另一套执行器 |
| 模型规划、诊断与安全边界 | `advisor/`、`ai_plan.mbt` | 结构化 README 计划与离线校验已有测试；实际模型账户端到端未据此验证 |

此表记录源码功能对应关系，不宣称任意第三方仓库或真实系统环境都已经验收。实现方式与 CLI 形态可以随语言改变；原版用户能力、失败恢复与保护边界逐项映射。陌生包安装、非结构化任意模型命令仍采用明确的安全限制，不归因于 MoonBit 语言不可实现。

专项验证：`scripts/test-parity.ps1` 使用自己编写的离线 npm/Docker 替身，不连接镜像、不安装第三方包、不重启系统。它验证执行链路及拒绝分支，不能替代真实服务与系统验收。
