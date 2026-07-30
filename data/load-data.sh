#!/usr/bin/env bash
#
# Phase 8 シードデータ投入ランナー
#
# 使い方:
#   ./data/load-data.sh [target-org-alias]
#   （省略時はデフォルト組織 'training' を使用）
#
# 投入は冪等（seed.apex 先頭で既存シードを削除して再生成）。
# seed の前提として権限セット（FLS）の割当もこのスクリプト内で行うため、追加の手動操作は不要。

set -euo pipefail

ORG="${1:-training}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PERMSET="Lead_Management_User"

echo "==> 対象組織: ${ORG}"

# 権限セットの割当（seed の前提）。
# スコア系・興味系項目の FLS が無いと、seed.apex のコンパイル（Source__c 等の参照）や
# Lead 挿入時のトリガー（スコア計算の WITH SECURITY_ENFORCED クエリ）が
# 「No such column / Insufficient permissions」で失敗するため、必ず seed より前に割り当てる。
# 既に割当済みでも害が無いよう、重複エラーは無視する（冪等）。
echo "==> 権限セットを割当 (${PERMSET}) ※seed の前提"
sf org assign permset --name "${PERMSET}" -o "${ORG}" 2>/dev/null \
  || echo "    （割当済みのためスキップ）"

echo "==> シードデータを投入 (data/seed.apex)"
sf apex run -f "${DIR}/seed.apex" -o "${ORG}"

echo "==> 投入結果を検証 (data/verify.apex)"
sf apex run -f "${DIR}/verify.apex" -o "${ORG}"

echo "==> 商談化データを投入 (data/seed-converted.apex)"
sf apex run -f "${DIR}/seed-converted.apex" -o "${ORG}"

echo "==> 商談化データを検証 (data/verify-converted.apex)"
sf apex run -f "${DIR}/verify-converted.apex" -o "${ORG}"

echo "==> 完了"
