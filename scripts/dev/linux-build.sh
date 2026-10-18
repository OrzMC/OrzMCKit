#!/usr/bin/env bash
# 本地 Linux 构建/测试/验收（决策 D14；见 docs/iteration-efficiency.md）。
#
# 为什么有它：Swift 包的 Linux 门禁在 CI 上要 7–8 分钟一轮，本地用容器只要增量编译
# 几十秒到一两分钟，且能一次看到**全部**错误（不用等一轮 CI 才知道下一处）。
#
# 用法:
#   scripts/dev/linux-build.sh              # 构建 + 单测 + CLI 验收（release）
#   scripts/dev/linux-build.sh build        # 只构建（最快）
#   scripts/dev/linux-build.sh test         # 构建 + 单测
#   scripts/dev/linux-build.sh accept       # 构建 + CLI 验收
#   scripts/dev/linux-build.sh lint         # 只跑静态可移植性检查（秒级，无需容器）
#
# 前置: 本机有 docker 或 podman。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

TASK="${1:-all}"
IMAGE="${SWIFT_IMAGE:-swift:6.0}"

if [[ "$TASK" == "lint" ]]; then
    exec python3 scripts/verify/portability.py
fi

if command -v docker >/dev/null 2>&1; then
    ENGINE=docker
elif command -v podman >/dev/null 2>&1; then
    ENGINE=podman
else
    cat >&2 <<'EOF'
没有 docker/podman：无法本地跑 Linux 门禁。
可选替代：
  1) 装 Docker Desktop / podman（推荐，增量编译最快）；
  2) 本地装 Swift 6 工具链（swiftly install 6.0），直接 `swift build`（macOS 上跑不了 Linux 专属差异，
     但能秒级抓到 90% 的编译错误——比等 CI 快得多）；
  3) 交给 CI：`gh workflow run ci.yml`（每轮约 7–8 分钟）。
EOF
    exit 1
fi

# 复用同一容器内的工作目录，让 `.build`（SwiftPM 增量产物）留在本地 → 二次运行快很多。
mkdir -p .build-linux
TMP_HOME="$ROOT/.build-linux/home"
mkdir -p "$TMP_HOME"

run_in_container() {
    $ENGINE run --rm \
        -v "$ROOT:/src" \
        -v "$ROOT/.build-linux:/root/.cache/org.swift.swiftpm" \
        -w /src \
        -e HOME=/root \
        "$IMAGE" \
        bash -lc "$1"
}

case "$TASK" in
    build)
        run_in_container "swift build 2>&1 | tail -30"
        ;;
    test)
        run_in_container "apt-get update -qq && apt-get install -y -qq zip python3 >/dev/null && swift test 2>&1 | tail -30"
        ;;
    accept)
        run_in_container "apt-get update -qq && apt-get install -y -qq python3 >/dev/null && swift build -c release --product orzmc && python3 scripts/accept_cli.py --cli .build/release/orzmc"
        ;;
    all)
        run_in_container "apt-get update -qq && apt-get install -y -qq zip python3 >/dev/null \
            && python3 scripts/verify/portability.py \
            && swift build 2>&1 | tail -20 \
            && swift test 2>&1 | tail -20 \
            && swift build -c release --product orzmc \
            && python3 scripts/accept_cli.py --cli .build/release/orzmc"
        ;;
    *)
        echo "未知任务: $TASK（可选 build|test|accept|all|lint）" >&2
        exit 2
        ;;
esac
