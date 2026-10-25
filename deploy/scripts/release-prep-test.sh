#!/usr/bin/env bash
# release-prep.sh 的测试：在临时目录里放一份覆盖层的副本跑，不碰仓里的文件。
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
script="$root/deploy/scripts/release-prep.sh"
overlay=$(sed -n 's/^OVERLAY="\(.*\)"$/\1/p' "$script")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/$(dirname "$overlay")"
cp "$root/$overlay" "$work/$overlay"
cd "$work"

count=0
expect() {
  local name=$1 want=$2 reason=$3 status=0 out
  shift 3
  out=$(bash "$script" "$@" 2>&1) || status=$?
  printf '%s | 期望 %s 实际 %s | %s\n' "$name" "$want" "$status" "$out"
  [ "$status" = "$want" ] && [[ $out == *"$reason"* ]] || exit 1
  count=$((count + 1))
}

expect '缺参数' 1 '用法'
expect '带 v 前缀拒绝' 1 '版本形状不对' v2026.10.22-r1
expect '干跑后缀拒绝' 1 '版本形状不对' 2026.10.22-r1-dry.1
expect '前导零拒绝' 1 '版本形状不对' 2026.10.02-r1
expect '改写前核对不通过' 1 '先运行' --check 2026.10.22-r1
expect '写入日期版本' 0 '→' 2026.10.22-r1
expect '写入后核对通过' 0 '已钉到' --check 2026.10.22-r1
expect '核对别的版本不通过' 1 '先运行' --check 2026.10.22-r2
expect '三段号也接受' 0 '→' 1.2.3
expect '三段号核对通过' 0 '已钉到' --check 1.2.3
# 只动 newTag 那几行，其余原样
cp "$root/$overlay" "$work/orig.yaml"
diff <(grep -v 'newTag:' "$work/orig.yaml") <(grep -v 'newTag:' "$overlay") >/dev/null || { echo '改到了 newTag 以外的行'; exit 1; }
count=$((count + 1))
grep -q 'newTag: "1.2.3"' "$overlay" || { echo '没写进去'; exit 1; }
count=$((count + 1))
echo "release-prep 测试全部通过（$count 条）"
