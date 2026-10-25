#!/usr/bin/env bash
# 发版前把正式版本号写进生产环境覆盖层（ADR-0005 的发布流程）。
#
#   bash deploy/scripts/release-prep.sh <版本>          改写 overlays/prod 的镜像 newTag
#   bash deploy/scripts/release-prep.sh --check <版本>  只核对 overlays/prod 是否已钉到该版本，不改文件
#
# 版本不带 v：日期发布标识 2026.10.22-r1，或 1.2.3 这种三段号。
# 发版顺序：本脚本改写 → 提交并合进 main → 在那个提交上打 v<版本> tag 并推送。
# tag 触发的 workflow 用 --check 再核对一次，没写对就不构建、不上线：生产环境跟 release 分支，
# release 快进到 tag 那个提交，所以 Git 里写的版本号就是线上跑的版本号。
set -euo pipefail

# ── 每个仓只改这两行 ──
OVERLAY="deploy/k8s/dujiao-next/overlays/prod/kustomization.yaml"
IMAGES=(hubwu42/dujiao-next)

fail() { printf 'release-prep: %s\n' "$*" >&2; exit 1; }

mode="write"
if [ "${1:-}" = --check ]; then mode="check"; shift; fi
[ $# -eq 1 ] || fail "用法：release-prep.sh [--check] <版本>"
version=$1
[[ $version =~ ^([0-9]+\.[0-9]+\.[0-9]+|[0-9]{4}\.[1-9][0-9]?\.[1-9][0-9]?-r[1-9][0-9]{0,2})$ ]] ||
  fail "版本形状不对：${version}（要 2026.10.22-r1 或 1.2.3，不带 v、不带 -dry）"
[ -f "$OVERLAY" ] || fail "找不到 ${OVERLAY}（在仓根运行）"

# 取出 images 列表里某个镜像的 newTag；镜像没登记就输出空
current_tag() {
  awk -v img="$1" '
    /^[^ #]/ { in_images = ($0 ~ /^images:/) }
    in_images && $0 ~ "^ *- name: *" img " *$" { hit = 1; next }
    in_images && hit && /^ *newTag:/ { sub(/^ *newTag: */, ""); gsub(/["'\'']/, ""); print; exit }
    in_images && /^ *- name:/ { hit = 0 }
  ' "$OVERLAY"
}

for img in "${IMAGES[@]}"; do
  [ -n "$(current_tag "$img")" ] || fail "$OVERLAY 的 images 里没有 $img 的 newTag"
done

if [ "$mode" = check ]; then
  bad=0
  for img in "${IMAGES[@]}"; do
    got=$(current_tag "$img")
    if [ "$got" != "$version" ]; then
      printf 'release-prep: %s 钉的是 %s，不是 %s\n' "$img" "$got" "$version" >&2
      bad=1
    fi
  done
  [ $bad -eq 0 ] || fail "先运行 release-prep.sh $version 并合进 main，再在那个提交上打 tag"
  printf '%s 已钉到 %s\n' "$OVERLAY" "$version"
  exit 0
fi

tmp=$(mktemp)
for img in "${IMAGES[@]}"; do
  awk -v img="$img" -v ver="$version" '
    /^[^ #]/ { in_images = ($0 ~ /^images:/) }
    in_images && $0 ~ "^ *- name: *" img " *$" { hit = 1; print; next }
    in_images && hit && /^ *newTag:/ { match($0, /^ */); printf "%snewTag: \"%s\"\n", substr($0, 1, RLENGTH), ver; hit = 0; next }
    in_images && /^ *- name:/ { hit = 0 }
    { print }
  ' "$OVERLAY" >"$tmp"
  cat "$tmp" >"$OVERLAY"
done
rm -f "$tmp"
printf '%s → %s\n' "$OVERLAY" "$version"
