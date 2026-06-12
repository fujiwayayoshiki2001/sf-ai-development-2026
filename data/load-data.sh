#!/usr/bin/env bash
#
# Phase 8 シードデータ投入ランナー
#
# 使い方:
#   ./data/load-data.sh [target-org-alias]
#   （省略時はデフォルト組織 'training' を使用）
#
# 追加の手動設定・権限は不要。投入は冪等（seed.apex 先頭で既存シードを削除して再生成）。

set -euo pipefail

ORG="${1:-training}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> 対象組織: ${ORG}"

echo "==> シードデータを投入 (data/seed.apex)"
sf apex run -f "${DIR}/seed.apex" -o "${ORG}"

echo "==> 投入結果を検証 (data/verify.apex)"
sf apex run -f "${DIR}/verify.apex" -o "${ORG}"

echo "==> 完了"
