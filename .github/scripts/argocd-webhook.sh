#!/usr/bin/env bash
# 通知 Argo CD 立刻刷新跟着某个分支的 Application（ADR-0005 的发布流程）。
#
#   ARGOCD_WEBHOOK_SECRET=... bash .github/scripts/argocd-webhook.sh <分支名> <提交 sha>
#
# 发的是一个伪装成 GitHub push 事件的请求：Argo CD 按 repository.html_url 与 ref 找到
# 跟这个仓、这个分支的 Application 并立即刷新，用 HMAC-SHA256 签名校验来源（密钥同 Argo CD
# 的 webhook.github.secret）。不发也不会丢部署：Argo CD 每 3 分钟自己轮询一次 Git，这一步只为快。
# 所以缺密钥时只告警、以 0 退出；密钥在但请求失败才算失败。
#
# 环境变量：
#   ARGOCD_WEBHOOK_SECRET  仓库 secret，值与 settings 的 GOSAIL_ARGOCD_WEBHOOK_SECRET 相同
#   ARGOCD_WEBHOOK_URL     可省略，默认 https://argocd.gosail.tech/api/webhook
#   GITHUB_REPOSITORY      Actions 自带，形如 HubWu42/agent-platform
set -euo pipefail

branch="${1:?用法：argocd-webhook.sh <分支名> <提交 sha>}"
sha="${2:?用法：argocd-webhook.sh <分支名> <提交 sha>}"
url="${ARGOCD_WEBHOOK_URL:-https://argocd.gosail.tech/api/webhook}"
repo="${GITHUB_REPOSITORY:?缺 GITHUB_REPOSITORY}"

if [ -z "${ARGOCD_WEBHOOK_SECRET:-}" ]; then
  echo "::warning::没配 ARGOCD_WEBHOOK_SECRET，跳过通知；Argo CD 会在 3 分钟内自己轮询到这次改动"
  exit 0
fi

body=$(printf '{"ref":"refs/heads/%s","after":"%s","repository":{"html_url":"https://github.com/%s","default_branch":"main"},"commits":[]}' \
  "$branch" "$sha" "$repo")
sig=$(printf '%s' "$body" | openssl dgst -sha256 -hmac "$ARGOCD_WEBHOOK_SECRET" -r | cut -d' ' -f1)

code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 --retry 3 --retry-all-errors \
  -X POST "$url" \
  -H 'Content-Type: application/json' \
  -H 'X-GitHub-Event: push' \
  -H "X-Hub-Signature-256: sha256=$sig" \
  --data "$body")
if [ "$code" != 200 ]; then
  echo "::error::Argo CD webhook 返回 HTTP $code"
  exit 1
fi
echo "已通知 Argo CD：$repo 的 $branch 分支到 ${sha:0:7}"
