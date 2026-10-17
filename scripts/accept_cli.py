#!/usr/bin/env python3
"""orzmc CLI 行为验收(Swift 实现侧;契约见父仓库 `docs/spec/conformance.md` §12)。

与 Python 侧 `orzmc-app` 的 `scripts/accept_cli.py` **分组与断言语义一致**:
按规范(`cli-surface.md` §4/§6/§7/§9、`behavior.md` B9/B11、`frontends.md` F2/F6)
对**真实子进程**断言,而不是按实现断言。

用法::

    swift build -c debug --product orzmc
    python3 scripts/accept_cli.py                       # 默认 .build/debug/orzmc
    python3 scripts/accept_cli.py --cli /tmp/orzmc       # 指定被测二进制
    python3 scripts/accept_cli.py --list-cases
    python3 scripts/accept_cli.py --only completion,frozen
    python3 scripts/accept_cli.py --network             # 追加联网用例

设计约束(与 Python 侧一致):
- 只用标准库;每个用例一个隔离沙箱(HOME / XDG_* / 游戏根),不碰真实配置;
- 一律 `stdin=DEVNULL` + 超时 ——「非交互不阻塞」本身是被测行为;
- 断言取自规范;规范变了先改断言,再改实现。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import traceback
from collections.abc import Callable, Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

#: 规范命令集(规范 §2)。
EXPECTED_COMMANDS = (
    "client",
    "server",
    "plugin",
    "list",
    "remove",
    "backup",
    "update",
    "uninstall",
    "app",
    "completion",
    "capabilities",
    "mcp",
    "version",
)

#: MCP 不暴露的元 / 自毁命令(规范 §8.2)。
MCP_EXCLUDED = {"capabilities", "completion", "mcp", "uninstall"}

#: 规范 §9 的补全 shell。
COMPLETION_SHELLS = ("bash", "zsh", "fish", "powershell", "pwsh")


# ── 基础设施 ────────────────────────────────────────────────────────────────


class CheckError(AssertionError):
    """断言失败(带上下文,便于定位)。"""


class SkipCase(Exception):
    """前置条件不满足:记 SKIP,不算失败。"""


def skip(reason: str) -> None:
    raise SkipCase(reason)


def check(condition: object, message: str) -> None:
    if not condition:
        raise CheckError(message)


@dataclass
class Result:
    args: list[str]
    returncode: int
    stdout: str
    stderr: str
    duration: float = 0.0

    @property
    def combined(self) -> str:
        return self.stdout + self.stderr

    def describe(self) -> str:
        return (
            f"$ orzmc {' '.join(self.args)}\n"
            f"  rc={self.returncode}\n"
            f"  stdout={self.stdout.strip()[:2000]!r}\n"
            f"  stderr={self.stderr.strip()[:2000]!r}"
        )


class Sandbox:
    """一次验收的隔离环境:独立 HOME / XDG / 游戏根 + 干净的环境变量。"""

    def __init__(self, cli: Sequence[str], *, timeout: float) -> None:
        self.cli = list(cli)
        self.timeout = timeout
        self._tmp = tempfile.TemporaryDirectory(prefix="orzmc-swift-accept-")
        self.dir = Path(self._tmp.name)
        self.home = self.dir / "home"
        self.root = self.dir / "mc"
        for path in (self.home, self.root):
            path.mkdir(parents=True, exist_ok=True)
        self.env = self._clean_env()

    def _clean_env(self) -> dict[str, str]:
        env = {key: value for key, value in os.environ.items() if not key.startswith("ORZMC_")}
        env.update(
            {
                "HOME": str(self.home),
                "XDG_STATE_HOME": str(self.dir / "state"),
                "XDG_DATA_HOME": str(self.dir / "data"),
                "XDG_CONFIG_HOME": str(self.dir / "config"),
                "XDG_CACHE_HOME": str(self.dir / "cache"),
                "NO_COLOR": "1",
                "TERM": "dumb",
            }
        )
        # Swift 实现只在 macOS 发布;`$SHELL` 是它判断补全落点的唯一输入。
        env["SHELL"] = "/bin/bash"
        return env

    def run(
        self,
        *args: str,
        env: dict[str, str] | None = None,
        drop_env: Iterable[str] = (),
        stdin: str | None = None,
        timeout: float | None = None,
    ) -> Result:
        run_env = dict(self.env)
        run_env.update(env or {})
        for key in drop_env:
            run_env.pop(key, None)
        started = time.monotonic()
        completed = subprocess.run(
            [*self.cli, *args],
            input=stdin,
            stdin=None if stdin is not None else subprocess.DEVNULL,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=run_env,
            cwd=str(self.dir),
            timeout=self.timeout if timeout is None else timeout,
        )
        return Result(
            list(args),
            completed.returncode,
            completed.stdout,
            completed.stderr,
            time.monotonic() - started,
        )

    def cleanup(self) -> None:
        self._tmp.cleanup()


@dataclass
class Context:
    sandbox: Sandbox
    verbose: bool


# ── 通用断言 ────────────────────────────────────────────────────────────────


def no_crash(result: Result) -> None:
    """任何路径都不许把 Swift 运行时错误/栈泄漏给用户。"""
    for needle in ("Fatal error", "Traceback (most recent call last)", "Unhandled error", "precondition failed"):
        check(needle not in result.combined, f"出现未捕获错误({needle}):\n" + result.describe())


def envelope(result: Result) -> dict[str, object]:
    """规范 §6.1:`--json` 下 stdout **恰好一个** JSON 对象。"""
    text = result.stdout.strip()
    check(bool(text), "stdout 为空,期望 JSON 信封:\n" + result.describe())
    try:
        payload = json.loads(text)
    except json.JSONDecodeError as exc:
        raise CheckError(f"stdout 不是单个 JSON 对象({exc}):\n" + result.describe()) from None
    check(isinstance(payload, dict), f"信封必须是对象:\n{result.describe()}")
    for key in ("ok", "command", "data", "error"):
        check(key in payload, f"信封缺字段 {key}:\n{result.describe()}")
    check(isinstance(payload["ok"], bool), f"ok 必须是 bool:\n{result.describe()}")
    check("\x1b" not in result.stdout, "JSON stdout 里混入了 ANSI 转义序列:\n" + result.describe())
    return payload


def expect_ok(result: Result, command: str) -> dict[str, object]:
    payload = envelope(result)
    check(payload["command"] == command, f"信封 command 应为 {command}:\n{result.describe()}")
    check(payload["ok"] is True, f"期望成功:\n{result.describe()}")
    check(payload["error"] is None, f"成功时 error 必须为 null:\n{result.describe()}")
    check(result.returncode == 0, f"成功时退出码必须是 0:\n{result.describe()}")
    return payload


def expect_error(result: Result, command: str, code: str | None = None) -> dict[str, object]:
    payload = envelope(result)
    check(payload["command"] == command, f"信封 command 应为 {command}:\n{result.describe()}")
    check(payload["ok"] is False, f"期望失败:\n{result.describe()}")
    check(payload["data"] is None, f"失败时 data 必须为 null:\n{result.describe()}")
    error = payload["error"]
    check(isinstance(error, dict), f"error 必须是对象:\n{result.describe()}")
    assert isinstance(error, dict)
    check(isinstance(error.get("code"), str), f"error.code 必须是字符串:\n{result.describe()}")
    check(isinstance(error.get("message"), str) and error["message"], f"error.message 不能为空:\n{result.describe()}")
    if code is not None:
        check(error["code"] == code, f"期望错误码 {code},实际 {error['code']}:\n{result.describe()}")
    expected_rc = 130 if error["code"] == "E_CANCELLED" else 1
    check(result.returncode == expected_rc, f"{error['code']} 的退出码应为 {expected_rc}:\n" + result.describe())
    return payload


# ── 用例注册 ────────────────────────────────────────────────────────────────


@dataclass
class Case:
    group: str
    name: str
    func: Callable[[Context], None]
    network: bool = False


CASES: list[Case] = []


def case(group: str, name: str, *, network: bool = False) -> Callable:
    def register(func: Callable[[Context], None]) -> Callable[[Context], None]:
        CASES.append(Case(group, name, func, network=network))
        return func

    return register


# ── surface ────────────────────────────────────────────────────────────────


def _command_names(ctx: Context) -> list[str]:
    payload = expect_ok(ctx.sandbox.run("--json", "capabilities"), "capabilities")
    data = payload["data"]
    assert isinstance(data, dict)
    commands = data["commands"]
    assert isinstance(commands, list)
    return [str(item["name"]) for item in commands]


@case("surface", "no-args-prints-help")
def case_no_args(ctx: Context) -> None:
    result = ctx.sandbox.run()
    no_crash(result)
    check(result.returncode == 0, "无子命令必须打印帮助并退出 0(规范 §1):\n" + result.describe())
    for name in EXPECTED_COMMANDS:
        check(name in result.stdout, f"帮助里缺命令 {name}:\n" + result.describe())


@case("surface", "help-flags")
def case_help_flags(ctx: Context) -> None:
    for flag in ("-h", "--help"):
        result = ctx.sandbox.run(flag)
        no_crash(result)
        check(result.returncode == 0, f"{flag} 应退出 0(规范 §3):\n" + result.describe())
        check("Usage" in result.stdout or "用法" in result.stdout, f"{flag} 应打印用法:\n" + result.describe())


@case("surface", "help-every-command")
def case_help_every_command(ctx: Context) -> None:
    names = _command_names(ctx)
    check(set(EXPECTED_COMMANDS) <= set(names), f"capabilities 缺命令: {set(EXPECTED_COMMANDS) - set(names)}")
    for name in names:
        for flag in ("--help", "-h"):
            result = ctx.sandbox.run(name, flag)
            no_crash(result)
            check(result.returncode == 0, f"{name} {flag} 应退出 0:\n" + result.describe())


@case("surface", "version-subcommand-matches-flag")
def case_version_parity(ctx: Context) -> None:
    sub = ctx.sandbox.run("version")
    flag = ctx.sandbox.run("--version")
    no_crash(sub)
    no_crash(flag)
    check(sub.returncode == 0 and flag.returncode == 0, "version 与 --version 都必须成功")
    pattern = re.compile(r"(\d+\.\d+\.\d+)")
    sub_match = pattern.search(sub.stdout)
    flag_match = pattern.search(flag.stdout)
    check(sub_match is not None, "version 输出里没有版本号:\n" + sub.describe())
    check(flag_match is not None, "--version 输出里没有版本号:\n" + flag.describe())
    assert sub_match and flag_match
    check(sub_match.group(1) == flag_match.group(1), "version 与 --version 报的版本不一致")


@case("surface", "usage-errors-exit-1")
def case_usage_errors(ctx: Context) -> None:
    for args in (("nope",), ("--nope",), ("client", "--nope"), ("remove",)):
        result = ctx.sandbox.run(*args)
        no_crash(result)
        check(result.returncode == 1, f"用法错误应退出 1(规范 §6):\n{result.describe()}")
        check(result.stderr.strip() != "", f"用法错误信息应写 stderr:\n{result.describe()}")


@case("surface", "no-subcommand-json-is-usage-error")
def case_no_subcommand_json(ctx: Context) -> None:
    """`--json` 下 stdout 只能有信封:缺子命令按用法错误处理(§1/§6.1)。"""
    expect_error(ctx.sandbox.run("--json"), "_root", "E_USAGE")


@case("surface", "global-options-before-subcommand")
def case_global_option_placement(ctx: Context) -> None:
    ok = ctx.sandbox.run("--json", "--root-dir", str(ctx.sandbox.root), "list")
    expect_ok(ok, "list")
    bad = ctx.sandbox.run("list", "--json")
    no_crash(bad)
    check(bad.returncode == 1, "`list --json`(全局选项在子命令后)应被拒绝:\n" + bad.describe())


# ── envelope ───────────────────────────────────────────────────────────────


@case("envelope", "every-command-emits-one-envelope")
def case_envelope_matrix(ctx: Context) -> None:
    root = str(ctx.sandbox.root)
    expect_ok(ctx.sandbox.run("--json", "version"), "version")
    expect_ok(ctx.sandbox.run("--json", "capabilities"), "capabilities")
    expect_ok(ctx.sandbox.run("--json", "--root-dir", root, "list"), "list")
    expect_ok(ctx.sandbox.run("--json", "completion", "bash"), "completion")
    expect_error(ctx.sandbox.run("--json", "client", "-t", "paper", "-v", "1.20.4"), "client", "E_UNSUPPORTED_TYPE")
    expect_error(ctx.sandbox.run("--json", "plugin"), "plugin", "E_USAGE")
    expect_error(ctx.sandbox.run("--json", "update", "--channel", "nope"), "update", "E_USAGE")
    expect_error(ctx.sandbox.run("--json", "remove", "-v", "9.9.9", "--root-dir", root), "remove", "E_NOT_FOUND")
    # --force:被测二进制在 .build 里,开发环境护栏会先拦下来;这条只验证「非交互缺 --yes → 取消」。
    expect_error(ctx.sandbox.run("--json", "--root-dir", root, "uninstall", "--force"), "uninstall", "E_CANCELLED")


@case("envelope", "failures-do-not-print-human-lines-to-stdout")
def case_envelope_stdout_only_json(ctx: Context) -> None:
    result = ctx.sandbox.run("--json", "remove", "-v", "9.9.9", "--root-dir", str(ctx.sandbox.root))
    expect_error(result, "remove", "E_NOT_FOUND")
    check(
        result.stdout.strip().count("\n") == 0,
        "stdout 只能有信封一行(人类可读内容必须走 stderr):\n" + result.describe(),
    )


# ── contract ───────────────────────────────────────────────────────────────


@case("contract", "remove-without-yes-is-cancelled")
def case_remove_cancel(ctx: Context) -> None:
    target = ctx.sandbox.root / "versions" / "1.20.4" / "client"
    target.mkdir(parents=True)
    (target / "marker").write_text("x", encoding="utf-8")
    result = ctx.sandbox.run("--json", "remove", "-v", "1.20.4", "--root-dir", str(ctx.sandbox.root))
    expect_error(result, "remove", "E_CANCELLED")
    check(target.is_dir(), "取消后不得删除任何东西(规范 §8.2 / B9)")


@case("contract", "remove-with-yes-removes")
def case_remove_yes(ctx: Context) -> None:
    target = ctx.sandbox.root / "versions" / "1.20.5" / "client"
    target.mkdir(parents=True)
    payload = expect_ok(
        ctx.sandbox.run("--json", "remove", "-v", "1.20.5", "--root-dir", str(ctx.sandbox.root), "--yes"),
        "remove",
    )
    data = payload["data"]
    check(isinstance(data, dict) and data.get("removed") is True, f"应报告 removed=true: {data}")
    check(not target.exists(), "`remove --yes` 应真的删掉该目录")


@case("contract", "list-reports-installed-versions")
def case_list_installed(ctx: Context) -> None:
    (ctx.sandbox.root / "versions" / "1.21.4" / "client").mkdir(parents=True)
    (ctx.sandbox.root / "versions" / "1.21.4" / "server" / "paper").mkdir(parents=True)
    payload = expect_ok(ctx.sandbox.run("--json", "--root-dir", str(ctx.sandbox.root), "list"), "list")
    data = payload["data"]
    assert isinstance(data, dict)
    versions = data["versions"]
    assert isinstance(versions, list)
    entry = next((item for item in versions if item["version"] == "1.21.4"), None)
    check(entry is not None, f"list 未报告已安装版本: {versions}")
    assert entry is not None
    check(entry["client"] is True, "list 应识别出客户端")
    check("paper" in entry["servers"], "list 应识别出 paper 服务端")


@case("contract", "uninstall-without-yes-is-cancelled")
def case_uninstall_cancel(ctx: Context) -> None:
    # --force:让「开发环境护栏」不抢先,这里只验证非交互缺 --yes → 取消。
    result = ctx.sandbox.run("--json", "--root-dir", str(ctx.sandbox.root), "uninstall", "--force")
    expect_error(result, "uninstall", "E_CANCELLED")


@case("contract", "non-interactive-never-blocks")
def case_no_blocking(ctx: Context) -> None:
    # 用**超时**判定是否阻塞,不用墙钟阈值 —— CI 机器忙时 20s 内的正常启动也可能被误判。
    # 真阻塞(等输入)会一直挂着,由 timeout 触发并在这里变成失败。
    for args in (("list",), ("--json", "list"), ("client", "-t", "paper")):
        result = ctx.sandbox.run(*args, timeout=20)
        no_crash(result)
        check(result.duration < 20, f"{args} 疑似阻塞(耗时 {result.duration:.1f}s)")


# ── completion ─────────────────────────────────────────────────────────────


@case("completion", "scripts-for-every-shell")
def case_completion_scripts(ctx: Context) -> None:
    for shell in COMPLETION_SHELLS:
        payload = expect_ok(ctx.sandbox.run("--json", "completion", shell), "completion")
        data = payload["data"]
        assert isinstance(data, dict)
        script = data.get("script")
        check(isinstance(script, str) and len(script) > 20, f"{shell} 补全脚本为空: {data}")
        check(data.get("shell") == shell, f"{shell} 应回显请求值: {data}")


@case("completion", "unknown-shell-rejected")
def case_completion_unknown_shell(ctx: Context) -> None:
    expect_error(ctx.sandbox.run("--json", "completion", "tcsh"), "completion", "E_USAGE")


@case("completion", "install-writes-into-home")
def case_completion_install(ctx: Context) -> None:
    home = ctx.sandbox.home
    script = home / ".zsh" / "completions" / "_orzmc"
    payload = expect_ok(ctx.sandbox.run("--json", "completion", "install", env={"SHELL": "/bin/zsh"}), "completion")
    data = payload["data"]
    assert isinstance(data, dict)
    check(data.get("shell") == "zsh", f"应识别出 zsh: {data}")
    check(data.get("path") == str(script), f"落点应为 {script}: {data}")
    check("hint" in data, f"`data.hint` 字段必须存在(可为 null): {data}")
    check(script.is_file(), f"未写入补全脚本: {script}")
    rc = home / ".zshrc"
    check(rc.is_file(), "zsh 需要 fpath,应写入 ~/.zshrc")
    before = rc.read_text(encoding="utf-8")
    expect_ok(ctx.sandbox.run("--json", "completion", "install", env={"SHELL": "/bin/zsh"}), "completion")
    check(rc.read_text(encoding="utf-8") == before, "重复安装不应修改 rc(必须幂等)")


@case("completion", "script-only-shells-are-unsupported")
def case_completion_script_only(ctx: Context) -> None:
    """`frontends.md` F6:powershell/pwsh 只生成脚本 → `install` 必须明确 E_UNSUPPORTED。"""
    for shell in ("powershell", "pwsh"):
        payload = expect_error(
            ctx.sandbox.run("--json", "completion", "install", env={"SHELL": f"/usr/bin/{shell}"}),
            "completion",
            "E_UNSUPPORTED",
        )
        error = payload["error"]
        assert isinstance(error, dict)
        check(f"completion {shell}" in str(error.get("message")), f"应提示改用 `completion {shell}`: {error}")


@case("completion", "install-without-shell-is-usage-error")
def case_completion_install_no_shell(ctx: Context) -> None:
    result = ctx.sandbox.run("--json", "completion", "install", drop_env=("SHELL",))
    payload = expect_error(result, "completion", "E_USAGE")
    error = payload["error"]
    assert isinstance(error, dict)
    check("completion <shell>" in str(error.get("message")), f"应提示改用 `completion <shell>`: {error}")


# ── mcp ────────────────────────────────────────────────────────────────────


@case("mcp", "stdio-session")
def case_mcp_session(ctx: Context) -> None:
    installed = ctx.sandbox.root / "versions" / "1.20.4" / "client"
    installed.mkdir(parents=True, exist_ok=True)
    messages = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
        {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {"name": "list", "arguments": {"root-dir": str(ctx.sandbox.root)}},
        },
        {
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {"name": "remove", "arguments": {"version": "1.20.4", "root-dir": str(ctx.sandbox.root)}},
        },
        {"jsonrpc": "2.0", "id": 5, "method": "ping"},
        {"jsonrpc": "2.0", "id": 6, "method": "nope/nope"},
        {"jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": {"name": "nope", "arguments": {}}},
    ]
    stdin = "".join(json.dumps(message, ensure_ascii=False) + "\n" for message in messages)
    stdin += "{ this is not json }\n"
    result = ctx.sandbox.run("mcp", stdin=stdin)
    no_crash(result)

    lines = [line for line in result.stdout.splitlines() if line.strip()]
    check(len(lines) >= 7, f"响应行数不足({len(lines)}):\n" + result.describe())
    replies: dict[int, dict[str, object]] = {}
    for line in lines:
        payload = json.loads(line)
        check(payload.get("jsonrpc") == "2.0", f"缺少 jsonrpc 2.0: {payload}")
        if isinstance(payload.get("id"), int):
            replies[payload["id"]] = payload

    init_result = replies.get(1, {}).get("result")
    check(isinstance(init_result, dict), f"initialize 没有 result: {replies.get(1)}")
    assert isinstance(init_result, dict)
    check(init_result.get("protocolVersion") == "2025-06-18", f"protocolVersion 未回显: {init_result}")
    check(init_result.get("serverInfo", {}).get("name") == "orzmc", f"serverInfo 不对: {init_result}")

    tools = replies.get(2, {}).get("result", {}).get("tools")  # type: ignore[union-attr]
    check(isinstance(tools, list), "tools/list 没有返回 tools")
    assert isinstance(tools, list)
    names = {tool["name"] for tool in tools}
    check(names.isdisjoint(MCP_EXCLUDED), f"MCP 不应暴露 {MCP_EXCLUDED & names}")
    check({"list", "remove", "client"} <= names, f"核心命令未暴露: {names}")

    list_result = replies.get(3, {}).get("result")
    check(isinstance(list_result, dict), f"tools/call list 没有 result: {replies.get(3)}")
    assert isinstance(list_result, dict)
    check(list_result.get("isError") is False, f"list 应成功: {list_result}")
    inner = json.loads(list_result["content"][0]["text"])
    check(inner["ok"] is True and inner["command"] == "list", f"tool 信封不对: {inner}")

    remove_result = replies.get(4, {}).get("result")
    check(isinstance(remove_result, dict), f"tools/call remove 没有 result: {replies.get(4)}")
    assert isinstance(remove_result, dict)
    check(remove_result.get("isError") is True, "缺 --yes 的 remove 必须报错(规范 §8.2)")
    inner = json.loads(remove_result["content"][0]["text"])
    check(inner["error"]["code"] == "E_CANCELLED", f"应是 E_CANCELLED: {inner}")
    check(installed.is_dir(), "MCP 下缺 --yes 的 remove 不得真的删除任何东西")

    check(replies.get(5, {}).get("result") == {}, f"ping 应返回空结果: {replies.get(5)}")
    check(replies.get(6, {}).get("error", {}).get("code") == -32601, f"未知方法应 -32601: {replies.get(6)}")
    check(replies.get(7, {}).get("error", {}).get("code") == -32602, f"未知 tool 应 -32602: {replies.get(7)}")


# ── network(默认不跑)──────────────────────────────────────────────────────


@case("network", "update-check", network=True)
def case_update_check(ctx: Context) -> None:
    result = ctx.sandbox.run("--json", "update", "--check", timeout=120)
    no_crash(result)
    payload = envelope(result)
    if payload["ok"] is True:
        data = payload["data"]
        assert isinstance(data, dict)
        check(data.get("mode") == "check", f"data.mode 应为 check: {data}")
    else:
        error = payload["error"]
        assert isinstance(error, dict)
        check(str(error.get("code", "")).startswith("E_"), f"失败也要有稳定错误码: {error}")


@case("network", "plugin-search", network=True)
def case_plugin_search(ctx: Context) -> None:
    result = ctx.sandbox.run("--json", "plugin", "--search", "essentials", "--count", "2", timeout=120)
    no_crash(result)
    payload = envelope(result)
    if payload["ok"] is True:
        data = payload["data"]
        assert isinstance(data, dict)
        check(data.get("mode") == "search", f"data.mode 应为 search: {data}")


# ── 运行器 ──────────────────────────────────────────────────────────────────


@dataclass
class Outcome:
    case: Case
    status: str  # PASS / FAIL / SKIP
    detail: str = ""
    duration: float = 0.0


def run_case(case_: Case, sandbox: Sandbox, *, verbose: bool) -> Outcome:
    ctx = Context(sandbox=sandbox, verbose=verbose)
    started = time.monotonic()
    try:
        case_.func(ctx)
    except SkipCase as exc:
        return Outcome(case_, "SKIP", str(exc), time.monotonic() - started)
    except CheckError as exc:
        return Outcome(case_, "FAIL", str(exc), time.monotonic() - started)
    except subprocess.TimeoutExpired as exc:
        return Outcome(case_, "FAIL", f"超时({exc.timeout}s): {exc.cmd}", time.monotonic() - started)
    except Exception:
        return Outcome(case_, "FAIL", "验收脚本自身异常:\n" + traceback.format_exc(), time.monotonic() - started)
    return Outcome(case_, "PASS", "", time.monotonic() - started)


def selected_cases(*, only: set[str], network: bool) -> list[Case]:
    picked: list[Case] = []
    for case_ in CASES:
        if case_.network and not network:
            continue
        if only and case_.group not in only:
            continue
        picked.append(case_)
    return picked


def resolve_cli(explicit: str | None) -> list[str]:
    if explicit:
        path = Path(explicit).expanduser().resolve()
        if not path.is_file():
            raise SystemExit(f"--cli 指向的文件不存在: {path}")
        return [str(path)]
    for candidate in (REPO_ROOT / ".build" / "debug" / "orzmc", REPO_ROOT / ".build" / "release" / "orzmc"):
        if candidate.is_file():
            return [str(candidate)]
    raise SystemExit(
        "找不到 .build/debug/orzmc;先跑 `swift build -c debug --product orzmc`,或用 --cli 指定被测二进制"
    )


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="orzmc CLI 行为验收(Swift 实现;按规范断言)")
    parser.add_argument("--cli", help="被测可执行文件(缺省 .build/debug/orzmc)")
    parser.add_argument("--only", default="", help="只跑指定组,逗号分隔(如 envelope,completion)")
    parser.add_argument("--network", action="store_true", help="追加联网用例(update --check / plugin 搜索)")
    parser.add_argument("--list", action="store_true", help="列出用例组后退出")
    parser.add_argument("--list-cases", action="store_true", help="列出全部用例后退出")
    parser.add_argument("--timeout", type=float, default=90.0, help="单个用例超时秒数(默认 90)")
    parser.add_argument("--keep", action="store_true", help="保留沙箱目录(排障用)")
    parser.add_argument("-v", "--verbose", action="store_true", help="打印每个用例的输出")
    args = parser.parse_args(argv)

    only = {item.strip() for item in args.only.split(",") if item.strip()}
    cases = selected_cases(only=only, network=args.network)

    if args.list or args.list_cases:
        # 列用例不需要构建产物,先于 resolve_cli 返回。
        groups: dict[str, list[str]] = {}
        for case_ in cases:
            groups.setdefault(case_.group, []).append(case_.name)
        for group, names in groups.items():
            print(f"{group}:")
            if args.list_cases:
                for name in names:
                    print(f"  - {name}")
            else:
                print(f"  {len(names)} 个用例")
        return 0

    if not cases:
        print("没有匹配的用例(--only / --network 组合)", file=sys.stderr)
        return 2

    cli = resolve_cli(args.cli)
    sandbox = Sandbox(cli, timeout=args.timeout)
    print(f"被测对象: {' '.join(cli)}")
    print(f"沙箱: {sandbox.dir}")
    print()

    outcomes: list[Outcome] = []
    try:
        for case_ in cases:
            outcome = run_case(case_, sandbox, verbose=args.verbose)
            outcomes.append(outcome)
            print(f"[{outcome.status}] {case_.group}/{case_.name} ({outcome.duration:.1f}s)")
            if outcome.status == "FAIL":
                print(_indent(outcome.detail))
    finally:
        if args.keep:
            print(f"\n沙箱已保留: {sandbox.dir}")
        else:
            sandbox.cleanup()

    passed = sum(1 for item in outcomes if item.status == "PASS")
    skipped = [item for item in outcomes if item.status == "SKIP"]
    failed = [item for item in outcomes if item.status == "FAIL"]
    print()
    print(f"结果: {passed} 通过 / {len(failed)} 失败 / {len(skipped)} 跳过 / 共 {len(outcomes)}")
    for item in skipped:
        print(f"  SKIP {item.case.group}/{item.case.name}: {item.detail}")
    if failed:
        print("\n失败用例:")
        for item in failed:
            print(f"  - {item.case.group}/{item.case.name}")
        return 1
    return 0


def _indent(text: str) -> str:
    return "\n".join("    " + line for line in text.splitlines())


if __name__ == "__main__":
    raise SystemExit(main())
