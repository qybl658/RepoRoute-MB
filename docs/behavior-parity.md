# 行为对照与验证边界

更新：2026-09-15。对照原版提交 `966eb0eef672013151497d9819b5a6e9b08f9271`；不能用旧副本或单个仓库运行成功代替功能对照。

| 原版行为 / 代码入口 | MB 对应位置 | 当前证据与差异 |
| --- | --- | --- |
| 关键词搜索、Git 优先与 ZIP 获取 | `repository/`、`cmd/main/` | 已有真实公开搜索、克隆及 ZIP 边界测试；尚未移植 GitClone 同 SHA 镜像分支 |
| Node/Python/Docker/Compose 部署 | `deploy_plan.mbt`、`runtime/deploy.mbt` | 真实本地部署与 HTTP 检查；并非任意仓库兼容保证 |
| `visible_blocking_wait` | `host/host.mbt`、`scripts/bootstrap.ps1` | 先提示后输入；命令等待动态显示且不污染日志，交互回归已覆盖 |
| `package_mirror_command` | `runtime/package_mirror.mbt` | 识别网络错误后一次临时 PyPI/npm 镜像；保留显式源，不修改配置；私有依赖必须拒绝发送。离线替身验证完整重试与拒绝分支；未重新执行真实镜像下载 |
| `detect_eol_debian_dockerfile` / `prepare_eol_docker_repair` | `runtime/docker_repair.mbt`、部署入口 | 默认 Dockerfile 的已知 Bullseye 配方经确认生成报告内副本，构建显式使用 `--file`。原文件不变；摘要固定镜像和仅注释匹配不自动处理。源码及离线命令链通过，不等于新版镜像业务兼容已验证 |
| WSL 重启等待标记 / `resume_deployment.ps1` | `environment/environment.mbt`、`runtime.resume` | 已实现启动周期识别、防重复、重启后重新探测、不确定结果保留；源码状态分支通过，真实新机/UAC/重启仍待对应环境验收。Windows 可选功能的完整提权引导尚未全部对应 |
| `local_readme_beginner_digest` / 下一步指导 | `runtime/beginner_guide.mbt` | 报告按状态给下一步并引用 README 安装/使用章节；原文摘录不执行，未实现原版完整 AI 翻译/化简流程 |
| 项目配置保留、环境归属及卸载 | `runtime/config.mbt`、`environment/` | 已有配置保护与应用本地工具验证；系统级卸载仍需相应真实环境验收 |
| 报告、续跑、计划变更拒绝 | `runtime/deploy.mbt` | 八项部署回归及报告入口验证已覆盖；重启后仍需探测，不能从旧收据推断就绪 |
| 依赖缺失修复 / `infer_repair` | `runtime/repair.mbt` | 明确 Python 包映射已实现；与原版其余修复分支尚未完全对齐，不接受任意缺包名称直接安装 |
| 模型规划、诊断与安全边界 | `advisor/`、`ai_plan.mbt` | 结构化 README 计划与离线校验已有测试；实际模型账户端到端未据此验证 |

此表记录已对照的功能，不是全量一致性认证。后续迁移以原版入口、状态分支和对应回归为单位，不再依据临时演示需求自行省略行为。实现方式可以随语言改变，用户可见能力与保护边界必须明确对应。

专项验证：`scripts/test-parity.ps1` 使用自己编写的离线 npm/Docker 替身，不连接镜像、不安装第三方包、不重启系统。它验证执行链路及拒绝分支，不能替代真实服务与系统验收。
