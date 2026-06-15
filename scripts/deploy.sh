#!/usr/bin/env bash
#
# メタデータ デプロイ ランナー（2 パス方式）
#
# 使い方:
#   ./scripts/deploy.sh [target-org-alias]
#   （省略時はデフォルト組織 'training' を使用）
#
# なぜ 2 パスか:
#   Lead のコンパクトレイアウト（Lead_Compact_Layout）と、それを primary に指定する
#   CustomObject の <compactLayoutAssignment> を「同一デプロイ（同一トランザクション）」で
#   送ると、割当評価時にレイアウトがまだコミットされておらず、primary が SYSTEM(既定) に
#   フォールバックする。結果、強調表示パネル（Highlights Panel）が既定項目のままになる。
#
#   そこで:
#     Pass 1) force-app 全体を通常デプロイ（この時点でコンパクトレイアウトは作成される）
#     Pass 2) <compactLayoutAssignment> だけを別トランザクションで再デプロイ
#             （レイアウトは既に存在するので割当が確実に適用される）
#
#   ※ Pass 2 は冪等。既に割当済みなら "Unchanged" となり無害。
#
# 追加の手動操作（Setup 画面でのコンパクトレイアウト割当など）は不要。

set -euo pipefail

ORG="${1:-training}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_VERSION="63.0"
COMPACT_LAYOUT="Lead_Compact_Layout"

echo "==> 対象組織: ${ORG}"

# ---- Pass 1: 全メタデータをデプロイ ----------------------------------------
echo "==> [Pass 1/2] force-app 全体をデプロイ"
sf project deploy start --source-dir "${ROOT}/force-app" --target-org "${ORG}"

# ---- Pass 2: コンパクトレイアウト割当のみを再デプロイ -----------------------
echo "==> [Pass 2/2] Lead の primary コンパクトレイアウト割当を適用 (${COMPACT_LAYOUT})"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${TMP}/objects"

cat > "${TMP}/objects/Lead.object" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <compactLayoutAssignment>${COMPACT_LAYOUT}</compactLayoutAssignment>
</CustomObject>
EOF

cat > "${TMP}/package.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types><members>Lead</members><name>CustomObject</name></types>
    <version>${API_VERSION}</version>
</Package>
EOF

sf project deploy start --metadata-dir "${TMP}" --target-org "${ORG}"

echo "==> 完了（強調表示パネルにカスタム コンパクトレイアウトが適用されました）"
