# Salesforce AI 駆動開発研修 - リード管理・スコアリングシステム

> **対象研修**: 2026年度 AI 駆動開発研修
> **研修期間**: 2026年9月11日〜9月29日（10日間）
> **目的**: Salesforce のリファクタリングと AI 協働開発を学ぶ

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
├── IMPLEMENTATION_GUIDE.md   # 実装指示書
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
git clone https://github.com/fujiwarayoshiki2001/sf-ai-development.git
cd sf-ai-development
```

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
sf project deploy start --target-org lead-scoring-base
```

### 5. シードデータの投入

```bash
bash data/load-data.sh
```

### 6. 権限セットの割り当て

```bash
sf org assign permset --name Lead_Management_User --target-org lead-scoring-base
```

### 7. 組織を開く

```bash
sf org open --target-org lead-scoring-base
```

---

## システム構成

### Apex クラス（11個 + トリガー 3個）

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
| LeadConstants | 定数 |
| TestDataFactory | テストデータファクトリ |

### Flow（2個）

| Flow 名 | 種類 | 役割 |
|---|---|---|
| Lead_Status_Update_Flow | スケジュール | 古いリードのステータス更新 |
| Lead_Validation_Flow | レコードトリガー | バリデーション補助 |

### LWC（5個）

| コンポーネント | 配置場所 | 役割 |
|---|---|---|
| leadList | カスタムタブ | リード一覧 |
| leadSearch | カスタムタブ | 高度な検索 |
| leadScoreCard | Lead レコードページ | 3軸スコア表示 |
| leadDetail | カスタムタブ | リード詳細 |
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
[ブランチ戦略]
- main: 本番相当（常にデプロイ可能）
- develop: 統合検証ブランチ
- feature/機能名: 新機能
- bugfix/バグ名: バグ修正
- refactor/対象: リファクタリング

[ワークフロー]
1. feature ブランチで作業
2. PR を作成（develop へ）
3. レビューを受ける
4. マージ後、ブランチを削除
```

---

## Claude Code との協働

このプロジェクトは **Claude Code** を活用して開発・リファクタを行います。

### 起動方法

```bash
# プロジェクトルートで
claude
```

`CLAUDE.md` が自動で読み込まれ、プロジェクトのルールを理解した状態で会話が始まります。

### 主なスラッシュコマンド

| コマンド | 用途 |
|---|---|
| `/review` | コードレビュー |
| `/refactor` | リファクタリングの提案 |
| `/test` | テストクラスの生成 |
| `/design` | 設計について議論 |
| `/soql` | SOQL の最適化 |
| `/security` | セキュリティチェック |
| `/error-handling` | エラーハンドリングのレビュー |

詳細は `.claude/commands/` を参照。

---

## 研修の流れ

### 全体スケジュール（10日間）

```
[Day 1]    環境構築、GitHub 操作、プロジェクト把握
[Day 2-3]  リファクタリング期（Apex・Flow を改善）
[Day 4]    要件定義（追加機能の企画）
[Day 5-9]  機能追加期（チーム開発、AI 協働）
[Day 10]   発表
```

詳細は別途配布する **カリキュラム概要** を参照。

---

## 関連ドキュメント

### このリポジトリ内

| ファイル | 内容 |
|---|---|
| `CLAUDE.md` | プロジェクトルール（Claude Code 用）|
| `IMPLEMENTATION_GUIDE.md` | 実装指示書（詳細な仕様）|
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
