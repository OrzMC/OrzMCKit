# Changelog

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
