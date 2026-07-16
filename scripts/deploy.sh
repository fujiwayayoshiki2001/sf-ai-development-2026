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
#   Lead レコードページ（Lead_Record_Page FlexiPage）を View アクションの actionOverrides で
#   割り当てる設定も同じ問題を持つ。実際に検証したところ、FlexiPage と actionOverrides を
#   同一デプロイで送るとデプロイ自体はエラー無く成功するが、デプロイ後に retrieve すると
#   actionOverrides は type=Default のままで、割当が反映されていないことを確認済み
#   （= FlexiPage 未コミットのまま割当評価が行われ、silent に既定へフォールバックする）。
#
#   なお、formFactor 未指定（無指定）の actionOverrides エントリを Pass 2 の
#   metadata-dir 経由の部分デプロイに含めると
#   「null はサポートされていないフォーム要素です」で失敗することを確認済み
#   （source 形式デプロイの Pass 1 では問題にならないが、mdapi 部分デプロイでは NG）。
#   Lightning Experience のデスクトップ表示は formFactor=Large の割当のみで機能するため、
#   Pass 2 では Large のみを対象にしている。
#
#   そこで:
#     Pass 1) force-app 全体を通常デプロイ（この時点でコンパクトレイアウト・FlexiPage は作成される）
#     Pass 2) <compactLayoutAssignment> と Lead レコードページの actionOverrides(View) だけを
#             別トランザクションで再デプロイ（対象はすでに存在するので割当が確実に適用される）
#
#   ※ Pass 2 は冪等。既に割当済みなら "Unchanged" となり無害。
#
# 追加の手動操作（Setup 画面でのコンパクトレイアウト割当・Lightning App Builder での
# レコードページ有効化など）は不要。

set -euo pipefail

ORG="${1:-training}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_VERSION="63.0"
COMPACT_LAYOUT="Lead_Compact_Layout"
RECORD_PAGE="Lead_Record_Page"

echo "==> 対象組織: ${ORG}"

# ---- Pass 1: 全メタデータをデプロイ ----------------------------------------
echo "==> [Pass 1/2] force-app 全体をデプロイ"
sf project deploy start --source-dir "${ROOT}/force-app" --target-org "${ORG}"

# ---- Pass 2: コンパクトレイアウト割当 + レコードページ割当を再デプロイ -------
echo "==> [Pass 2/2] Lead の primary コンパクトレイアウト割当 (${COMPACT_LAYOUT}) と"
echo "               レコードページ割当 (${RECORD_PAGE}) を適用"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${TMP}/objects"

cat > "${TMP}/objects/Lead.object" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <actionOverrides>
        <actionName>View</actionName>
        <formFactor>Large</formFactor>
        <type>Flexipage</type>
        <content>${RECORD_PAGE}</content>
    </actionOverrides>
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

echo "==> 完了（強調表示パネルにカスタム コンパクトレイアウト、Lead レコードページに"
echo "     カスタム FlexiPage が適用されました）"
