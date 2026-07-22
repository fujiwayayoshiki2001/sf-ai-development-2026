# Salesforce AI 駆動開発研修 - リード管理・スコアリングシステム

> **対象研修**: 2026年度 AI 駆動開発研修
> **研修期間**: 2026年9月17日〜9月29日（6日間）
> **目的**: AI 協働による新規機能開発を学ぶ

---

## 概要

このリポジトリは、AI 駆動開発研修で使用する **ベースシステム** のソースコードです。

### システム名

リード管理・スコアリングシステム (Lead Scoring System)

### 主な機能

リードを 3 つの軸（属性・行動・興味）で評価し、スコアの高い順に優先順位を可視化する。

```
最終スコア = 属性スコア + 行動スコア + 興味スコア
            (最大100)   (最大120)   (最大80)
            = 最大 300 点
```

| 軸 | データソース |
|---|---|
| 属性スコア | Lead レコード自身 |
| 行動スコア | CampaignMember（標準）|
| 興味スコア | Lead_Interest__c（カスタム）|

---

## 技術スタック

```
[Salesforce]
- Salesforce Platform (API Version 62.0)
- Lightning Experience

[開発言語]
- Apex
- Lightning Web Components (LWC)
- Flow (宣言的)

[開発ツール]
- Salesforce CLI (sf)
- Salesforce DX
- VS Code + Salesforce Extension Pack
- Git / GitHub
- Claude Code (AI 駆動開発)
```

---

## ディレクトリ構成

```
sf-ai-development/
├── force-app/main/default/   # Salesforce ソースコード
│   ├── classes/              # Apex クラス
│   ├── triggers/             # Apex トリガー
│   ├── flows/                # Flow
│   ├── lwc/                  # Lightning Web Components
│   ├── objects/              # カスタムオブジェクト・項目
│   ├── customMetadata/       # カスタムメタデータ
│   ├── permissionsets/       # 権限セット
│   ├── tabs/                 # カスタムタブ
│   ├── flexipages/           # Lightning ページ
│   └── applications/         # カスタムアプリ
├── data/                     # シードデータ
├── .claude/                  # Claude Code の設定
│   └── commands/             # カスタムスラッシュコマンド
├── CLAUDE.md                 # プロジェクトルール
└── README.md                 # このファイル
```

---

## セットアップ

### 前提条件

以下がインストール済みであること：

```
✓ Node.js 20 LTS
✓ Salesforce CLI (sf) v2.x
✓ Git
✓ VS Code（推奨）
✓ Claude Code（研修ツール）
```

### 1. リポジトリのクローン

```bash
git clone https://github.com/<研修用Org>/<リポジトリ名>.git
cd sf-ai-development
```

> 実際のリポジトリ URL は講師から共有します。

### 2. Dev Hub への接続確認

```bash
sf org list
```

Dev Hub が認証済みでない場合：

```bash
sf org login web --alias dev-hub --instance-url https://power-connect-7303.my.salesforce.com --set-default-dev-hub
```

### 3. スクラッチ組織の作成

```bash
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias lead-scoring-base \
  --duration-days 30 \
  --set-default
```

### 4. メタデータのデプロイ

```bash
bash scripts/deploy.sh lead-scoring-base
```

> **なぜスクリプト経由か（重要）**
> `sf project deploy start` を 1 回実行するだけでは、Lead の **強調表示パネル（Highlights Panel）**
> が既定項目のままになります。コンパクトレイアウト（`Lead_Compact_Layout`）と、それを primary に
> 指定する `<compactLayoutAssignment>` を同一デプロイで送ると、割当評価時にレイアウトが未コミットで
> SYSTEM(既定) にフォールバックするためです。
>
> `scripts/deploy.sh` は **2 パス方式**（① 全体デプロイ → ② 割当のみ別トランザクションで再デプロイ）で
> この問題を吸収し、**手動操作なし**でカスタム コンパクトレイアウトを適用します。
>
> 素の `sf project deploy start --target-org lead-scoring-base` を使った場合は、デプロイ後に
> もう一度 `bash scripts/deploy.sh lead-scoring-base` を実行すれば割当だけが適用されます（冪等）。

### 5. 権限セットの割り当て（シードより**前**に実行）

```bash
sf org assign permset --name Lead_Management_User --target-org lead-scoring-base
```

> **順序が重要（重要）**
> この権限セットは、スコア系・興味系のカスタム項目に対する **FLS（項目レベルセキュリティ）** を付与します。
> 割り当てる前に Lead を作成したり次のシード投入を行うと、スコア計算トリガーの
> `WITH SECURITY_ENFORCED` クエリや `seed.apex` のコンパイルが
> **「Insufficient permissions / No such column 'Source__c'」** で失敗します。
> 必ず **デプロイ → 権限セット → シード** の順で実行してください。

### 6. シードデータの投入

```bash
bash data/load-data.sh lead-scoring-base
```

> `load-data.sh` は冗長安全のため、投入前に権限セット（手順 5）を自動で割り当てます
> （割当済みならスキップ）。手順 5 を実行済みでも問題ありません。

### 7. 組織を開く

```bash
sf org open --target-org lead-scoring-base
```

---

## システム構成

### Apex クラス（12個 + トリガー 3個）

| クラス名 | 役割 |
|---|---|
| LeadController | LWC からの呼び出し窓口 |
| LeadService | ビジネスロジック中核 |
| LeadScoringService | 3軸を合算する統括 |
| LeadAttributeScorer | 属性スコア計算 |
| LeadBehaviorScorer | 行動スコア計算（時間減衰込み）|
| LeadInterestScorer | 興味スコア計算 |
| LeadValidator | バリデーション |
| LeadTriggerHandler | Lead トリガーハンドラ |
| LeadInterestTriggerHandler | Lead_Interest__c トリガーハンドラ |
| CampaignMemberTriggerHandler | CampaignMember トリガーハンドラ |
| LeadConstants | 定数 |
| TestDataFactory | テストデータファクトリ |

### Flow（1個）

| Flow 名 | 種類 | 役割 |
|---|---|---|
| Lead_Status_Update_Flow | スケジュール | 古いリードのステータス更新 |

### LWC（2個）

| コンポーネント | 配置場所 | 役割 |
|---|---|---|
| leadScoreCard | Lead レコードページ | 3軸スコア表示 |
| leadInterestRadar | Lead レコードページ | 興味レーダーチャート |

### カスタムオブジェクト

```
Lead_Interest__c（リード興味）
- リードの関心トピックを構造化
- 主従関係 with Lead
```

### カスタムメタデータ

```
Lead_Scoring_Config__mdt（スコアリング設定）
- 各スコアの重みを設定で管理
```

---

## 開発のガイドライン

### コーディング規約

詳細は `CLAUDE.md` を参照。

主要なルール：

```
✓ バルク化を徹底（ループ内 SOQL/DML 禁止）
✓ WITH SECURITY_ENFORCED を全 SOQL に
✓ エラーハンドリングを完備
✓ テストカバレッジ 90% 以上
✓ 定数を LeadConstants に集約
✓ 命名規則の遵守
```

### Git の運用

```
[基本方針]
- 個人開発（チーム開発ではない）
- ローカルでコミットしながら進める
- リモートへの push、PR は行わない
```

---

## Claude Code との協働

このプロジェクトは **Claude Code** を活用して開発を行います。

### 起動方法

```bash
# プロジェクトルートで
claude
```

`CLAUDE.md` が自動で読み込まれ、プロジェクトのルールを理解した状態で会話が始まります。

### 主なスラッシュコマンド

| コマンド | 用途 |
|---|---|
| `/sf-review` | 統合コードレビュー (Apex / LWC / Flow / テストを観点別にチェック) |
| `/refactor` | リファクタリングの提案 |
| `/test` | テストクラスの生成 |
| `/explain` | コードの解説 |

これらは `.claude/skills/` 配下の Skill として実装されています。
Skill の中身を読むと、Claude Code の動きが理解できます。

### hooks による自動コンテキスト注入

このプロジェクトには **SessionStart hook** が設定されています。
Claude Code のセッションを開始するたびに、以下の情報が Claude に自動で
伝わります:

- Salesforce AI 駆動開発研修プロジェクトであること
- 主要コマンド (`/sf-review` 等) の存在
- コード作成後は `/sf-review` でのセルフレビュー推奨

そのため、Claude に何も説明していないのに、
「Salesforce の研修プロジェクトですね」と応答してくれます。

hooks の仕組みは `.claude/settings.json` で確認できます。
`/hooks` コマンドでも現在有効な hook を一覧表示できます。

---

## 研修の流れ

### 全体スケジュール（6日間）

本研修は6日間（9/17, 18, 24, 25, 28, 29）で、既存のベースシステムに
AI と協働して新規機能を追加します。

```
[大まかな流れ]
1. 環境構築、ベースシステムの理解
2. 追加機能の要件を整理（議事録メモをもとに）
3. AI と協働で新機能を実装
4. 成果を発表
```

※ リファクタリング期は廃止、個人開発

詳細は別途配布する **カリキュラム概要** を参照。

---

## 関連ドキュメント

### このリポジトリ内

| ファイル | 内容 |
|---|---|
| `CLAUDE.md` | プロジェクトルール（Claude Code 用）|
| `README.md` | このファイル |

### 研修関連（別途配布）

| ドキュメント | 配布対象 |
|---|---|
| AI駆動開発_カリキュラム概要.md | 全員 |
| 環境構築手順書 | 受講者 |
| GitHub 基本ガイド | 受講者 |
| ベースシステム仕様書 | 講師・受講者 |

---

## トラブルシューティング

### スクラッチ組織の作成に失敗する

```bash
# Dev Hub の状態を確認
sf org list

# Dev Hub を再認証
sf org login web --alias dev-hub --set-default-dev-hub
```

### Lead を作成すると「Insufficient permissions / inaccessible field」エラーになる

```
System.QueryException: Insufficient permissions: secure query included inaccessible field
Class.LeadInterestScorer.calculateBulk: line XX
...
Trigger.LeadTrigger: line 19
```

または `seed.apex` 実行時に `No such column 'Source__c' on entity 'Lead_Interest__c'`。

**原因**: 権限セット `Lead_Management_User`（スコア系・興味系項目の FLS を付与）が未割当。
スコア計算トリガーの `WITH SECURITY_ENFORCED` クエリが項目を参照できず失敗します。

```bash
# 対処: 権限セットを割り当てる（セットアップ手順 5）
sf org assign permset --name Lead_Management_User --target-org <org-alias>
```

### デプロイエラーが発生する

```bash
# テストカバレッジ不足の場合
sf project deploy start --test-level RunLocalTests

# 個別のメタデータをデプロイ
sf project deploy start --metadata ApexClass:LeadController
```

### Claude Code が CLAUDE.md を読まない

```bash
# プロジェクトルートで起動しているか確認
pwd
ls CLAUDE.md

# Claude Code を再起動
claude
```

---

## ライセンス

社内研修教材。社外への配布禁止。

---

## 作成者・お問い合わせ

```
[作成者]
藤原 佳樹

[作成日]
2026年6月

[研修事務局]
(社内連絡先)
```
