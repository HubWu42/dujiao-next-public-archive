#!/usr/bin/env bash
# 把镜像版本写进某个环境的覆盖层，以 github-actions[bot] 的身份提交并推回 main（ADR-0008）。
# 测试版回写 overlays/test、正式版回写 overlays/prod 都用这一个脚本。
#
#   IMAGE_NAME=hubwu42/dujiao-next bash .github/scripts/write-overlay.sh <覆盖层目录> <镜像 tag> <环境名>
#
# 在 checkout 了 main 的工作区里运行。测试版和正式版两条回写可能同时推 main，
# 被拒就丢掉自己的提交、rebase 到最新的 main 再改一次；两条改的是不同文件，rebase 不会冲突。
# 提交信息不带 [skip ci]：GITHUB_TOKEN 推的提交本来就不触发 workflow，带了反而会让
# 打在这个提交上的发版 tag 被 GitHub 一起跳过。
set -euo pipefail

overlay="${1:?用法：write-overlay.sh <覆盖层目录> <镜像 tag> <环境名>}"
tag="${2:?用法：write-overlay.sh <覆盖层目录> <镜像 tag> <环境名>}"
env_name="${3:?用法：write-overlay.sh <覆盖层目录> <镜像 tag> <环境名>}"
image="${IMAGE_NAME:?缺 IMAGE_NAME}"

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
for attempt in 1 2 3 4 5; do
  (cd "$overlay" && kustomize edit set image "$image=$image:$tag")
  if git diff --quiet; then
    echo "$env_name 环境已是 $tag"
    break
  fi
  git commit -am "chore(deploy): $env_name 环境镜像改为 $tag"
  if git push origin HEAD:main; then break; fi
  [ "$attempt" -lt 5 ] || { echo "::error::推送 main 五次都被拒"; exit 1; }
  git reset --hard HEAD~1
  sleep $((attempt * 3))
  git pull --rebase origin main
done
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "- $env_name 环境镜像 → \`$tag\`" >>"$GITHUB_STEP_SUMMARY"
fi
