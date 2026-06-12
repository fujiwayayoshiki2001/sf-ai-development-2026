# CLAUDE.md - プロジェクトルール

> **プロジェクト名**: リード管理・スコアリングシステム
> **目的**: 2026年度 AI駆動開発研修のベースシステム
> **対象**: Claude Code がこのプロジェクトで作業する際のガイドライン

このファイルは、Claude Code がこのプロジェクトを理解し、適切に作業するための指示を含みます。
セッション開始時に自動的に読み込まれます。

---

## 1. プロジェクト概要

### システム概要

リードを 3 つの軸（属性・行動・興味）で評価し、スコアの高い順に優先順位を可視化するシステム。

```
[3軸スコアリング]
属性スコア（最大100点）+ 行動スコア（最大120点・時間減衰込み）
                       + 興味スコア（最大80点）
                       = 最終スコア（最大300点）
```

### 主要なデータソース

| 軸 | データソース | 種類 |
|---|---|---|
| 属性 | Lead レコード自身 | 標準 |
| 行動 | CampaignMember | 標準 |
| 興味 | Lead_Interest__c | カスタム |

---

## 2. プロジェクトの状態

このプロジェクトは **研修教材** であり、現在のコードベースには **意図的に問題のあるコード** が含まれています。

```
[このプロジェクトの2つのフェーズ]

Phase A: ベースシステム実装フェーズ
   └ 講師が「悪いコード」を含むベースシステムを作る
   
Phase B: 研修フェーズ（受講者がリファクタリング）
   └ 受講者が AI と協働で問題を発見・改善する
```

詳細は `IMPLEMENTATION_GUIDE.md` を参照してください。

---

## 3. 技術スタック

```
[プラットフォーム]
- Salesforce Platform (API Version 62.0)
- Sales Cloud / Lightning Experience

[開発環境]
- Salesforce DX
- Salesforce CLI (sf)
- スクラッチ組織での開発

[言語・フレームワーク]
- Apex（バックエンドロジック）
- Lightning Web Components (LWC)（フロントエンド）
- Flow（宣言的ロジック）
- SOQL（クエリ言語）

[開発ツール]
- VS Code + Salesforce Extension Pack
- Git / GitHub
- Claude Code（このAI）
```

---

## 4. コーディング規約

### 4-1. Apex の規約

#### 命名規則

```
[クラス名]
- PascalCase
- 名詞または名詞句
- 役割を明確に示す
例: LeadScoringService, LeadAttributeScorer

[メソッド名]
- camelCase
- 動詞で始まる
例: calculateScore, getLeadList, validateEmail

[変数名]
- camelCase
- 意味のある名前を使う
- 1文字変数（i, j, k 等のループカウンタ以外）は使わない
良い例: List<Lead> highScoreLeads, Integer attemptCount
悪い例: List<Lead> a, Integer b

[定数]
- ALL_CAPS_SNAKE_CASE
- LeadConstants クラスに集約
例: HOT_THRESHOLD, MAX_RETRY_COUNT
```

#### コードスタイル

```apex
// クラス宣言は with sharing を基本に
public with sharing class LeadService {
    
    // 定数は static final で
    private static final Integer DEFAULT_LIMIT = 100;
    
    // メソッドの引数が多い場合は改行
    public static Lead createLead(
        String firstName,
        String lastName,
        String company,
        String email
    ) {
        // 実装
    }
}
```

#### SOQL の規約

```apex
// 必須: WITH SECURITY_ENFORCED を使う
List<Lead> leads = [
    SELECT Id, Name, Score__c
    FROM Lead
    WHERE Lead_Category__c = 'Hot'
    WITH SECURITY_ENFORCED
    ORDER BY Score__c DESC
    LIMIT 100
];

// 動的 SOQL は String.escapeSingleQuotes() でエスケープ
String searchTerm = String.escapeSingleQuotes(userInput);
String query = 'SELECT Id FROM Lead WHERE Name LIKE \'%' + searchTerm + '%\'';
```

#### DML の規約

```apex
// バルク化を意識
// 悪い例: ループ内 DML
for (Lead lead : leads) {
    update lead;  // ❌
}

// 良い例: バルク DML
update leads;  // ✅

// 必要に応じて CRUD/FLS チェック
if (Schema.sObjectType.Lead.isUpdateable()) {
    update leads;
}
```

#### エラーハンドリング

```apex
try {
    // 処理
} catch (DmlException e) {
    // 具体的な例外をキャッチ
    throw new AuraHandledException('保存に失敗しました: ' + e.getMessage());
} catch (Exception e) {
    // 想定外の例外
    System.debug(LoggingLevel.ERROR, 'Unexpected: ' + e.getMessage());
    throw e;
}
```

### 4-2. LWC の規約

#### コンポーネント名

```
[ファイル名]
- camelCase
例: leadList, leadScoreCard, leadInterestRadar

[コンポーネント参照]
- HTMLでは kebab-case
<c-lead-list></c-lead-list>
```

#### JavaScript

```javascript
import { LightningElement, wire, api } from 'lwc';
import getLeadList from '@salesforce/apex/LeadController.getLeadList';

export default class LeadList extends LightningElement {
    @api recordId;
    
    @wire(getLeadList, { category: '$category' })
    wiredLeads({ error, data }) {
        if (data) {
            this.leads = data;
        } else if (error) {
            this.error = error;
        }
    }
}
```

#### 必須事項

```
✓ @wire を優先的に使う（imperative call は必要時のみ）
✓ Apex 呼び出しのエラーハンドリングを必ず実装
✓ アクセシビリティ（aria-label 等）を意識
✓ SLDS（Salesforce Lightning Design System）クラスを使う
✓ ハードコードされた CSS は避ける
```

### 4-3. Flow の規約

#### 命名規則

```
[Flow 名]
- スネークケース + 役割
例: Lead_Status_Update_Flow, Lead_Validation_Flow

[要素名]
- 意味のある名前を使う（"Decision_1" などのデフォルト名は避ける）
例: Check_Stale_Leads, Update_Lead_Status_to_Stale
```

#### 設計指針

```
✓ バルク化を意識（ループ内 DML は避ける）
✓ フェイルパス（Fault Path）を必ず定義
✓ ハードコードを避け、カスタムラベルやカスタム設定を使う
✓ 複雑なロジックは Apex に任せ、Flow は宣言的な処理に専念
```

---

## 5. プロジェクトの構造

### ディレクトリ構成

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
├── CLAUDE.md                 # このファイル
├── IMPLEMENTATION_GUIDE.md   # 実装指示書
├── README.md                 # プロジェクト概要
└── sfdx-project.json         # Salesforce DX 設定
```

### 主要ファイル

| ファイル | 役割 |
|---|---|
| `CLAUDE.md` | このファイル。プロジェクトルール |
| `IMPLEMENTATION_GUIDE.md` | 実装の詳細仕様 |
| `README.md` | プロジェクト概要 |
| `sfdx-project.json` | Salesforce DX プロジェクト設定 |

---

## 6. Apex クラスの責務分離

### クラスの階層

```
[呼び出される側]                  [呼び出す側]

LeadController (LWC窓口)
        ↓
LeadService (ビジネスロジック)
        ↓
LeadScoringService (スコア統括)
        ↓
LeadAttributeScorer (属性スコア)
LeadBehaviorScorer (行動スコア)
LeadInterestScorer (興味スコア)

LeadValidator (バリデーション)
LeadTriggerHandler (トリガーから呼ばれる)
LeadConstants (定数)
```

### 各クラスの責務

| クラス | 責務 | 呼ぶ側 | 呼ばれる |
|---|---|---|---|
| LeadController | LWC との接続 | LWC | LeadService |
| LeadService | ビジネスロジック中核 | Controller, Trigger | Scoring, Validator |
| LeadScoringService | 3軸スコアの統括 | Service | 各 Scorer |
| LeadAttributeScorer | 属性スコア計算 | Scoring | - |
| LeadBehaviorScorer | 行動スコア計算 | Scoring | - |
| LeadInterestScorer | 興味スコア計算 | Scoring | - |
| LeadValidator | バリデーション | Service, Handler | - |
| LeadTriggerHandler | トリガーハンドリング | Trigger | Service |

### 守るべき設計原則

```
✓ 単一責任の原則（SRP）
   1クラス = 1責務

✓ 依存の方向は一方向
   上位レイヤーが下位レイヤーを呼ぶ
   逆方向の依存はNG

✓ Trigger は薄く保つ
   Trigger 内にロジックを書かず、Handler に委譲

✓ Service 層がビジネスロジックの中心
   Controller には最小限の処理だけ
```

---

## 7. データモデル

### Lead オブジェクト（標準 + カスタム項目）

#### 主要なカスタム項目

| 項目 | 型 | 用途 |
|---|---|---|
| `Score__c` | Number(3) | 最終スコア |
| `Attribute_Score__c` | Number(3) | 属性スコア |
| `Behavior_Score__c` | Number(5,2) | 行動スコア（時間減衰込み）|
| `Interest_Score__c` | Number(3) | 興味スコア |
| `Lead_Category__c` | Picklist | Hot/Warm/Cold/Low |
| `Score_Last_Calculated__c` | DateTime | 最終計算時刻 |
| `Last_Action_Date__c` | Date | 最終アクション日 |

### Lead_Interest__c（カスタムオブジェクト）

```
リードの興味・関心を構造化して記録

[項目]
- Lead__c (主従関係)
- Interest_Topic__c (選択リスト)
- Interest_Level__c (数値 1-100)
- Detected_Date__c (日付)
- Source__c (テキスト)
- Notes__c (テキストエリア)
```

### 標準オブジェクトの活用

| 標準オブジェクト | 用途 |
|---|---|
| CampaignMember | リードのキャンペーン参加履歴 |
| Campaign | マーケティングキャンペーン |
| Task | 営業の活動記録 |
| Event | 商談・ミーティング |

---

## 8. 重要なビジネスロジック

### スコア計算の流れ

```
[新規リード作成 or 更新]
   ↓
Lead Trigger が発火
   ↓
LeadTriggerHandler が処理を受ける
   ↓
LeadScoringService.calculateScore() を呼び出し
   ├ LeadAttributeScorer.calculate() → 属性スコア
   ├ LeadBehaviorScorer.calculate() → 行動スコア
   └ LeadInterestScorer.calculate() → 興味スコア
   ↓
合計を Score__c に保存
   ↓
カテゴリを判定して Lead_Category__c を更新
```

### カテゴリ判定の閾値

```
180+ : Hot   (即時対応)
100-179: Warm (営業フォロー)
50-99 : Cold (育成フェーズ)
0-49 : Low  (低優先度)
```

### 時間減衰の計算

```
減衰係数 = 0.95 ^ 経過日数

[計算例]
- 当日: 1.00 (100%)
- 7日前: 0.70 (70%)
- 14日前: 0.49 (49%)
- 30日前: 0.21 (21%)
```

---

## 9. テスト方針

### テストカバレッジ

```
[必須]
✓ Salesforce のデプロイ要件: 75% 以上
✓ 各 Apex クラスに対応するテストクラスを作成

[推奨]
✓ 単体テスト 90% 以上
✓ バルクテスト（200件処理）を必ず含める
✓ ポジティブケースとネガティブケースの両方
```

### テストクラスの書き方

```apex
@isTest
private class LeadServiceTest {
    
    @TestSetup
    static void setup() {
        // テストデータを準備
        List<Lead> leads = TestDataFactory.createLeads(10);
        insert leads;
    }
    
    @isTest
    static void testGetLeadsByCategory() {
        Test.startTest();
        List<Lead> result = LeadService.getLeadsByCategory('Hot');
        Test.stopTest();
        
        System.assertEquals(5, result.size(), 'Hot リードが 5件あるべき');
    }
    
    @isTest
    static void testBulkOperation() {
        // 200件のバルクテスト
        List<Lead> leads = TestDataFactory.createLeads(200);
        
        Test.startTest();
        insert leads;
        Test.stopTest();
        
        // ガバナ制限を超えないことを確認
    }
}
```

### NG パターン

```
✗ @isTest(SeeAllData=true) を使う
✗ @TestSetup を使わず毎回データを作り直す
✗ アサーションなし
✗ ネガティブケースなし
✗ バルクテストなし
```

---

## 10. セキュリティ

### 必ず守ること

```
✓ SOQL に WITH SECURITY_ENFORCED を付ける
✓ ユーザー入力は String.escapeSingleQuotes() でエスケープ
✓ CRUD/FLS チェック (Schema.sObjectType.X.isXxx())
✓ シェアリングルール (with sharing を基本に)
✓ Apex REST / Lightning Out など外部公開時は特に注意
```

### 避けるべき

```
✗ without sharing の不必要な使用
✗ ユーザー入力を直接 SOQL に埋め込む
✗ 認証なしのアクセス
✗ ハードコードされた認証情報
```

---

## 11. パフォーマンス

### ガバナ制限を意識

```
[よくある制限]
- SOQL: 100/トランザクション
- DML: 150/トランザクション
- ヒープサイズ: 6MB (同期), 12MB (非同期)
- CPU時間: 10秒 (同期)
- レコード数: 50,000/SOQL

[対策]
✓ ループ内 SOQL/DML は禁止
✓ Map を使った効率的なクエリ
✓ LIMIT 句で取得件数を制限
✓ 200件以上はバッチ処理を検討
```

### バルク化のパターン

```apex
// 悪い例
public static void updateLeads(List<Lead> leads) {
    for (Lead lead : leads) {
        List<CampaignMember> members = [
            SELECT Id FROM CampaignMember WHERE LeadId = :lead.Id
        ];  // ❌ ループ内 SOQL
        // 処理
    }
}

// 良い例
public static void updateLeads(List<Lead> leads) {
    Set<Id> leadIds = new Map<Id, Lead>(leads).keySet();
    
    Map<Id, List<CampaignMember>> membersByLead = new Map<Id, List<CampaignMember>>();
    for (CampaignMember cm : [
        SELECT Id, LeadId FROM CampaignMember 
        WHERE LeadId IN :leadIds
        WITH SECURITY_ENFORCED
    ]) {
        if (!membersByLead.containsKey(cm.LeadId)) {
            membersByLead.put(cm.LeadId, new List<CampaignMember>());
        }
        membersByLead.get(cm.LeadId).add(cm);
    }
    
    for (Lead lead : leads) {
        List<CampaignMember> members = membersByLead.get(lead.Id);
        // 処理
    }
}
```

---

## 12. Git の運用

### ブランチ戦略

```
[基本ブランチ]
- main: 本番相当（常にデプロイ可能）
- develop: 統合検証ブランチ

[作業ブランチ]
- feature/機能名: 新機能の追加
- bugfix/バグ名: バグ修正
- refactor/対象: リファクタリング

[ブランチ命名例]
feature/lead-search
bugfix/score-calculation-null
refactor/lead-controller
```

### コミットメッセージ

```
[フォーマット]
type: 簡潔な説明 (50文字以内)

詳細な説明（必要に応じて）

[type の種類]
- feat: 新機能
- fix: バグ修正
- refactor: リファクタリング
- test: テスト追加
- docs: ドキュメント
- style: コードスタイル変更
- chore: その他の雑務

[例]
feat: リード検索機能を追加

LeadController に searchLeads メソッドを追加。
LWC から呼び出して名前と会社名で検索できる。
```

### プルリクエスト

```
[ルール]
✓ feature ブランチから develop へ
✓ 必ずレビューを受ける
✓ テストが全てパスすることを確認
✓ コンフリクトがない状態でマージ
✓ マージ後はブランチを削除
```

---

## 13. Claude Code との協働ルール

### 作業の進め方

```
1. ユーザーの指示を理解する
   - 不明点があれば必ず質問する
   - 推測で進めない

2. 計画を立てる
   - 何をするかを明確にする
   - ユーザーに合意を取る

3. 実装する
   - このプロジェクトのルールに従う
   - コーディング規約を守る

4. 動作確認する
   - 自分でビルド・テストを実行
   - エラーがあれば修正

5. 説明する
   - 何をしたかを明確に報告
   - 注意点があれば伝える
```

### 守るべきこと

```
✓ コミットせずに何かを書き換える前に、ユーザーに確認
✓ 大規模な変更は計画を見せて合意を取る
✓ テストを実行できる時は必ず実行
✓ エラーが出たら隠さず報告
✓ 完璧主義に陥らない（小さく動かして検証）
```

### 避けるべきこと

```
✗ 勝手にライブラリを追加
✗ 勝手にプロジェクト構造を変える
✗ コードを「動くから良い」で終わらせる
✗ テストを書かずに「完了」と報告
✗ エラーを隠す
```

---

## 14. スラッシュコマンド

このプロジェクトには以下のカスタムスラッシュコマンドが用意されています。
`/コマンド名` で実行できます。

| コマンド | 用途 |
|---|---|
| `/review` | コードレビュー（このプロジェクトの観点で）|
| `/refactor` | リファクタリングの提案 |
| `/test` | テストクラスの生成 |
| `/design` | 設計について議論 |
| `/soql` | SOQL クエリの最適化 |
| `/naming` | 命名のレビュー |
| `/security` | セキュリティチェック |
| `/error-handling` | エラーハンドリングのレビュー |
| `/pr` | プルリクエスト用の説明文を生成 |
| `/explain` | コードの解説（受講者向け）|

詳細は `.claude/commands/` ディレクトリ参照。

---

## 15. よくある作業パターン

### 新しい Apex クラスを作る

```
1. クラス名を決める（責務に応じて）
2. force-app/main/default/classes/ に配置
3. クラスファイル (.cls) とメタデータファイル (.cls-meta.xml) を作成
4. with sharing を基本に
5. テストクラスも同時に作成
```

### SOQL を書くとき

```
1. WITH SECURITY_ENFORCED を必ず付ける
2. LIMIT 句で件数を制限
3. ORDER BY で順序を明確に
4. WHERE 句で絞り込みを徹底
```

### LWC を作る

```
1. lwc/コンポーネント名/ ディレクトリを作る
2. .js, .html, .css, .js-meta.xml を作成
3. @wire でデータ取得（imperative call は必要時のみ）
4. エラーハンドリングを忘れない
5. SLDS クラスを使う
```

### デプロイする

```bash
# スクラッチ組織にデプロイ
sf project deploy start -o my-scratch

# 特定のメタデータのみ
sf project deploy start -d force-app/main/default/classes -o my-scratch

# テストを含む
sf project deploy start -l RunLocalTests -o my-scratch
```

---

## 16. トラブルシューティング

### よくあるエラーと対処

#### "System.LimitException: Too many SOQL queries: 101"

```
[原因]
ループ内で SOQL を実行している

[対処]
ループ外でまとめてクエリ → Map で関連付け
```

#### "FIELD_INTEGRITY_EXCEPTION"

```
[原因]
必須項目が空、または値が不正

[対処]
バリデーションを確認、必須項目を埋める
```

#### "Code coverage is below 75%"

```
[原因]
テストカバレッジが不足

[対処]
テストクラスを追加、未カバーの行を確認
```

#### "Insufficient access rights"

```
[原因]
権限不足

[対処]
権限セットの確認、CRUD/FLS の確認
```

---

## 17. 参考リンク

### Salesforce 公式ドキュメント

- [Apex Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/)
- [Lightning Web Components Developer Guide](https://developer.salesforce.com/docs/component-library/documentation/en/lwc)
- [SOQL Reference](https://developer.salesforce.com/docs/atlas.en-us.soql_sosl.meta/soql_sosl/)
- [Apex Best Practices](https://developer.salesforce.com/wiki/apex_code_best_practices)

### 設計の参考

- [Apex Recipes](https://github.com/trailheadapps/apex-recipes)
- [LWC Recipes](https://github.com/trailheadapps/lwc-recipes)
- [Salesforce Architects Site](https://architect.salesforce.com/)

### 研修関連

- ベースシステム仕様書: `ベースシステム仕様書_v2.md`
- 実装指示書: `IMPLEMENTATION_GUIDE.md`
- 環境構築手順書: `AI駆動開発_環境構築手順書_v2.md`

---

## 18. このファイルの更新

```
[更新ルール]
- プロジェクトの方針が変わったら更新
- 新しいパターンが見つかったら追加
- 受講者からのフィードバックを反映

[更新の流れ]
1. 変更内容を明確化
2. レビューを受ける
3. プルリクエストでマージ
```




---

最終更新: 2026年9月
バージョン: 1.0
