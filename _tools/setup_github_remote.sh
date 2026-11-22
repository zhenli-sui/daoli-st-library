#!/usr/bin/env bash
# =============================================================================
# setup_github_remote.sh —— A 方案一键落地：把 C:\Library 接到 GitHub 并触发 MatIEC CI
#
# 前置：需要一个 GitHub Personal Access Token（classic，勾选 repo + workflow 权限）
#       生成地址：https://github.com/settings/tokens/new?scopes=repo,workflow
#
# 用法：
#   GITHUB_TOKEN=ghp_xxx bash setup_github_remote.sh <owner>/<repo>
#   例：GITHUB_TOKEN=ghp_xxx bash setup_github_remote.sh daoli/daoli-st-library
#
# 做的事：
#   1) 校验 token 与网络
#   2) 远端仓库不存在则用 API 自动创建（public，开源项目免费用 CI）
#   3) 写入 ~/.git-credentials（供后续每轮自动化 push，无需再输密码）
#   4) 配置 origin、推送 master、打首个 tag
#   5) 轮询 GitHub Actions，读回 MatIEC 编译结果
# =============================================================================
set -uo pipefail

LIB="${LIB:-C:/Library}"
OWNER_REPO="${1:-}"
TOKEN="${GITHUB_TOKEN:-}"

if [ -z "$OWNER_REPO" ] || [ -z "$TOKEN" ]; then
  echo "用法: GITHUB_TOKEN=<你的PAT> bash setup_github_remote.sh <owner>/<repo>"
  echo "  PAT 生成: https://github.com/settings/tokens/new?scopes=repo,workflow"
  exit 1
fi

OWNER="${OWNER_REPO%%/*}"
REPO="${OWNER_REPO##*/}"
API="https://api.github.com"

echo "== 1/5 校验 token =="
ME=$(curl -s -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" "$API/user")
LOGIN=$(echo "$ME" | python -c "import sys,json;print(json.load(sys.stdin).get('login',''))" 2>/dev/null)
if [ -z "$LOGIN" ]; then
  echo "  ✗ token 无效或网络不通："
  echo "$ME" | head -3
  exit 1
fi
echo "  ✓ 已登录为 $LOGIN"

echo "== 2/5 确认远端仓库 =="
CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "$API/repos/$OWNER/$REPO")
if [ "$CODE" = "404" ]; then
  echo "  仓库不存在，自动创建 $OWNER/$REPO（public）..."
  CREATE=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" "$API/user/repos" \
    -d "{\"name\":\"$REPO\",\"description\":\"道莅 IEC 61131-3 ST 工业代码库 · 零缺陷跨平台标准件\",\"private\":false,\"has_issues\":true,\"has_wiki\":false}")
  echo "$CREATE" | python -c "import sys,json;d=json.load(sys.stdin);print('  ✓ 已创建:',d.get('html_url') or d.get('message'))" 2>/dev/null
elif [ "$CODE" = "200" ]; then
  echo "  ✓ 仓库已存在"
else
  echo "  ! 返回 HTTP $CODE，继续尝试推送"
fi

echo "== 3/5 配置 git 凭据（供后续无人值守 push）=="
git config --global credential.helper store
CRED="$HOME/.git-credentials"
touch "$CRED" && chmod 600 "$CRED" 2>/dev/null
grep -q "github.com" "$CRED" 2>/dev/null || echo "https://$LOGIN:$TOKEN@github.com" >> "$CRED"
echo "  ✓ 已写入 $CRED（本地明文，勿外传）"

echo "== 4/5 配置 remote 并推送 =="
cd "$LIB" || exit 1
git remote remove origin 2>/dev/null
git remote add origin "https://github.com/$OWNER/$REPO.git"

# 确保 .gitignore 生效后再提交一次
git add -A 2>/dev/null
if ! git diff --cached --quiet 2>/dev/null; then
  git commit -q -m "chore: 编译闸基础设施 + 仓库瘦身（l2_check 缓存/降级桩/自愈补桩）" 2>/dev/null \
    && echo "  ✓ 已提交本地变更"
fi

echo "  推送 master（首次可能较慢，约 45MB）..."
if git push -u origin master 2>&1 | tail -3; then
  echo "  ✓ 推送成功"
else
  echo "  ✗ 推送失败，检查 token 是否有 repo 权限"
  exit 1
fi

echo "== 5/5 等待 MatIEC CI =="
sleep 8
RUNS=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "$API/repos/$OWNER/$REPO/actions/runs?per_page=1")
RUN_ID=$(echo "$RUNS" | python -c "import sys,json;r=json.load(sys.stdin).get('workflow_runs',[]);print(r[0]['id'] if r else '')" 2>/dev/null)
if [ -z "$RUN_ID" ]; then
  echo "  ! 未发现 CI run。可能 workflow 未被识别（检查 .github/workflows/iec-compile.yml 是否已推送）"
else
  echo "  ✓ CI run #$RUN_ID 已触发"
  echo "  查看: https://github.com/$OWNER/$REPO/actions/runs/$RUN_ID"
  echo "  轮询状态（最多 15 分钟）..."
  for i in $(seq 1 30); do
    sleep 30
    ST=$(curl -s -H "Authorization: Bearer $TOKEN" "$API/repos/$OWNER/$REPO/actions/runs/$RUN_ID" \
      | python -c "import sys,json;d=json.load(sys.stdin);print(d.get('status'),d.get('conclusion'))" 2>/dev/null)
    echo "    [$i/30] $ST"
    case "$ST" in
      completed*) break ;;
    esac
  done
fi

echo
echo "完成。后续每轮自动化可直接 git push 触发 CI，无需交互。"
echo "如 CI 报错，日志在 Actions 页面可下载 gate-reports 工件。"
