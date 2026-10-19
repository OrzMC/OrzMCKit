# Changelog

## [0.17.0](https://github.com/OrzMC/OrzMCKit/compare/v0.16.0...v0.17.0) (2026-10-19)


### Features

* **m2:** 验收脚本收敛到父仓库一份 + 修共享判据抓出的 3 个真 bug ([#76](https://github.com/OrzMC/OrzMCKit/issues/76)) ([acd99d4](https://github.com/OrzMC/OrzMCKit/commit/acd99d4d15448e2a41eb161c2cab6bbfade0d064))

## [0.16.0](https://github.com/OrzMC/OrzMCKit/compare/v0.15.0...v0.16.0) (2026-10-19)


### ⚠️ 升级须知（Windows 资产是 zip / 发布链路已加固）

- **Windows 用安装器整包安装**（`orzmc-windows-<arch>.zip` = exe + Swift 运行时 DLL），
  只下 exe 在没装 Swift 的机器上会 `STATUS_DLL_NOT_FOUND`。
- PowerShell 补全按 F6 不落盘：`orzmc completion powershell` 追加到 `$PROFILE`。
- `orzmc app …` 是 macOS 专属；Windows/Linux 返回 `E_UNSUPPORTED`。
- 发布链路新增 **dry-run**（发版前排雷）与发布后 Linux 资产自动验收。

### Features

* **release:** dry-run 支持「打 tag 之前」跑（用源码版本），构建断言改用 verify 输出的 tag ([#73](https://github.com/OrzMC/OrzMCKit/issues/73)) ([6443dbc](https://github.com/OrzMC/OrzMCKit/commit/6443dbc1e1e16ffffabe104f1eedbc6ddef72f63))
* **windows:** 发布形态改为 zip（exe + 运行时 DLL）；安装器解压；自升级从 zip 取 exe ([#69](https://github.com/OrzMC/OrzMCKit/issues/69)) ([3acc636](https://github.com/OrzMC/OrzMCKit/commit/3acc636b75a48cb66ea3d4d87956975846bd9329))


### Bug Fixes

* **release:** build-windows 的版本断言也改用 verify 输出的 tag（dry-run 前会拿到 main 而假失败） ([#75](https://github.com/OrzMC/OrzMCKit/issues/75)) ([8e77516](https://github.com/OrzMC/OrzMCKit/commit/8e775161e201a9cddbb9dd6f36afba35221b1fd2))
* **release:** tag 输入改为可选（dry-run 不填），正式发布缺 tag 时明确报错 ([#74](https://github.com/OrzMC/OrzMCKit/issues/74)) ([076b3d4](https://github.com/OrzMC/OrzMCKit/commit/076b3d442911ae07006283fb25265eaaeba430f5))
* **windows:** 资产名改为 orzmc-windows-x86_64.zip（内容已是 zip，名字没跟上） ([#70](https://github.com/OrzMC/OrzMCKit/issues/70)) ([ffa46d3](https://github.com/OrzMC/OrzMCKit/commit/ffa46d3e017f2c5d51ac59aa767b38df0f33d647))
* **windows:** 静态链接 Swift 运行时（用户机器无 Swift → STATUS_DLL_NOT_FOUND），并用干净 PATH 验证 ([#67](https://github.com/OrzMC/OrzMCKit/issues/67)) ([6a12131](https://github.com/OrzMC/OrzMCKit/commit/6a1213153cb3966832c97801bf9872e2f6b60b6a))

## [0.15.0](https://github.com/OrzMC/OrzMCKit/compare/v0.14.0...v0.15.0) (2026-10-18)


### ⚠️ 升级须知（Windows 首次可用 / 资产是 zip）

- **Windows 现在有官方产物**：`orzmc-windows-x86_64.zip`（exe + Swift 运行时 DLL，约 33 MB）。
  单 exe 在没装 Swift 的机器上会 `STATUS_DLL_NOT_FOUND`；请用安装器整包安装：
  `irm https://raw.githubusercontent.com/OrzMC/OrzMCKit/main/scripts/install.ps1 | iex`。
- **PowerShell 补全按规范 F6 不落盘**：把 `orzmc completion powershell` 追加到 `$PROFILE`。
- `orzmc app …` 是 macOS 专属；Windows/Linux 上返回 `E_UNSUPPORTED`。
- Linux / macOS 升级方式不变（`orzmc update --yes` 或重跑一键安装器）。

### Features

* **dx:** 本机 Swift 6 快速迭代脚本 + 秒级 portability 快车道 ([#62](https://github.com/OrzMC/OrzMCKit/issues/62)) ([260b845](https://github.com/OrzMC/OrzMCKit/commit/260b8454fde8405462cc9b4f7fd408567c2ba099))
* **linux:** Linux 收尾——发布链路修复 + 秒级可移植性检查 + 本地容器迭代 ([#59](https://github.com/OrzMC/OrzMCKit/issues/59)) ([3525a64](https://github.com/OrzMC/OrzMCKit/commit/3525a644ff2d8b6965befaf7139490ab18886b39))
* **linux:** 安装器支持 Linux + 发布后自动验收(资产/安装/补全/卸载) ([#61](https://github.com/OrzMC/OrzMCKit/issues/61)) ([1242479](https://github.com/OrzMC/OrzMCKit/commit/124247927c2aad27f3cb377a509fd92b83137ac8))
* **windows:** W3/W4/W5——自升级/解压打包/安装器按平台 ([#65](https://github.com/OrzMC/OrzMCKit/issues/65)) ([b3c33cc](https://github.com/OrzMC/OrzMCKit/commit/b3c33cc724531900157b3f60e82556769db10ae7))
* **windows:** W6——CI 加 windows job（build+冒烟），发布出 orzmc-windows-x86_64.exe ([#64](https://github.com/OrzMC/OrzMCKit/issues/64)) ([28bf1b3](https://github.com/OrzMC/OrzMCKit/commit/28bf1b386d59bfe2e11eaf6123ce2cab090a4fb8))
* **windows:** Windows 第一步——编译打通 + W1 补全函数名 + W2 状态目录 ([#63](https://github.com/OrzMC/OrzMCKit/issues/63)) ([b809aa2](https://github.com/OrzMC/OrzMCKit/commit/b809aa253b4e172cd7605b7b98775b2634159847))

## [0.14.0](https://github.com/OrzMC/OrzMCKit/compare/v0.13.0...v0.14.0) (2026-10-18)


### Features

* **linux:** Swift CLI 跨平台第一步——Linux 编译/单测/验收全绿 + Linux 发布资产 ([#57](https://github.com/OrzMC/OrzMCKit/issues/57)) ([bbed961](https://github.com/OrzMC/OrzMCKit/commit/bbed961ac55daddc2359413a0fa7c82e5a1af1b9))

## [0.13.0](https://github.com/OrzMC/OrzMCKit/compare/v0.12.0...v0.13.0) (2026-10-17)


### ⚠️ 升级须知（脚本调用需加 --yes / 补全行为变化）

- 脚本里调用 **`orzmc remove` / `orzmc uninstall` / `orzmc app uninstall` 现在必须显式 `--yes`**，
  否则按规范返回取消并退出 **130**（以前非交互会直接执行）。
- `completion install` 在 **PowerShell** 下明确返回「不支持自动安装补全」（规范 F6：只生成脚本）。
  请用 `orzmc completion powershell` 把脚本加入 `$PROFILE`。
- `completion install` 现在会把补全路径登记进 `install.conf` 的 `completion_file`，
  `orzmc uninstall` 会一并清理；`completion <shell>` 的 `shell` 字段回显请求值（`pwsh` 不再折叠）。
- 安装器新增 `ORZMC_NO_COMPLETION=1`：安装时不装补全。

### Features

* **cli:** 对齐 CLI 契约 0.2（非交互取消 / 补全 hint 与 E_USAGE / CLI 验收） ([#56](https://github.com/OrzMC/OrzMCKit/issues/56)) ([e96de48](https://github.com/OrzMC/OrzMCKit/commit/e96de486ff0bbb5a4b2bd5a7c10bcb15925621ac))
* **install:** InstallManifest 下沉到 Game（公开）+ 安装器写 surface ([#54](https://github.com/OrzMC/OrzMCKit/issues/54)) ([329230f](https://github.com/OrzMC/OrzMCKit/commit/329230f03f4327aa453fb530d52597ba15b71d1e))

## [0.12.0](https://github.com/OrzMC/OrzMCKit/compare/v0.11.1...v0.12.0) (2026-10-17)


### Features

* **engine:** 结构化进度出口 LaunchProgress + 服务端统一进度观察者 ([adca8b3](https://github.com/OrzMC/OrzMCKit/commit/adca8b365c9dd66c17bfd36e704885188c757c82))
* **engine:** 结构化进度出口 LaunchProgress（GUI 适配 Phase A） ([0d36e26](https://github.com/OrzMC/OrzMCKit/commit/0d36e26da5e41adbf70ade3795176c76de7a3067))

## [0.11.1](https://github.com/OrzMC/OrzMCKit/compare/v0.11.0...v0.11.1) (2026-10-17)


### Bug Fixes

* **cli:** server --type 帮助文本补齐 fabric/forge（0.11.0 已支持） ([#50](https://github.com/OrzMC/OrzMCKit/issues/50)) ([ecc2a9b](https://github.com/OrzMC/OrzMCKit/commit/ecc2a9b3974d98647682390c04c4d8d66e65219c))

## [0.11.0](https://github.com/OrzMC/OrzMCKit/compare/v0.10.0...v0.11.0) (2026-10-17)


### Features

* **cli:** capabilities 上报枚举 + fish/PowerShell 补全；update 护栏对齐 Python ([#47](https://github.com/OrzMC/OrzMCKit/issues/47)) ([9f91bee](https://github.com/OrzMC/OrzMCKit/commit/9f91beebb74659e04107822be91b3641cc903d2e))
* **server:** 支持 fabric / forge 服务端 ([#46](https://github.com/OrzMC/OrzMCKit/issues/46)) ([04df994](https://github.com/OrzMC/OrzMCKit/commit/04df994501e70d8a3cffd906b8e10ceab7fb4535))
* 对齐 B8 结构化进度与 B10 版本选择器（release/snapshot + 搜索） ([#49](https://github.com/OrzMC/OrzMCKit/issues/49)) ([71cbf44](https://github.com/OrzMC/OrzMCKit/commit/71cbf4464c54d94d19c32356e359936e0ceed8d8))

## [0.10.0](https://github.com/OrzMC/OrzMCKit/compare/v0.9.1...v0.10.0) (2026-10-17)


### ⚠️ 升级须知（卸载命令改名）

「卸载工具自身」的子命令由 `self-uninstall` 改名为 **`uninstall`**（`remove` 仍是移除 Minecraft 版本，语义不变）：

- 旧名 `self-uninstall` **已不存在**，请改用 `orzmc uninstall`（选项不变：`--yes` / `--remove-root` / `--force`）；
- 若脚本 / 文档里写了 `orzmc self-uninstall`，请替换为 `orzmc uninstall`；
- 规范（`docs/spec/cli-surface.json`）与两套实现（Python / Swift CLI）已同步；Swift 类型 `SelfUninstallCommand` → `UninstallCommand`。


### Features

* **cli:** 卸载命令 self-uninstall → uninstall（规范先行） ([#45](https://github.com/OrzMC/OrzMCKit/issues/45)) ([f277e4f](https://github.com/OrzMC/OrzMCKit/commit/f277e4f52d7f81019058aeea9107fa4d2169dfd7))


### Bug Fixes

* **cli:** 版本声明改多行、去联系邮箱（合规单一事实源生成） ([#43](https://github.com/OrzMC/OrzMCKit/issues/43)) ([a1af7c5](https://github.com/OrzMC/OrzMCKit/commit/a1af7c59998e6c322461f25f4cdfbd012d51e7fc))

## [0.9.1](https://github.com/OrzMC/OrzMCKit/compare/v0.9.0...v0.9.1) (2026-10-16)


### Performance Improvements

* 跟进 OrzSwiftKit 去掉编译期 SwiftLint（Package.resolved）+ runner 护栏注释 ([#40](https://github.com/OrzMC/OrzMCKit/issues/40)) ([f8e4f26](https://github.com/OrzMC/OrzMCKit/commit/f8e4f2607f5f200412a11a9bdb1b45286c90c79a))
* 跟进 OrzSwiftKit 预编译 SwiftLint（插件回归，本地/CI 自动 lint；Package.resolved） ([#42](https://github.com/OrzMC/OrzMCKit/issues/42)) ([f983847](https://github.com/OrzMC/OrzMCKit/commit/f98384799ae2db3e3ef1f5b3a2ad52a3c9350940))

## [0.9.0](https://github.com/OrzMC/OrzMCKit/compare/v0.8.0...v0.9.0) (2026-10-16)


### Features

* Mojang 元数据缓存指向游戏根目录 cache（与 Python / app 共享） ([#36](https://github.com/OrzMC/OrzMCKit/issues/36)) ([70c62b0](https://github.com/OrzMC/OrzMCKit/commit/70c62b0d2ce993eadd8f3b07c84e5ab39715b62f))

## [0.8.0](https://github.com/OrzMC/OrzMCKit/compare/v0.7.0...v0.8.0) (2026-10-16)


### Features

* **client:** 支持 --type forge（官方安装器 + patched client jar） ([#33](https://github.com/OrzMC/OrzMCKit/issues/33)) ([b92e497](https://github.com/OrzMC/OrzMCKit/commit/b92e497fbf0dc5e9d2a39c96259d78c07c5ab686))

## [0.7.0](https://github.com/OrzMC/OrzMCKit/compare/v0.6.0...v0.7.0) (2026-10-16)


### Features

* **client:** 支持 --type fabric（fabric-meta 解析） ([#31](https://github.com/OrzMC/OrzMCKit/issues/31)) ([ba585ac](https://github.com/OrzMC/OrzMCKit/commit/ba585ace7876c8519a355672e0fb928dba9427f2))

## [0.6.0](https://github.com/OrzMC/OrzMCKit/compare/v0.5.0...v0.6.0) (2026-10-15)


### Features

* **auth:** AuthConfig 内置 Azure 应用 client_id（公共客户端） ([#27](https://github.com/OrzMC/OrzMCKit/issues/27)) ([08d9c0e](https://github.com/OrzMC/OrzMCKit/commit/08d9c0e66affbe412fa75d1ef2d8d253dbcf9f92))

## [0.5.0](https://github.com/OrzMC/OrzMCKit/compare/v0.4.0...v0.5.0) (2026-10-15)


### Features

* client --extract-music / --download-threads + server --download-threads ([#24](https://github.com/OrzMC/OrzMCKit/issues/24)) ([d372bc1](https://github.com/OrzMC/OrzMCKit/commit/d372bc17c70be9134f752ec2300bdbe194defd0b))

## [0.4.0](https://github.com/OrzMC/OrzMCKit/compare/v0.3.0...v0.4.0) (2026-10-15)


### Features

* server/client --refresh + server --symlink/--force-download ([#22](https://github.com/OrzMC/OrzMCKit/issues/22)) ([8f0160a](https://github.com/OrzMC/OrzMCKit/commit/8f0160a452f6ab7f63ad5c0d5574831514cbefa1))

## [0.3.0](https://github.com/OrzMC/OrzMCKit/compare/v0.2.0...v0.3.0) (2026-10-15)


### Features

* server --print-jar-help 改名 + client --jvm-opts ([#20](https://github.com/OrzMC/OrzMCKit/issues/20)) ([0df2feb](https://github.com/OrzMC/OrzMCKit/commit/0df2feb44fd95e414fcc1c3e993f000c66a83b2e))

## [0.2.0](https://github.com/OrzMC/OrzMCKit/compare/v0.1.0...v0.2.0) (2026-10-15)


### Features

* --auth 离线链路 + orzmc mcp + 命令面收敛与一致性适配 ([#19](https://github.com/OrzMC/OrzMCKit/issues/19)) ([e237d32](https://github.com/OrzMC/OrzMCKit/commit/e237d32e70b716dc5b914e8e79e5c2217cbabc9f))
* **conformance:** planClientDownload 支持 legacy natives + Maven 回退 ([#18](https://github.com/OrzMC/OrzMCKit/issues/18)) ([599616b](https://github.com/OrzMC/OrzMCKit/commit/599616baa42896b92001c2528db0c08a01893aa3))
* **conformance:** 实现 planClientDownload（引擎纯计划 + 适配器） ([#15](https://github.com/OrzMC/OrzMCKit/issues/15)) ([064bca1](https://github.com/OrzMC/OrzMCKit/commit/064bca179b0d565d114f4e2d8d4563caf0f7702f))

## [0.1.0](https://github.com/OrzMC/OrzMCKit/compare/v0.0.6...v0.1.0) (2026-10-14)


### Features

* **cli:** app 命令（跨面安装/打开/卸载 GUI 应用） ([#11](https://github.com/OrzMC/OrzMCKit/issues/11)) ([33504ac](https://github.com/OrzMC/OrzMCKit/commit/33504ac6bc528960312890a49aade5304534ec7c))
* **cli:** capabilities 命令 + fabric 隐藏别名 ([#9](https://github.com/OrzMC/OrzMCKit/issues/9)) ([c4ec57f](https://github.com/OrzMC/OrzMCKit/commit/c4ec57f94fb46473ea6c34479c8adbf9aa25f0ea))
* **cli:** completion 命令（ConsoleKit 原生 bash/zsh + install） ([#7](https://github.com/OrzMC/OrzMCKit/issues/7)) ([c275996](https://github.com/OrzMC/OrzMCKit/commit/c2759964294c381b23115fe59175187d21eeffaa))
* **cli:** update / self-uninstall 命令（发行产品生命周期） ([#10](https://github.com/OrzMC/OrzMCKit/issues/10)) ([586cc60](https://github.com/OrzMC/OrzMCKit/commit/586cc605ba8c5a120ac42a12adaf247617b043f4))


### Bug Fixes

* **cli:** 用户取消(E_CANCELLED)退出码改为 130(规范 §6) ([#12](https://github.com/OrzMC/OrzMCKit/issues/12)) ([998cdc0](https://github.com/OrzMC/OrzMCKit/commit/998cdc0b8250c4c5f6eef14dfb15616fb22d6fa9))

## Changelog
