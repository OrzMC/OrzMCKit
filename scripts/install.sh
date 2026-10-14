#!/bin/sh
# OrzMC `orzmc` CLI 一键安装器（macOS，用户级，免 sudo）。
#
#   curl -fsSL https://raw.githubusercontent.com/OrzMC/OrzMCKit/main/scripts/install.sh | sh
#
# 环境变量：
#   ORZMC_VERSION      指定版本（0.1.0 或 v0.1.0；缺省取最新 release）
#   ORZMC_INSTALL_DIR  二进制落点（缺省 ${XDG_BIN_HOME:-$HOME/.local/bin}）
#   ORZMC_ROOT_DIR     游戏根目录（写入 install.conf，缺省 ~/minecraft）
#
# 契约见父仓库 OrzMC/docs/spec/install-update.md。
set -eu

REPO="OrzMC/OrzMCKit"
BIN_NAME="orzmc"

err() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] \
  || err "当前安装器仅支持 macOS；其它平台见 https://github.com/${REPO}#install"

arch="$(uname -m)"
case "$arch" in
  arm64|aarch64) arch="arm64" ;;
  x86_64|amd64) arch="x86_64" ;;
  *) err "暂不支持该架构: ${arch}" ;;
esac

asset="orzmc-macos-${arch}"
version="${ORZMC_VERSION:-}"
case "$version" in
  "")  base="https://github.com/${REPO}/releases/latest/download" ;;
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
    && shasum -a 256 -c "${asset}.sum" >/dev/null ) \
  || err "SHA256 校验失败"

# 拒绝 HTML/JSON 错误页：必须是 Mach-O 可执行文件。
magic="$(head -c 4 "${tmp_dir}/${asset}" | od -An -tx1 | tr -d ' \n')"
case "$magic" in
  cffaedfe|cefaedfe|cafebabe|bebafeca|feedface|feedfacf) : ;;
  *) err "下载内容不是有效的 Mach-O 可执行文件(可能命中错误页)" ;;
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

# Shell 补全（命令自实现；未实现时静默跳过）。
completion_file=""
case "$(basename "${SHELL:-sh}")" in
  zsh) completion_file="$HOME/.zsh/completions/_orzmc" ;;
  bash) completion_file="$HOME/.local/share/bash-completion/completions/orzmc" ;;
esac
if ! "${install_dir}/${BIN_NAME}" completion install >/dev/null 2>&1; then
  completion_file=""
fi

installed_version="$("${install_dir}/${BIN_NAME}" version 2>/dev/null | awk '{print $2}')"

root_dir="${ORZMC_ROOT_DIR:-$HOME/minecraft}"
{
  printf 'tool=orzmc\n'
  printf 'schema=1\n'
  printf 'version=%s\n' "$installed_version"
  printf 'platform=macos-%s\n' "$arch"
  printf 'install_dir=%s\n' "$install_dir"
  printf 'binary=%s\n' "${install_dir}/${BIN_NAME}"
  printf 'source=%s\n' "$base"
  [ -n "$path_file" ] && printf 'path_file=%s\n' "$path_file"
  [ -n "$path_line" ] && printf 'path_line=%s\n' "$path_line"
  printf 'root_dir=%s\n' "$root_dir"
  [ -n "$completion_file" ] && printf 'completion_file=%s\n' "$completion_file"
} > "$manifest"
printf '安装记录: %s\n' "$manifest"

printf '\n完成。运行 %s --help 开始。\n' "$BIN_NAME"
