#!/bin/sh
# OrzMC `orzmc` CLI 一键安装器（macOS / Linux，用户级，免 sudo）。
#
#   curl -fsSL https://raw.githubusercontent.com/OrzMC/OrzMCKit/main/scripts/install.sh | sh
#
# 环境变量：
#   ORZMC_VERSION      指定版本（0.1.0 或 v0.1.0；缺省取最新 release）
#   ORZMC_INSTALL_DIR  二进制落点（缺省 ${XDG_BIN_HOME:-$HOME/.local/bin}）
#   ORZMC_ROOT_DIR     游戏根目录（写入 install.conf，缺省 ~/minecraft）
#   ORZMC_SURFACE      哪个前端装了 CLI（cli|gui，写入 install.conf，缺省 cli）
#   ORZMC_NO_COMPLETION=1  不安装 Shell 补全（规范 install-update.md §5 的 --no-completion）
#
# 契约见父仓库 OrzMC/docs/spec/install-update.md。
set -eu

REPO="OrzMC/OrzMCKit"
BIN_NAME="orzmc"

err() { printf 'error: %s\n' "$*" >&2; exit 1; }

# 解析「最新 release」的下载前缀。
#
# `releases/latest` 只指向**最新正式版**：本仓库的 Swift CLI 按 `docs/two-cli-strategy.md` §6
# 一律以 **pre-release** 发布（与 Python 同步迭代、但不对外分发），此时
# `releases/latest/download/<asset>` 恒为 404 —— GUI「安装 Swift CLI」失败的根因就在这里。
# 改为问 API 要「最新一个 release」（含预发布），API 不可用（离线/限流）时再退回 latest。
latest_base() {
  api="https://api.github.com/repos/${REPO}/releases?per_page=1"
  tag="$(curl -fsSL --max-time 15 "$api" 2>/dev/null \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  if [ -n "$tag" ]; then
    printf '最新发布: %s\n' "$tag" >&2
    printf 'https://github.com/%s/releases/download/%s' "$REPO" "$tag"
  else
    printf 'https://github.com/%s/releases/latest/download' "$REPO"
  fi
}

os=""
case "$(uname -s)" in
  Darwin) os="macos" ;;
  Linux)  os="linux" ;;
  *) err "当前安装器仅支持 macOS / Linux；Windows 请等 Phase 6.5（见 docs/spec/frontends.md §7.2）" ;;
esac

arch="$(uname -m)"
case "$arch" in
  arm64|aarch64) arch="arm64" ;;
  x86_64|amd64) arch="x86_64" ;;
  *) err "暂不支持该架构: ${arch}" ;;
esac

asset="orzmc-${os}-${arch}"
version="${ORZMC_VERSION:-}"
case "$version" in
  "")  base="$(latest_base)" ;;
  v*)  base="https://github.com/${REPO}/releases/download/${version}" ;;
  *)   base="https://github.com/${REPO}/releases/download/v${version}" ;;
esac

install_dir="${ORZMC_INSTALL_DIR:-${XDG_BIN_HOME:-$HOME/.local/bin}}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/orzmc"
manifest="${state_dir}/install.conf"

mkdir -p "$install_dir" "$state_dir"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/orzmc-install.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

printf '下载 %s ...\n' "$asset"
curl -fL --retry 3 -o "${tmp_dir}/${asset}" "${base}/${asset}" \
  || err "下载失败: ${base}/${asset}"
curl -fL --retry 3 -o "${tmp_dir}/SHA256SUMS" "${base}/SHA256SUMS" \
  || err "下载校验文件失败: ${base}/SHA256SUMS"

( cd "$tmp_dir" && grep " ${asset}\$" SHA256SUMS > "${asset}.sum" \
    && if command -v sha256sum >/dev/null 2>&1; then sha256sum -c "${asset}.sum" >/dev/null; \
       else shasum -a 256 -c "${asset}.sum" >/dev/null; fi ) \
  || err "SHA256 校验失败"

# 拒绝 HTML/JSON 错误页：macOS 必须是 Mach-O，Linux 必须是 ELF。
magic="$(head -c 4 "${tmp_dir}/${asset}" | od -An -tx1 | tr -d ' \n')"
case "$os:$magic" in
  macos:cffaedfe|macos:cefaedfe|macos:cafebabe|macos:bebafeca|macos:feedface|macos:feedfacf) : ;;
  linux:7f454c46) : ;;
  *) err "下载内容不是有效的可执行文件(${os}，可能命中错误页)" ;;
esac

chmod +x "${tmp_dir}/${asset}"
mv -f "${tmp_dir}/${asset}" "${install_dir}/${BIN_NAME}"
printf '已安装: %s\n' "${install_dir}/${BIN_NAME}"

# PATH 集成（幂等；PATH 已含 install_dir 则不动 rc）。
path_file=""
path_line=""
case ":${PATH}:" in
  *":${install_dir}:"*) : ;;
  *)
    case "$(basename "${SHELL:-sh}")" in
      zsh) rc="$HOME/.zshrc" ;;
      bash) rc="$HOME/.bashrc" ;;
      *) rc="$HOME/.profile" ;;
    esac
    line="export PATH=\"${install_dir}:\$PATH\""
    if ! grep -Fqx "$line" "$rc" 2>/dev/null; then
      printf '\n%s\n' "$line" >> "$rc"
      path_file="$rc"
      path_line="$line"
      printf '已把 %s 写入 %s\n' "$install_dir" "$rc"
      printf '请新开终端或执行: . %s\n' "$rc"
    fi
    ;;
esac

# Shell 补全（命令自实现；未实现时静默跳过；--no-completion / ORZMC_NO_COMPLETION=1 关闭）。
completion_file=""
if [ "${ORZMC_NO_COMPLETION:-0}" != "1" ]; then
  case "$(basename "${SHELL:-sh}")" in
    zsh) completion_file="$HOME/.zsh/completions/_orzmc" ;;
    bash) completion_file="$HOME/.local/share/bash-completion/completions/orzmc" ;;
  esac
  if ! "${install_dir}/${BIN_NAME}" completion install >/dev/null 2>&1; then
    completion_file=""
  fi
fi

# 只取首行：`orzmc version` 之后还会打印合规声明（多行），直接用 awk 会把声明也塞进
# install.conf 的 version 字段（实测过）。
installed_version="$("${install_dir}/${BIN_NAME}" version 2>/dev/null | head -n 1 | awk '{print $2}')"
[ -n "$installed_version" ] || installed_version="unknown"

root_dir="${ORZMC_ROOT_DIR:-$HOME/minecraft}"
{
  printf 'tool=orzmc\n'
  printf 'schema=1\n'
  printf 'version=%s\n' "$installed_version"
  printf 'platform=%s-%s\n' "$os" "$arch"
  printf 'install_dir=%s\n' "$install_dir"
  printf 'binary=%s\n' "${install_dir}/${BIN_NAME}"
  printf 'source=%s\n' "$base"
  [ -n "$path_file" ] && printf 'path_file=%s\n' "$path_file"
  [ -n "$path_line" ] && printf 'path_line=%s\n' "$path_line"
  printf 'root_dir=%s\n' "$root_dir"
  case "${ORZMC_SURFACE:-cli}" in
    cli | gui) printf 'surface=%s\n' "${ORZMC_SURFACE:-cli}" ;;
    *)         printf 'surface=cli\n' ;;
  esac
  [ -n "$completion_file" ] && printf 'completion_file=%s\n' "$completion_file"
} > "$manifest"
printf '安装记录: %s\n' "$manifest"

# 备份功能依赖系统 `zip`（极简发行版可能没有）；不影响其它命令，仅提示一次。
if [ "$os" = "linux" ] && ! command -v zip >/dev/null 2>&1; then
  printf '\n提示: 未检测到 `zip`，`orzmc backup` 需要它（Debian/Ubuntu: sudo apt install zip）。\n'
fi

printf '\n完成。运行 %s --help 开始。\n' "$BIN_NAME"
