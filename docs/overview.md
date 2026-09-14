# RepoWayfinder MB｜仓库启动证据提取器

## 产品目标

陌生开源仓库经常同时包含包管理器脚本、语言清单、Dockerfile 与 Compose 等多个入口。人或自动化工具很容易直接猜出一个命令，却无法说明来源、所需环境和其他冲突入口。RepoWayfinder MB 使用 MoonBit 将这些结构化证据编译为确定、可追踪的运行契约。

## 核心特点

- 每个启动候选都携带来源文件、行号、原文、依赖与置信度，结论可复核。
- 多入口不被静默覆盖，而是完整保留并生成冲突诊断。
- 纯解析核心与文件系统适配分离，既可作为 MoonBit 库复用，也可作为 CLI 使用。
- 默认不执行第三方代码，不把“扫描成功”误写为“项目运行成功”。

## 当前能力

当前版本支持 Node.js、Python、Rust、MoonBit、Docker 和 Compose 的根目录显式入口。输出提供 JSON 与 Markdown 两种格式，并以公开 JSON Schema 固定机器接口。自动化测试覆盖锁文件选择、行号证据、PEP 621 脚本、损坏 JSON、多生态冲突和空仓库。

## 验证方式

```text
moon fmt --check
moon check --deny-warn
moon test --deny-warn
moon run cmd/main -- examples/mixed-app
```

固定示例应输出两个 `pnpm` 脚本候选和一个 Docker 候选，同时报告 `multiple-entrypoints`；每个候选都应指向准确证据行。

## 许可证

项目采用 Apache-2.0 许可证。
