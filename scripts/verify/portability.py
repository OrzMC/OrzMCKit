#!/usr/bin/env python3
"""跨平台可移植性静态检查（决策 D14：Swift CLI 收敛为唯一跨平台实现）。

**为什么有它**：Linux/Windows 上的平台缺口（`CryptoKit`、`FoundationNetworking`、写死的
`/usr/bin/*`）过去是「编译一次才发现一类」，每次都要等一轮 8 分钟的 CI。静态扫一遍是秒级，
可以把这类问题挡在提交之前（见 `docs/iteration-efficiency.md`）。

检查项（只看 `Sources/`，`Tests/` 单独扫 CryptoKit）：

1. `import CryptoKit` 没有 `#if canImport(CryptoKit)` 兜底 → Linux 上必定 `no such module`；
2. 文件用到 `URLSession`/`URLRequest`/`URLSessionConfiguration`/`URLSessionDownloadTask`/`URLProtocol`
   却没有 `canImport(FoundationNetworking)`；
3. 写死的系统工具绝对路径（`/usr/bin/*`、`/bin/*`）没有走 `PlatformTools`／允许清单；
4. `#if !os(Windows)` / `#if os(Windows)` 之外的 `WinSDK` 假设（预留：Windows 阶段启用）。

用法:
    python3 scripts/verify/portability.py            # 检查(有违规 → 退出 1)
    python3 scripts/verify/portability.py --list     # 只列出扫描面
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

SOURCES = [ROOT / "Sources", ROOT / "Tests"]

# 允许写死绝对路径的文件（每处都要有理由）。
ABS_PATH_ALLOW = {
    # 自升级脚本固定走 POSIX sh；macOS/Linux 都有。
    "Sources/OrzMC/SelfUpdate.swift": {"/bin/sh"},
    # 测试夹具：这些路径只作为字符串数据参与断言，不会被本机执行。
    "Tests/OrzMCTests/CapabilityTests.swift": {"/bin/zsh", "/bin/tcsh"},
}

NETWORKING_SYMBOLS = re.compile(
    r"\b(URLSession|URLRequest|URLSessionConfiguration|URLSessionDownloadTask|URLSessionTask|URLProtocol)\b"
)
NETWORKING_GUARD = "canImport(FoundationNetworking)"
CRYPTO_GUARD = "canImport(CryptoKit)"
ABS_PATH = re.compile(r'"(/(?:usr/)?bin/[A-Za-z0-9_.-]+)"')


class Violation:
    def __init__(self, path: Path, line: int, rule: str, detail: str) -> None:
        self.path = path
        self.line = line
        self.rule = rule
        self.detail = detail

    def __str__(self) -> str:
        rel = self.path.relative_to(ROOT)
        return f"{rel}:{self.line}: [{self.rule}] {self.detail}"


def iter_swift_files() -> list[Path]:
    files: list[Path] = []
    for base in SOURCES:
        if not base.exists():
            continue
        files.extend(sorted(base.rglob("*.swift")))
    return files


def check_crypto_kit(path: Path, text: str) -> list[Violation]:
    out: list[Violation] = []
    lines = text.splitlines()
    for index, line in enumerate(lines, start=1):
        if not re.match(r"\s*import CryptoKit\b", line):
            continue
        # 前面 4 行内要有 canImport(CryptoKit) 的条件编译兜底。
        window = "\n".join(lines[max(0, index - 4) : index])
        if CRYPTO_GUARD not in window:
            out.append(
                Violation(path, index, "crypto-kit", "`import CryptoKit` 需要 `#if canImport(CryptoKit)` 兜底（Linux 无此模块）")
            )
    return out


def check_foundation_networking(path: Path, text: str) -> list[Violation]:
    if not NETWORKING_SYMBOLS.search(text):
        return []
    if NETWORKING_GUARD in text:
        return []
    match = NETWORKING_SYMBOLS.search(text)
    line = text[: match.start()].count("\n") + 1 if match else 1
    return [
        Violation(
            path,
            line,
            "foundation-networking",
            "用到 URLSession/URLRequest 却没有 `#if canImport(FoundationNetworking) import FoundationNetworking #endif`",
        )
    ]


def check_abs_paths(path: Path, text: str) -> list[Violation]:
    rel = str(path.relative_to(ROOT))
    allowed = ABS_PATH_ALLOW.get(rel, set())
    # 整文件 macOS 限定的（`#if os(macOS)`）用 macOS 专属工具是合法的。
    if "#if os(macOS)" in text:
        return []
    out: list[Violation] = []
    for index, line in enumerate(text.splitlines(), start=1):
        for hit in ABS_PATH.findall(line):
            if hit in allowed:
                continue
            out.append(
                Violation(
                    path,
                    index,
                    "abs-path",
                    f"写死系统工具路径 {hit}；应走 `Game.PlatformTools` 或加入 `ABS_PATH_ALLOW`（附理由）",
                )
            )
    return out


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="跨平台可移植性检查（D14）")
    parser.add_argument("--list", action="store_true", help="只列出扫描面（不做检查）")
    args = parser.parse_args(argv)

    files = iter_swift_files()
    if args.list:
        for path in files:
            print(path.relative_to(ROOT))
        print(f"\n共 {len(files)} 个 Swift 文件", file=sys.stderr)
        return 0

    violations: list[Violation] = []
    for path in files:
        text = path.read_text(encoding="utf-8")
        violations.extend(check_crypto_kit(path, text))
        violations.extend(check_foundation_networking(path, text))
        violations.extend(check_abs_paths(path, text))

    if violations:
        print(f"发现 {len(violations)} 处跨平台隐患：\n", file=sys.stderr)
        for item in violations:
            print(f"  {item}", file=sys.stderr)
        print(
            "\n提示：`CryptoKit` → `#if canImport(CryptoKit) import CryptoKit #elseif canImport(Crypto) import Crypto #endif`；"
            "`URLSession` → 条件导入 `FoundationNetworking`；系统工具 → `Game.PlatformTools`。",
            file=sys.stderr,
        )
        return 1

    print(f"[ok] 跨平台可移植性检查通过（{len(files)} 个文件）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
