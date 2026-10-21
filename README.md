# OrzMCKit

> ⚠️ **实验性项目 / 不对外分发**：本仓库的 `orzmc` CLI 与 [Python 实现](https://github.com/OrzMC/OrzPythonMC)**同步迭代**（命令面与行为对齐），但它**不是对外分发的实现** —— Release 一律标 **pre-release**、不宣传，
> 仅作为 Swift 生态的实现样例与跨平台能力探索。普通用户请用 Python 实现（PyPI / 一键安装器）。

Swift 工具集与 `orzmc` CLI：Minecraft 客户端启动 / 服务端部署的**跨平台实现**
（macOS / Linux / Windows；Linux 资产自包含、glibc ≥ 2.35）。

- **引擎库**：`Game`（版本解析、规范布局、下载、托管 JRE、受管进程、启动计划）、`Fabric`。
- **可执行**：`orzmc` CLI（与 [Python 实现 `orzmc`](https://github.com/OrzMC/OrzPythonMC) 共用
  同一套[命令面规范](https://github.com/OrzMC/OrzMC/blob/main/docs/spec/cli-surface.md)与
  [一致性套件](https://github.com/OrzMC/OrzMC/blob/main/docs/spec/conformance.md)）。
- **一致性适配器**：`ConformanceAdapter`（驱动父仓库 `docs/spec/fixtures` 黄金样例）。

> 父仓库 [OrzMC](https://github.com/OrzMC/OrzMC) 是产品伞：规范、发版组合、跨仓协调都在那里。

## Install

> **仅维护者/实验者**：下面的安装器默认从本仓库的 Release 装 —— 而 Release 现在是 **pre-release**，
> 安装器需要显式给版本（`-version vX.Y.Z` / `--version vX.Y.Z`）。普通用户请装
> [Python 实现](https://github.com/OrzMC/OrzPythonMC)。


macOS / Linux（用户级，免 sudo）：

```sh
curl -fsSL https://raw.githubusercontent.com/OrzMC/OrzMCKit/main/scripts/install.sh | sh
```

Windows（PowerShell 5.1+，用户级）：

```powershell
irm https://raw.githubusercontent.com/OrzMC/OrzMCKit/main/scripts/install.ps1 | iex
# 指定版本（绕过 GitHub API 限流）：
#   $code = (irm https://raw.githubusercontent.com/OrzMC/OrzMCKit/main/scripts/install.ps1)
#   & ([scriptblock]::Create($code)) -version vX.Y.Z
# 卸载：& ([scriptblock]::Create($code)) -uninstall
```

安装器会把二进制放到 `${XDG_BIN_HOME:-$HOME/.local/bin}`（Windows：`%LOCALAPPDATA%\Programs\orzmc`）、
配置 PATH 与补全，并写入状态目录下的 `install.conf`（契约见父仓库
[`docs/spec/install-update.md`](https://github.com/OrzMC/OrzMC/blob/main/docs/spec/install-update.md)）。

手动安装：从 [Releases](https://github.com/OrzMC/OrzMCKit/releases) 下载对应平台的资产——

| 平台 | 资产 | 用法 |
|---|---|---|
| macOS | `orzmc-macos-{arm64,x86_64}` | `chmod +x` 后放入 PATH |
| Linux | `orzmc-linux-{arm64,x86_64}` | 同上 |
| Windows | `orzmc-windows-{x86_64,arm64}.zip` | 解压到同一目录（exe + Swift 运行时 DLL），把目录加入 PATH |

Windows 的 zip 形状是必须的：`--static-swift-stdlib` 在 Windows 上不生效，单 exe 在没装 Swift
的机器上会 `STATUS_DLL_NOT_FOUND`。校验用同一 Release 里的 `SHA256SUMS`。

## Usage

```sh
orzmc --help                 # 命令总览
orzmc version                # 工具版本（或全局 orzmc --version）
orzmc client -v 1.20.4       # 启动客户端（缺失文件自动下载）
orzmc server -t vanilla -v 1.20.4 --nogui   # 部署并启动服务端
orzmc list                   # 已安装版本
orzmc remove -v 1.20.4       # 移除版本(脚本里需加 --yes)
orzmc backup -v 1.20.4       # 备份服务端世界
orzmc plugin --search luckperms             # Hangar 搜索插件
orzmc completion install     # 按 $SHELL 安装补全(zsh/bash/fish;幂等)
orzmc completion zsh > ~/.zsh/completions/_orzmc   # 或只打印脚本自己装
```

每个子命令都支持 `--help` / `-h`。**破坏性操作**(`remove` / `uninstall` / `app uninstall`)
在非交互环境(脚本 / 管道 / `--json`)必须显式 `--yes`,否则按规范返回取消并退出 **130**。

全局选项（须在子命令**之前**）：

```sh
orzmc --verbose --root-dir ~/mc client -v 1.20.4
orzmc --json list            # 机器可读信封 {ok,command,data,error}（AI/脚本）
```

## Versioning & releases

- 工具版本单一事实源：`Sources/Game/OrzMCVersion.swift`；
  `--version` / `version` / `--json` 信封都读它。
- 发版走 Conventional Commits + [release-please](https://github.com/googleapis/release-please)：
  合并 release PR 自动打 tag `vX.Y.Z` 并触发 [`release.yml`](.github/workflows/release.yml)
  构建 macOS / Linux / Windows（x64 + **arm64**）资产、校验自报版本、挂到 GitHub Release。
- **护栏**：tag 必须等于代码里的版本，且必须落在 `main` 上。

## Development

```sh
swift build
swift test

# CLI 行为验收（真实进程；CI 同款；与 Python 侧跑的是**同一份**父仓库脚本）
swift build -c debug --product orzmc
python3 <path-to-parent>/scripts/accept/cli.py --cli "$(swift build -c debug --show-bin-path)/orzmc"

# 一致性套件（需父仓库 fixtures；CI 同款）
swift build -c debug --product ConformanceAdapter
python3 ../OrzMC/scripts/conformance/run.py \
  --adapter "$(swift build -c debug --show-bin-path)/ConformanceAdapter" --strict
```

---

<!-- ORZMC:COMPLIANCE:BEGIN (auto-generated; do not edit by hand. Single source: docs/compliance/ + scripts/sync_compliance.py in the OrzMC/OrzMC umbrella repo) -->
> **NOT AN OFFICIAL MINECRAFT PRODUCT. NOT APPROVED BY OR ASSOCIATED WITH MOJANG OR MICROSOFT.**
>
> OrzMC 是独立的社区开源项目，与 Mojang / Microsoft 无隶属、赞助或背书关系，对本项目负责。
>
> “Minecraft”名称、品牌与素材的一切权利归 Mojang / Microsoft 所有。
>
> 联系：[GitHub 组织](https://github.com/OrzMC) ｜ 隐私政策：https://orzmc.jokerhub.cn/privacy/
<!-- ORZMC:COMPLIANCE:END -->
