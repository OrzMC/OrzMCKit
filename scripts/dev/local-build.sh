#!/usr/bin/env bash
# 本机快速迭代（macOS）。目标：把「改一行 → 知道对不对」从 CI 的一轮 7 分钟压到秒级。
#
# 子命令:
#   check      最便宜：可移植性静态检查 + 各模块语法检查（swiftc -parse，秒级，无需依赖）
#   parse      只做语法检查
#   lint       只做跨平台静态检查
#   build      完整构建（需要 Swift 6 工具链 + macOS 14+ SDK，见下方说明）
#   test       单测
#   linux      转交 Linux 容器门禁（scripts/dev/linux-build.sh）
#
# 环境:
#   SWIFT_TC   指定工具链目录（缺省自动探测 swiftly 安装的 6.x）
#
# 已知的本机限制（会打印诊断，不静默失败）:
#   1. 只有 CommandLineTools（无 Xcode）时，SwiftLint 构建插件可能因找不到 `sourcekitdInProc`
#      而崩溃 → 装 Xcode 16+ 或 Xcode 版 CLT；
#   2. macOS SDK < 14 时，依赖里的 `URL(string:encodingInvalidCharacters:)` 会编译失败 →
#      升级 CommandLineTools / Xcode。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

TASK="${1:-check}"
shift || true

# ── 工具链探测 ────────────────────────────────────────────────────────────────
find_toolchain() {
    if [[ -n "${SWIFT_TC:-}" ]]; then
        echo "$SWIFT_TC"
        return 0
    fi
    local base="${SWIFTLY_TOOLCHAINS_DIR:-$HOME/Library/Developer/Toolchains}"
    local candidate
    candidate="$(ls -d "$base"/swift-6.*.xctoolchain 2>/dev/null | sort -V | tail -1)"
    if [[ -n "$candidate" ]]; then
        echo "$candidate"
        return 0
    fi
    if command -v swift >/dev/null 2>&1; then
        echo ""            # 用 PATH 上的 swift
        return 0
    fi
    return 1
}

TC="$(find_toolchain)" || {
    cat >&2 <<'EOF'
没有可用的 Swift 6 工具链。
安装（免 sudo）:
  brew install swiftly          # 或 https://github.com/swiftlang/swiftly
  swiftly init -y --no-modify-profile --skip-install
  swiftly install 6.0
EOF
    exit 1
}

if [[ -n "$TC" ]]; then
    export PATH="$TC/usr/bin:$PATH"
fi

SWIFT_BIN="$(command -v swift)"
SWIFT_VER="$("$SWIFT_BIN" --version 2>/dev/null | head -1)"
SDK_VER="$(xcrun --show-sdk-version 2>/dev/null || echo "?")"
DEV_DIR="$(xcode-select -p 2>/dev/null || echo "?")"

diagnose() {
    printf '工具链: %s\n' "$SWIFT_VER"
    printf 'SDK:    %s (macOS SDK)\n' "$SDK_VER"
    printf '开发者: %s\n' "$DEV_DIR"
    if [[ "$SWIFT_VER" != *"6."* ]]; then
        printf '⚠️  需要 Swift 6 工具链（包是 swift-tools-version:6.0）\n' >&2
    fi
    if [[ "$SDK_VER" != "?" ]] && (( ${SDK_VER%%.*} < 14 )); then
        printf '⚠️  macOS SDK %s < 14：依赖（OpenAPIKit）用到 macOS 14 才有的 API，完整构建会失败。\n' "$SDK_VER" >&2
        printf '    解决：装 Xcode 16+ 或更新 CommandLineTools（需管理员），或改用 `scripts/dev/local-build.sh linux`。\n' >&2
    fi
    if [[ "$DEV_DIR" == *CommandLineTools* ]]; then
        printf 'ℹ️  当前只有 CommandLineTools：SwiftLint 构建插件可能找不到 sourcekitdInProc（装 Xcode 16+ 可解）。\n'
    fi
}

# ── 子命令 ────────────────────────────────────────────────────────────────────
case "$TASK" in
    lint)
        exec python3 scripts/verify/portability.py
        ;;

    parse)
        status=0
        for module in Sources/*/; do
            name="$(basename "$module")"
            files=()
            while IFS= read -r file; do files+=("$file"); done < <(find "$module" -name '*.swift')
            [[ ${#files[@]} -eq 0 ]] && continue
            if ! swiftc -parse "${files[@]}" 2>/tmp/orzmc-parse.log; then
                printf '✘ %s 语法错误:\n' "$name" >&2
                cat /tmp/orzmc-parse.log >&2
                status=1
            else
                printf '✔ %s (%d 文件)\n' "$name" "${#files[@]}"
            fi
        done
        exit "$status"
        ;;

    check)
        diagnose
        printf '\n— 跨平台静态检查 —\n'
        python3 scripts/verify/portability.py || exit 1
        printf '\n— 语法检查（swiftc -parse）—\n'
        exec "$0" parse
        ;;

    build)
        diagnose
        exec swift build --product orzmc "$@"
        ;;

    test)
        diagnose
        exec swift test "$@"
        ;;

    linux)
        exec bash scripts/dev/linux-build.sh "${1:-all}"
        ;;

    *)
        echo "未知子命令: $TASK（可用 check|parse|lint|build|test|linux）" >&2
        exit 2
        ;;
esac
