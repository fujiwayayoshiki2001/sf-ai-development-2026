# リード管理・スコアリングシステム 実装指示書（クリーン版）

> **対象読者**: Claude Code（このドキュメントを読んで実装する AI 開発者）
> **目的**: 2026年度 AI駆動開発研修のベースシステム（クリーンコード版）を実装
> **方針**: Salesforce のベストプラクティスに完全に従った「お手本」となるコードを作成

---

## 0. このドキュメントの位置付け

このシステムは **段階的に作られます**。

```
[Phase A: 正しいコード版を作る]  ←★ このドキュメントの対象
   └ Salesforce のベストプラクティスに完全準拠
   └ テストカバレッジ 90%+
   └ ガバナ制限を完全クリア
   └ セキュリティを完璧に確保
   └ Git タグ: v1.0-clean

[Phase B: 研修用に問題を仕込む]  ← 別ドキュメントで後日対応
   └ 正しいコードから意図的に劣化させる
   └ 受講者のリファクタ題材になる
   └ Git タグ: v1.0-with-issues
```

**このドキュメントでは、Phase A（正しいコード版）の実装のみを扱います。**
「悪いコード」を仕込む話は一切出てきません。
**Claude Code はベストプラクティスのみを使ってください。**

---

## 1. プロジェクト概要

### システム名

リード管理・スコアリングシステム (Lead Scoring System)

### 目的

リードを 3 つの軸（属性・行動・興味）で評価し、スコアの高い順に優先順位を可視化する。

### 3 軸スコアリング

| 軸 | データソース | 最大点数 |
|---|---|---|
| 属性スコア | Lead レコード自身 | 100 点 |
| 行動スコア | CampaignMember（標準）| 120 点（時間減衰込み）|
| 興味スコア | Lead_Interest__c（カスタム）| 80 点 |
| **最終スコア** | 上記の合算 | **300 点** |

### カテゴリ判定

| 最終スコア | カテゴリ |
|---|---|
| 180+ | Hot |
| 100-179 | Warm |
| 50-99 | Cold |
| 0-49 | Low |

---

## 2. 守るべきベストプラクティス

実装する全コードに以下を適用してください。

### 2-1. Apex のベストプラクティス

#### バルク化を徹底

```apex
// すべてのメソッドは List / Set / Map で複数件処理に対応
// 1件メソッドがある場合も、内部でバルクメソッドを呼ぶ形にする

// 良い例
public static Map<Id, Decimal> calculateScores(Set<Id> leadIds) {
    // 一度のクエリで全データ取得
    Map<Id, Decimal> scoreMap = new Map<Id, Decimal>();
    // ループ内で SOQL/DML は絶対にしない
    return scoreMap;
}

public static Decimal calculateScore(Id leadId) {
    // バルクメソッドを呼ぶ
    return calculateScores(new Set<Id>{leadId}).get(leadId);
}
```

#### SOQL は必ず WITH SECURITY_ENFORCED

```apex
List<Lead> leads = [
    SELECT Id, Name, Score__c
    FROM Lead
    WHERE Lead_Category__c = :category
    WITH SECURITY_ENFORCED      // ← 必須
    ORDER BY Score__c DESC
    LIMIT :limitSize
];
```

#### 動的 SOQL は必ずエスケープ

```apex
// 動的 SOQL を使う場合
String escaped = String.escapeSingleQuotes(userInput);
String query = 'SELECT Id FROM Lead WHERE Name LIKE \'%' + escaped + '%\' WITH SECURITY_ENFORCED';
List<Lead> results = Database.query(query);
```

#### CRUD/FLS チェック

```apex
// DML 前にチェック
if (!Schema.sObjectType.Lead.isUpdateable()) {
    throw new AuraHandledException('リードの更新権限がありません');
}
update leads;
```

#### エラーハンドリング

```apex
try {
    // 処理
} catch (DmlException e) {
    System.debug(LoggingLevel.ERROR, 'DML Error: ' + e.getMessage());
    throw new AuraHandledException('保存に失敗しました: ' + e.getMessage());
} catch (Exception e) {
    System.debug(LoggingLevel.ERROR, 'Unexpected Error: ' + e.getMessage() + '\n' + e.getStackTraceString());
    throw new AuraHandledException('予期しないエラーが発生しました');
}
```

#### 定数とカスタムメタデータの活用

```apex
// 定数は LeadConstants クラスに集約
public class LeadConstants {
    public static final Integer HOT_THRESHOLD = 180;
    public static final Integer WARM_THRESHOLD = 100;
    public static final Integer COLD_THRESHOLD = 50;
}

// 重みはカスタムメタデータから取得
List<Lead_Scoring_Config__mdt> configs = Lead_Scoring_Config__mdt.getAll().values();
```

#### 命名規則

```
クラス名: PascalCase、名詞、役割を明確に
メソッド名: camelCase、動詞で始まる
変数名: 意味のある名前、camelCase
定数: ALL_CAPS_SNAKE_CASE

良い例: List<Lead> highScoreLeads, calculateAttributeScore()
悪い例: List<Lead> a, doIt()
```

#### 再帰トリガー対策

```apex
public class LeadTriggerHandler {
    // 再帰防止フラグ
    private static Boolean isRecursing = false;
    
    public static void afterUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        if (isRecursing) return;
        isRecursing = true;
        try {
            // 処理
        } finally {
            isRecursing = false;
        }
    }
    
    // テスト時のバイパス用
    @TestVisible
    public static Boolean bypassTrigger = false;
}
```

### 2-2. Flow のベストプラクティス

```
✓ レコードトリガー Flow は Fast Field Updates を優先
✓ ループ内 DML 禁止（Get → Process → Update を一回ずつ）
✓ フェイルパス（Fault Path）を必ず定義
✓ ハードコードを避ける（カスタムラベル・カスタム設定を使用）
✓ 要素名を分かりやすく（"Decision_1" のような自動生成名は使わない）
✓ 複雑なロジックは Apex に任せる
```

### 2-3. LWC のベストプラクティス

```
✓ @wire を優先（imperative call は必要時のみ）
✓ エラーハンドリングを必ず実装
✓ アクセシビリティ（aria-label 等）を考慮
✓ SLDS クラスを使用
✓ ハードコードされた CSS を避ける
✓ コンポーネントの責務を1つに保つ
✓ getRecord / getFieldValue を活用（カスタム Apex 不要な場合）
```

### 2-4. テストのベストプラクティス

```
✓ @TestSetup でテストデータを準備
✓ SeeAllData=true は絶対に使わない
✓ TestDataFactory パターンを使用
✓ ポジティブ・ネガティブの両方をテスト
✓ バルクテスト（200件処理）を必ず含める
✓ アサーションを充実させる
✓ テストカバレッジ 90% 以上を目標
```

---

## 3. ディレクトリ構造

```
sf-ai-development/
├── force-app/main/default/
│   ├── applications/
│   │   └── Lead_Management.app-meta.xml
│   ├── classes/
│   │   ├── LeadController.cls
│   │   ├── LeadController.cls-meta.xml
│   │   ├── LeadService.cls
│   │   ├── LeadService.cls-meta.xml
│   │   ├── LeadScoringService.cls
│   │   ├── LeadScoringService.cls-meta.xml
│   │   ├── LeadAttributeScorer.cls
│   │   ├── LeadAttributeScorer.cls-meta.xml
│   │   ├── LeadBehaviorScorer.cls
│   │   ├── LeadBehaviorScorer.cls-meta.xml
│   │   ├── LeadInterestScorer.cls
│   │   ├── LeadInterestScorer.cls-meta.xml
│   │   ├── LeadValidator.cls
│   │   ├── LeadValidator.cls-meta.xml
│   │   ├── LeadTriggerHandler.cls
│   │   ├── LeadTriggerHandler.cls-meta.xml
│   │   ├── LeadConstants.cls
│   │   ├── LeadConstants.cls-meta.xml
│   │   ├── TestDataFactory.cls
│   │   ├── TestDataFactory.cls-meta.xml
│   │   ├── LeadControllerTest.cls
│   │   ├── LeadServiceTest.cls
│   │   ├── LeadScoringServiceTest.cls
│   │   ├── LeadAttributeScorerTest.cls
│   │   ├── LeadBehaviorScorerTest.cls
│   │   ├── LeadInterestScorerTest.cls
│   │   ├── LeadValidatorTest.cls
│   │   └── LeadTriggerTest.cls
│   ├── triggers/
│   │   ├── LeadTrigger.trigger
│   │   ├── LeadTrigger.trigger-meta.xml
│   │   ├── LeadInterestTrigger.trigger
│   │   ├── LeadInterestTrigger.trigger-meta.xml
│   │   ├── CampaignMemberTrigger.trigger
│   │   └── CampaignMemberTrigger.trigger-meta.xml
│   ├── flows/
│   │   ├── Lead_Status_Update_Flow.flow-meta.xml
│   │   └── Lead_Validation_Flow.flow-meta.xml
│   ├── lwc/
│   │   ├── leadList/
│   │   ├── leadSearch/
│   │   ├── leadScoreCard/
│   │   ├── leadDetail/
│   │   └── leadInterestRadar/
│   ├── objects/
│   │   ├── Lead/
│   │   │   └── fields/
│   │   ├── Lead_Interest__c/
│   │   └── Lead_Scoring_Config__mdt/
│   ├── customMetadata/
│   ├── permissionsets/
│   ├── tabs/
│   └── flexipages/
├── data/
│   ├── leads.json
│   ├── campaigns.json
│   ├── campaign-members.json
│   ├── interests.json
│   └── load-data.sh
└── README.md
```

---

## 4. データモデル

### 4-1. Lead オブジェクトのカスタム項目

#### Score__c

```xml
<fullName>Score__c</fullName>
<externalId>false</externalId>
<label>スコア</label>
<precision>3</precision>
<required>false</required>
<scale>0</scale>
<trackTrending>false</trackTrending>
<type>Number</type>
<unique>false</unique>
<defaultValue>0</defaultValue>
<description>3軸合算後の最終スコア</description>
```

#### Attribute_Score__c

```xml
<fullName>Attribute_Score__c</fullName>
<label>属性スコア</label>
<precision>3</precision>
<scale>0</scale>
<type>Number</type>
<defaultValue>0</defaultValue>
<description>属性のみのスコア（最大100）</description>
```

#### Behavior_Score__c

```xml
<fullName>Behavior_Score__c</fullName>
<label>行動スコア</label>
<precision>5</precision>
<scale>2</scale>
<type>Number</type>
<defaultValue>0</defaultValue>
<description>行動スコア（時間減衰込み、最大120）</description>
```

#### Interest_Score__c

```xml
<fullName>Interest_Score__c</fullName>
<label>興味スコア</label>
<precision>3</precision>
<scale>0</scale>
<type>Number</type>
<defaultValue>0</defaultValue>
<description>興味スコア（最大80）</description>
```

#### Lead_Category__c

```xml
<fullName>Lead_Category__c</fullName>
<label>カテゴリ</label>
<type>Picklist</type>
<valueSet>
    <valueSetDefinition>
        <value><fullName>Hot</fullName></value>
        <value><fullName>Warm</fullName></value>
        <value><fullName>Cold</fullName></value>
        <value><fullName>Low</fullName></value>
    </valueSetDefinition>
</valueSet>
<defaultValue>"Low"</defaultValue>
```

#### Score_Last_Calculated__c

```xml
<fullName>Score_Last_Calculated__c</fullName>
<label>スコア計算日時</label>
<type>DateTime</type>
<description>最後にスコアを計算した時刻</description>
```

#### Last_Action_Date__c

```xml
<fullName>Last_Action_Date__c</fullName>
<label>最終アクション日</label>
<type>Date</type>
<description>営業の最後のアクション日</description>
```

### 4-2. Lead_Interest__c カスタムオブジェクト

#### オブジェクト定義

```xml
<CustomObject>
    <label>リード興味</label>
    <pluralLabel>リード興味</pluralLabel>
    <deploymentStatus>Deployed</deploymentStatus>
    <enableReports>true</enableReports>
    <enableActivities>false</enableActivities>
    <enableHistory>true</enableHistory>
    <sharingModel>ControlledByParent</sharingModel>
    <nameField>
        <type>AutoNumber</type>
        <displayFormat>INT-{0000}</displayFormat>
    </nameField>
</CustomObject>
```

#### Lead__c（主従関係）

```xml
<fullName>Lead__c</fullName>
<label>リード</label>
<type>MasterDetail</type>
<referenceTo>Lead</referenceTo>
<required>true</required>
<relationshipName>Interests</relationshipName>
<relationshipLabel>興味領域</relationshipLabel>
<reparentableMasterDetail>false</reparentableMasterDetail>
<writeRequiresMasterRead>false</writeRequiresMasterRead>
```

#### Interest_Topic__c

```xml
<fullName>Interest_Topic__c</fullName>
<label>関心トピック</label>
<type>Picklist</type>
<required>true</required>
<valueSet>
    <valueSetDefinition>
        <value><fullName>データ統合</fullName></value>
        <value><fullName>業務効率化</fullName></value>
        <value><fullName>セキュリティ強化</fullName></value>
        <value><fullName>コスト削減</fullName></value>
        <value><fullName>DX 推進</fullName></value>
        <value><fullName>既存システム置き換え</fullName></value>
        <value><fullName>クラウド移行</fullName></value>
        <value><fullName>自動化</fullName></value>
        <value><fullName>AI 活用</fullName></value>
        <value><fullName>ガバナンス強化</fullName></value>
    </valueSetDefinition>
</valueSet>
```

#### Interest_Level__c

```xml
<fullName>Interest_Level__c</fullName>
<label>関心度</label>
<type>Number</type>
<precision>3</precision>
<scale>0</scale>
<required>true</required>
<description>1〜100</description>
```

#### Detected_Date__c

```xml
<fullName>Detected_Date__c</fullName>
<label>検出日</label>
<type>Date</type>
```

#### Source__c

```xml
<fullName>Source__c</fullName>
<label>検出元</label>
<type>Text</type>
<length>255</length>
```

#### Notes__c

```xml
<fullName>Notes__c</fullName>
<label>備考</label>
<type>LongTextArea</type>
<length>32768</length>
<visibleLines>5</visibleLines>
```

### 4-3. Lead_Scoring_Config__mdt カスタムメタデータ

#### オブジェクト定義

```xml
<CustomObject>
    <label>Lead Scoring Config</label>
    <pluralLabel>Lead Scoring Configs</pluralLabel>
</CustomObject>
```

#### Score_Type__c

```xml
<fullName>Score_Type__c</fullName>
<label>Score Type</label>
<type>Text</type>
<length>50</length>
<description>Attribute / Behavior / Interest</description>
```

#### Key__c

```xml
<fullName>Key__c</fullName>
<label>Key</label>
<type>Text</type>
<length>255</length>
<description>評価キー</description>
```

#### Weight__c

```xml
<fullName>Weight__c</fullName>
<label>Weight</label>
<type>Number</type>
<precision>5</precision>
<scale>2</scale>
<description>重み</description>
```

#### Is_Active__c

```xml
<fullName>Is_Active__c</fullName>
<label>Is Active</label>
<type>Checkbox</type>
<defaultValue>true</defaultValue>
```

#### 初期データ（CustomMetadata レコード）

属性スコア用：

| DeveloperName | Score_Type__c | Key__c | Weight__c |
|---|---|---|---|
| Attr_Industry_Tech | Attribute | Technology | 15 |
| Attr_Industry_Manuf | Attribute | Manufacturing | 15 |
| Attr_Industry_Finance | Attribute | Financial Services | 10 |
| Attr_Size_Large | Attribute | NumberOfEmployees_1000+ | 20 |
| Attr_Size_Medium | Attribute | NumberOfEmployees_100-999 | 10 |
| Attr_Size_Small | Attribute | NumberOfEmployees_10-99 | 5 |
| Attr_Title_C | Attribute | Title_C-level | 30 |
| Attr_Title_VP | Attribute | Title_VP | 25 |
| Attr_Title_Manager | Attribute | Title_Manager | 15 |
| Attr_Source_Webinar | Attribute | Webinar | 20 |
| Attr_Source_TradeShow | Attribute | Trade Show | 15 |
| Attr_Source_Web | Attribute | Web | 10 |

行動スコア用：

| DeveloperName | Score_Type__c | Key__c | Weight__c |
|---|---|---|---|
| Beh_Webinar_Registered | Behavior | Webinar_Registered | 10 |
| Beh_Webinar_Attended | Behavior | Webinar_Attended | 30 |
| Beh_TradeShow_Registered | Behavior | Trade Show_Registered | 10 |
| Beh_TradeShow_Visited | Behavior | Trade Show_Visited | 25 |
| Beh_Email_Responded | Behavior | Email_Responded | 5 |
| Beh_WhitePaper_DL | Behavior | White Paper_Downloaded | 15 |
| Beh_Demo_Requested | Behavior | Demo Request_Submitted | 50 |

興味スコア用：

| DeveloperName | Score_Type__c | Key__c | Weight__c |
|---|---|---|---|
| Int_DataIntegration | Interest | データ統合 | 1.5 |
| Int_DXPromotion | Interest | DX 推進 | 1.5 |
| Int_Security | Interest | セキュリティ強化 | 1.2 |
| Int_Efficiency | Interest | 業務効率化 | 1.0 |
| Int_CostReduction | Interest | コスト削減 | 1.0 |
| Int_SystemReplace | Interest | 既存システム置き換え | 1.5 |
| Int_CloudMigration | Interest | クラウド移行 | 1.3 |
| Int_Automation | Interest | 自動化 | 1.0 |
| Int_AI | Interest | AI 活用 | 1.5 |
| Int_Governance | Interest | ガバナンス強化 | 1.0 |

---

## 5. Apex クラスの実装仕様

### 5-1. LeadConstants.cls

#### 責務

プロジェクト全体で使う定数を集約する。

#### 実装

```apex
public class LeadConstants {
    // カテゴリ閾値
    public static final Integer HOT_THRESHOLD = 180;
    public static final Integer WARM_THRESHOLD = 100;
    public static final Integer COLD_THRESHOLD = 50;
    
    // カテゴリ値
    public static final String CATEGORY_HOT = 'Hot';
    public static final String CATEGORY_WARM = 'Warm';
    public static final String CATEGORY_COLD = 'Cold';
    public static final String CATEGORY_LOW = 'Low';
    
    // スコア上限
    public static final Integer ATTRIBUTE_MAX_SCORE = 100;
    public static final Integer BEHAVIOR_MAX_SCORE = 120;
    public static final Integer INTEREST_MAX_SCORE = 80;
    
    // 時間減衰
    public static final Decimal DECAY_FACTOR = 0.95;
    
    // ステータス更新
    public static final Integer STALE_DAYS = 30;
    public static final String STATUS_STALE = 'Stale';
    
    // スコアタイプ
    public static final String SCORE_TYPE_ATTRIBUTE = 'Attribute';
    public static final String SCORE_TYPE_BEHAVIOR = 'Behavior';
    public static final String SCORE_TYPE_INTEREST = 'Interest';
    
    // 業界・ソース等（必要に応じて）
    public static final String INDUSTRY_TECHNOLOGY = 'Technology';
    public static final String INDUSTRY_MANUFACTURING = 'Manufacturing';
    public static final String INDUSTRY_FINANCIAL = 'Financial Services';
}
```

---

### 5-2. LeadAttributeScorer.cls

#### 責務

Lead レコード自身の項目から属性スコアを計算する。

#### メソッドシグネチャ

```apex
public class LeadAttributeScorer {
    public static Decimal calculate(Lead lead);
    public static Map<Id, Decimal> calculateBulk(List<Lead> leads);
    private static Map<String, Decimal> getWeightMap();
}
```

#### 実装内容

```
1. カスタムメタデータから重みを取得（キャッシュ）
2. リードの各項目を評価:
   - Industry → 業界に応じた重み
   - NumberOfEmployees → 規模カテゴリの重み
   - Title → 役職に応じた重み（含有判定）
   - LeadSource → ソースに応じた重み
3. 合計を返す（最大 100 で頭打ち）
4. null チェックを徹底
5. 文字列比較は大文字小文字を無視（containsIgnoreCase / equalsIgnoreCase）
```

#### ベストプラクティスのポイント

```
✓ カスタムメタデータから重みを取得（ハードコード回避）
✓ Map による高速ルックアップ
✓ null チェック完備
✓ 大文字小文字を考慮した文字列比較
✓ バルク対応（calculateBulk）
✓ 上限値の制御
```

---

### 5-3. LeadBehaviorScorer.cls

#### 責務

CampaignMember を集計して行動スコアを計算する（時間減衰込み）。

#### メソッドシグネチャ

```apex
public class LeadBehaviorScorer {
    public static Decimal calculate(Id leadId);
    public static Map<Id, Decimal> calculateBulk(Set<Id> leadIds);
    private static Decimal calculateDecay(Date activityDate);
}
```

#### 実装内容

```
1. calculateBulk():
   - すべてのリードの CampaignMember を一度の SOQL で取得
   - WITH SECURITY_ENFORCED を付ける
   - Map<Id, List<CampaignMember>> でグルーピング
   
2. 各リードについて:
   - 各 CampaignMember の重みを取得（Campaign.Type + Status から）
   - 時間減衰係数を計算: 0.95 ^ Date.daysBetween()
   - 重み × 減衰係数 を合計
   - 最大 120 で頭打ち
   
3. calculate(leadId):
   - calculateBulk(Set<Id>{leadId}) を呼ぶ
```

#### コード例

```apex
public static Map<Id, Decimal> calculateBulk(Set<Id> leadIds) {
    Map<Id, Decimal> scoreMap = new Map<Id, Decimal>();
    if (leadIds == null || leadIds.isEmpty()) return scoreMap;
    
    // 初期化（全リードを 0 で初期化）
    for (Id leadId : leadIds) {
        scoreMap.put(leadId, 0);
    }
    
    // 一度のクエリで全 CampaignMember を取得
    List<CampaignMember> members = [
        SELECT Id, LeadId, Campaign.Type, Status, HasResponded, CreatedDate
        FROM CampaignMember
        WHERE LeadId IN :leadIds
        WITH SECURITY_ENFORCED
    ];
    
    // 重み Map をカスタムメタデータから取得
    Map<String, Decimal> weightMap = getBehaviorWeights();
    
    // 集計
    for (CampaignMember cm : members) {
        String key = cm.Campaign.Type + '_' + cm.Status;
        Decimal weight = weightMap.containsKey(key) ? weightMap.get(key) : 0;
        Decimal decay = calculateDecay(cm.CreatedDate.date());
        Decimal score = scoreMap.get(cm.LeadId) + (weight * decay);
        scoreMap.put(cm.LeadId, Math.min(score, LeadConstants.BEHAVIOR_MAX_SCORE));
    }
    
    return scoreMap;
}

private static Decimal calculateDecay(Date activityDate) {
    Integer daysAgo = activityDate.daysBetween(Date.today());
    if (daysAgo < 0) daysAgo = 0;
    return Math.pow(LeadConstants.DECAY_FACTOR.doubleValue(), daysAgo);
}
```

#### ベストプラクティスのポイント

```
✓ バルクメソッドが基本、単一メソッドは内部で呼ぶだけ
✓ ループ内 SOQL なし
✓ WITH SECURITY_ENFORCED 必須
✓ Date.daysBetween() による正確な日数計算
✓ カスタムメタデータからの重み取得
✓ 上限値の制御
✓ null チェック完備
```

---

### 5-4. LeadInterestScorer.cls

#### 責務

Lead_Interest__c を集計して興味スコアを計算する。

#### メソッドシグネチャ

```apex
public class LeadInterestScorer {
    public static Decimal calculate(Id leadId);
    public static Map<Id, Decimal> calculateBulk(Set<Id> leadIds);
    private static Map<String, Decimal> getTopicWeights();
}
```

#### 実装内容

```
1. calculateBulk():
   - すべてのリードの Lead_Interest__c を一度の SOQL で取得
   - WITH SECURITY_ENFORCED を付ける
   - リードごとにグルーピング
   
2. 各リードについて:
   - 各 Interest について Topic の重みを取得
   - Interest_Level × 重み を合計
   - 最大 80 で頭打ち
   
3. calculate(leadId):
   - calculateBulk(Set<Id>{leadId}) を呼ぶ
```

#### ベストプラクティスのポイント

```
✓ 必要な項目のみクエリ（Lead__r.Name 等は取得しない）
✓ ループ内 SOQL なし
✓ WITH SECURITY_ENFORCED 必須
✓ 文字列の正規化（trim()）
✓ 上限値の制御
✓ 同じ Topic が複数ある場合の扱いを明示（仕様: 単純合算）
```

---

### 5-5. LeadScoringService.cls

#### 責務

3 つの Scorer を統括し、最終スコアを計算して Lead を更新する。

#### メソッドシグネチャ

```apex
public class LeadScoringService {
    public static void calculateScore(Id leadId);
    public static void calculateScores(Set<Id> leadIds);
    public static String determineCategory(Decimal score);
}
```

#### 実装内容

```apex
public static void calculateScores(Set<Id> leadIds) {
    if (leadIds == null || leadIds.isEmpty()) return;
    
    // 一度のクエリでリードを取得
    Map<Id, Lead> leadMap = new Map<Id, Lead>([
        SELECT Id, Industry, NumberOfEmployees, Title, LeadSource
        FROM Lead
        WHERE Id IN :leadIds
        WITH SECURITY_ENFORCED
    ]);
    
    // 各 Scorer を呼び出し
    Map<Id, Decimal> attributeScores = LeadAttributeScorer.calculateBulk(leadMap.values());
    Map<Id, Decimal> behaviorScores = LeadBehaviorScorer.calculateBulk(leadIds);
    Map<Id, Decimal> interestScores = LeadInterestScorer.calculateBulk(leadIds);
    
    // 更新用リスト
    List<Lead> leadsToUpdate = new List<Lead>();
    
    for (Id leadId : leadIds) {
        Decimal attr = attributeScores.containsKey(leadId) ? attributeScores.get(leadId) : 0;
        Decimal beh = behaviorScores.containsKey(leadId) ? behaviorScores.get(leadId) : 0;
        Decimal inter = interestScores.containsKey(leadId) ? interestScores.get(leadId) : 0;
        Decimal total = attr + beh + inter;
        
        leadsToUpdate.add(new Lead(
            Id = leadId,
            Attribute_Score__c = attr,
            Behavior_Score__c = beh,
            Interest_Score__c = inter,
            Score__c = total,
            Lead_Category__c = determineCategory(total),
            Score_Last_Calculated__c = System.now()
        ));
    }
    
    // バルク update
    if (!leadsToUpdate.isEmpty()) {
        // 再帰防止
        LeadTriggerHandler.bypassTrigger = true;
        try {
            update leadsToUpdate;
        } finally {
            LeadTriggerHandler.bypassTrigger = false;
        }
    }
}

public static String determineCategory(Decimal score) {
    if (score >= LeadConstants.HOT_THRESHOLD) return LeadConstants.CATEGORY_HOT;
    if (score >= LeadConstants.WARM_THRESHOLD) return LeadConstants.CATEGORY_WARM;
    if (score >= LeadConstants.COLD_THRESHOLD) return LeadConstants.CATEGORY_COLD;
    return LeadConstants.CATEGORY_LOW;
}
```

#### ベストプラクティスのポイント

```
✓ バルク化されたメソッドを呼ぶ
✓ 一回の SOQL で必要なデータを取得
✓ バルク update
✓ 再帰防止フラグを適切に使用
✓ try-finally でフラグを必ずリセット
✓ 定数を使用（ハードコードなし）
✓ Map のキー存在チェック
```

---

### 5-6. LeadTriggerHandler.cls

#### 責務

Lead トリガーから呼ばれるハンドラ。

#### メソッドシグネチャ

```apex
public class LeadTriggerHandler {
    @TestVisible
    public static Boolean bypassTrigger = false;
    
    public static void beforeInsert(List<Lead> newLeads);
    public static void afterInsert(List<Lead> newLeads, Map<Id, Lead> newMap);
    public static void beforeUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap);
    public static void afterUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap, Map<Id, Lead> newMap);
}
```

#### 実装内容

```apex
public static void afterInsert(List<Lead> newLeads, Map<Id, Lead> newMap) {
    if (bypassTrigger) return;
    
    Set<Id> leadIds = newMap.keySet();
    LeadScoringService.calculateScores(leadIds);
}

public static void afterUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap, Map<Id, Lead> newMap) {
    if (bypassTrigger) return;
    
    // 属性関連項目が変わったリードのみ再計算
    Set<Id> leadsToRecalc = new Set<Id>();
    for (Lead newLead : newLeads) {
        Lead oldLead = oldMap.get(newLead.Id);
        if (isAttributeChanged(oldLead, newLead)) {
            leadsToRecalc.add(newLead.Id);
        }
    }
    
    if (!leadsToRecalc.isEmpty()) {
        LeadScoringService.calculateScores(leadsToRecalc);
    }
}

private static Boolean isAttributeChanged(Lead oldLead, Lead newLead) {
    return oldLead.Industry != newLead.Industry
        || oldLead.NumberOfEmployees != newLead.NumberOfEmployees
        || oldLead.Title != newLead.Title
        || oldLead.LeadSource != newLead.LeadSource;
}

public static void beforeInsert(List<Lead> newLeads) {
    LeadValidator.validate(newLeads);
}

public static void beforeUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap) {
    LeadValidator.validate(newLeads);
}
```

#### ベストプラクティスのポイント

```
✓ bypassTrigger フラグを使った再帰防止
✓ 変更検知（diff チェック）で不要な処理を回避
✓ バリデーションを before に集約
✓ スコア再計算を after に集約
✓ @TestVisible でテスト時のアクセスを許可
```

---

### 5-7. LeadTrigger.trigger

#### 実装

```apex
trigger LeadTrigger on Lead (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    if (LeadTriggerHandler.bypassTrigger) return;
    
    if (Trigger.isBefore) {
        if (Trigger.isInsert) LeadTriggerHandler.beforeInsert(Trigger.new);
        if (Trigger.isUpdate) LeadTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    } else if (Trigger.isAfter) {
        if (Trigger.isInsert) LeadTriggerHandler.afterInsert(Trigger.new, Trigger.newMap);
        if (Trigger.isUpdate) LeadTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap, Trigger.newMap);
    }
}
```

---

### 5-8. LeadInterestTrigger.trigger

#### 実装

```apex
trigger LeadInterestTrigger on Lead_Interest__c (
    after insert, after update, after delete, after undelete
) {
    Set<Id> leadIds = new Set<Id>();
    
    if (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete) {
        for (Lead_Interest__c interest : Trigger.new) {
            if (interest.Lead__c != null) leadIds.add(interest.Lead__c);
        }
    }
    
    if (Trigger.isDelete) {
        for (Lead_Interest__c interest : Trigger.old) {
            if (interest.Lead__c != null) leadIds.add(interest.Lead__c);
        }
    }
    
    if (!leadIds.isEmpty()) {
        LeadScoringService.calculateScores(leadIds);
    }
}
```

---

### 5-9. CampaignMemberTrigger.trigger

#### 実装

```apex
trigger CampaignMemberTrigger on CampaignMember (
    after insert, after update, after delete, after undelete
) {
    Set<Id> leadIds = new Set<Id>();
    
    if (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete) {
        for (CampaignMember cm : Trigger.new) {
            if (cm.LeadId != null) leadIds.add(cm.LeadId);
        }
    }
    
    if (Trigger.isDelete) {
        for (CampaignMember cm : Trigger.old) {
            if (cm.LeadId != null) leadIds.add(cm.LeadId);
        }
    }
    
    if (!leadIds.isEmpty()) {
        LeadScoringService.calculateScores(leadIds);
    }
}
```

---

### 5-10. LeadValidator.cls

#### 責務

Lead のバリデーション。

#### メソッドシグネチャ

```apex
public class LeadValidator {
    public static void validate(List<Lead> leads);
    public static void validateEmail(Lead lead);
    public static void validateRequiredFields(Lead lead);
    public static Map<String, List<Lead>> findDuplicatesByCompany(Set<String> companyNames);
}
```

#### 実装内容

```apex
public static void validate(List<Lead> leads) {
    // 重複チェック用に会社名を収集
    Set<String> companyNames = new Set<String>();
    for (Lead lead : leads) {
        if (String.isNotBlank(lead.Company)) {
            companyNames.add(lead.Company);
        }
    }
    
    // 一度のクエリで重複チェック
    Map<String, List<Lead>> duplicates = findDuplicatesByCompany(companyNames);
    
    for (Lead lead : leads) {
        validateRequiredFields(lead);
        validateEmail(lead);
        // 重複は警告のみ（エラーにしない）
        // 警告のロジックは UI 側で処理
    }
}

public static void validateRequiredFields(Lead lead) {
    if (String.isBlank(lead.LastName)) {
        lead.LastName.addError('姓は必須項目です');
    }
    if (String.isBlank(lead.Company)) {
        lead.Company.addError('会社名は必須項目です');
    }
}

public static void validateEmail(Lead lead) {
    if (String.isBlank(lead.Email)) return;
    
    // 標準的なメールアドレス形式の正規表現
    String pattern = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$';
    if (!Pattern.matches(pattern, lead.Email)) {
        lead.Email.addError('メールアドレスの形式が正しくありません');
    }
}

public static Map<String, List<Lead>> findDuplicatesByCompany(Set<String> companyNames) {
    Map<String, List<Lead>> result = new Map<String, List<Lead>>();
    if (companyNames.isEmpty()) return result;
    
    for (Lead lead : [
        SELECT Id, Name, Company
        FROM Lead
        WHERE Company IN :companyNames
        WITH SECURITY_ENFORCED
    ]) {
        if (!result.containsKey(lead.Company)) {
            result.put(lead.Company, new List<Lead>());
        }
        result.get(lead.Company).add(lead);
    }
    
    return result;
}
```

#### ベストプラクティスのポイント

```
✓ バルクメソッドの設計
✓ 重複チェックを一回の SOQL で実施
✓ WITH SECURITY_ENFORCED 必須
✓ addError() を使った標準的なバリデーション
✓ 正規表現でメールチェック
✓ null / blank チェック
```

---

### 5-11. LeadService.cls

#### 責務

Lead に対する一般的な操作を提供。

#### メソッドシグネチャ

```apex
public with sharing class LeadService {
    public static List<Lead> getLeadsByCategory(String category, Integer limitSize);
    public static List<Lead> searchLeads(String searchTerm, Integer limitSize);
    public static void updateLastActionDate(Set<Id> leadIds);
    public static List<Lead> getStaleLeads();
}
```

#### 実装内容

```apex
public static List<Lead> getLeadsByCategory(String category, Integer limitSize) {
    if (String.isBlank(category)) return new List<Lead>();
    if (limitSize == null || limitSize <= 0) limitSize = 50;
    if (limitSize > 200) limitSize = 200; // 上限
    
    return [
        SELECT Id, Name, Company, Title, Industry, 
               Score__c, Attribute_Score__c, Behavior_Score__c, Interest_Score__c,
               Lead_Category__c, Status
        FROM Lead
        WHERE Lead_Category__c = :category
        WITH SECURITY_ENFORCED
        ORDER BY Score__c DESC
        LIMIT :limitSize
    ];
}

public static List<Lead> searchLeads(String searchTerm, Integer limitSize) {
    if (String.isBlank(searchTerm)) return new List<Lead>();
    if (limitSize == null || limitSize <= 0) limitSize = 50;
    
    // エスケープして安全に
    String escaped = String.escapeSingleQuotes(searchTerm);
    String pattern = '%' + escaped + '%';
    
    return [
        SELECT Id, Name, Company, Score__c, Lead_Category__c
        FROM Lead
        WHERE Name LIKE :pattern OR Company LIKE :pattern
        WITH SECURITY_ENFORCED
        ORDER BY Score__c DESC
        LIMIT :limitSize
    ];
}

public static void updateLastActionDate(Set<Id> leadIds) {
    if (leadIds == null || leadIds.isEmpty()) return;
    
    List<Lead> leadsToUpdate = new List<Lead>();
    for (Id leadId : leadIds) {
        leadsToUpdate.add(new Lead(
            Id = leadId,
            Last_Action_Date__c = Date.today()
        ));
    }
    
    if (Schema.sObjectType.Lead.isUpdateable()) {
        update leadsToUpdate;
    } else {
        throw new AuraHandledException('リードの更新権限がありません');
    }
}

public static List<Lead> getStaleLeads() {
    Date thresholdDate = Date.today().addDays(-LeadConstants.STALE_DAYS);
    
    return [
        SELECT Id, Name, Last_Action_Date__c
        FROM Lead
        WHERE Last_Action_Date__c < :thresholdDate
        AND Status != :LeadConstants.STATUS_STALE
        WITH SECURITY_ENFORCED
    ];
}
```

#### ベストプラクティスのポイント

```
✓ with sharing 宣言
✓ WITH SECURITY_ENFORCED 必須
✓ パラメータ化クエリ（バインド変数）
✓ LIMIT 句で件数制限
✓ String.escapeSingleQuotes() でエスケープ（バインド変数も併用）
✓ CRUD/FLS チェック
✓ 定数の活用
✓ 入力バリデーション
```

---

### 5-12. LeadController.cls

#### 責務

LWC からの呼び出し窓口（@AuraEnabled メソッド）。

#### メソッドシグネチャ

```apex
public with sharing class LeadController {
    @AuraEnabled(cacheable=true)
    public static List<Lead> getLeadList(String category, Integer limitSize);
    
    @AuraEnabled(cacheable=true)
    public static List<Lead> searchLeads(String searchTerm);
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Decimal> getScoreBreakdown(Id leadId);
    
    @AuraEnabled(cacheable=true)
    public static List<Lead_Interest__c> getInterests(Id leadId);
    
    @AuraEnabled
    public static void recalculateScore(Id leadId);
}
```

#### 実装内容

```apex
@AuraEnabled(cacheable=true)
public static List<Lead> getLeadList(String category, Integer limitSize) {
    try {
        return LeadService.getLeadsByCategory(category, limitSize);
    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, 'getLeadList Error: ' + e.getMessage());
        throw new AuraHandledException('リスト取得に失敗しました');
    }
}

@AuraEnabled(cacheable=true)
public static Map<String, Decimal> getScoreBreakdown(Id leadId) {
    try {
        if (leadId == null) {
            throw new AuraHandledException('リード ID が指定されていません');
        }
        
        Lead lead = [
            SELECT Id, Score__c, Attribute_Score__c, Behavior_Score__c, Interest_Score__c
            FROM Lead
            WHERE Id = :leadId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        
        return new Map<String, Decimal>{
            'attribute' => lead.Attribute_Score__c,
            'behavior' => lead.Behavior_Score__c,
            'interest' => lead.Interest_Score__c,
            'total' => lead.Score__c
        };
    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, 'getScoreBreakdown Error: ' + e.getMessage());
        throw new AuraHandledException('スコア取得に失敗しました');
    }
}

@AuraEnabled
public static void recalculateScore(Id leadId) {
    try {
        if (leadId == null) {
            throw new AuraHandledException('リード ID が指定されていません');
        }
        LeadScoringService.calculateScores(new Set<Id>{leadId});
    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, 'recalculateScore Error: ' + e.getMessage());
        throw new AuraHandledException('スコア再計算に失敗しました');
    }
}
```

#### ベストプラクティスのポイント

```
✓ with sharing 宣言
✓ cacheable=true で読み取りメソッドは効率化
✓ 状態変更メソッドは cacheable=false
✓ AuraHandledException で適切にラップ
✓ null チェック
✓ ログ出力でデバッグ可能
✓ WITH SECURITY_ENFORCED 必須
```

---

## 6. Flow の実装仕様

### 6-1. Lead_Status_Update_Flow

#### 種類

Schedule-Triggered Flow

#### スケジュール

```
- Frequency: Daily
- Start Time: 02:00 AM
```

#### 処理内容

```
1. Get Records: 30日以上 Last_Action_Date__c が更新されていない Lead を取得
   - Status != 'Stale'
2. Update Records: Status を Stale に変更
   - Loop は使わず、collection 全体を一度に Update
3. Fault Path: エラー時にプラットフォーム管理者にメール通知
```

#### ベストプラクティスのポイント

```
✓ バルク化（コレクションで Update）
✓ Fault Path 定義
✓ 30日はカスタムラベルから取得（または定数）
✓ 要素名を意味のあるものに
   - "Get_Stale_Leads"
   - "Update_to_Stale_Status"
   - "Send_Error_Notification"
```

---

### 6-2. Lead_Validation_Flow

#### 種類

Record-Triggered Flow

#### トリガー

```
- Object: Lead
- Trigger: A record is created or updated
- Optimize for: Fast Field Updates
```

#### 処理内容

```
1. Decision: Email が空 OR Company が短い場合
2. Update Records: Flag 用カスタム項目を更新（任意）
```

**注意**: 主要なバリデーションは LeadValidator (Apex) で実施。
Flow では UI 補助的な処理のみ。

---

## 7. LWC の実装仕様

### 7-1. leadList

#### 機能

リード一覧をスコア順で表示。

#### 配置

カスタムタブ「リード一覧」

#### ファイル構成

```
lwc/leadList/
├── leadList.html
├── leadList.js
├── leadList.css
└── leadList.js-meta.xml
```

#### 主な機能

- @wire で getLeadList を呼び出し
- スコア順表示（デフォルト降順）
- カテゴリ別フィルタ
- ソース別フィルタ
- 名前・会社名で検索（imperative call）
- 行クリックで標準詳細画面遷移
- ローディング表示
- エラー表示
- Empty State 表示

#### ベストプラクティス

```
✓ @wire を主体に
✓ SLDS クラスを使用
✓ aria-label でアクセシビリティ確保
✓ try-catch でエラーハンドリング
✓ ローディングインジケータ
✓ Lightning Data Table を使用
```

---

### 7-2. leadSearch

#### 機能

高度な検索。

#### 主な機能

- 複数条件での検索
- 検索結果の表示
- リードへのナビゲーション

---

### 7-3. leadScoreCard

#### 機能

3軸スコアの内訳を視覚的に表示。

#### 配置

Lead レコードページ

#### 表示内容

```
[最終スコア]
245 / 300 (大きく表示)
カテゴリバッジ: Hot

[3軸の内訳]
属性スコア: 80 / 100 ████████░░ 80%
行動スコア: 95 / 120 ███████░░░ 79%
興味スコア: 70 /  80 █████████░ 88%
```

#### ベストプラクティス

```
✓ getRecord（Lightning Data Service）を使用
✓ Apex 呼び出しは最小限
✓ プログレスバー（SLDS）
✓ レスポンシブ対応
```

---

### 7-4. leadDetail

#### 機能

リードの詳細表示。

#### 配置

カスタムタブ

---

### 7-5. leadInterestRadar

#### 機能

リードの関心領域をレーダーチャートで表示。

#### 配置

Lead レコードページ

#### 実装ポイント

```
- chart.js または d3 を Static Resource として配置
- 全 10 トピックを軸として表示
- Interest_Level でプロット
- ホバーで詳細表示
- レスポンシブ対応
- データなしの場合は Empty State
```

---

## 8. テストクラスの方針

### TestDataFactory.cls（テストデータファクトリ）

```apex
@isTest
public class TestDataFactory {
    
    public static List<Lead> createLeads(Integer count) {
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < count; i++) {
            leads.add(new Lead(
                FirstName = 'Test',
                LastName = 'User' + i,
                Company = 'Test Company ' + i,
                Title = 'Manager',
                Industry = 'Technology',
                NumberOfEmployees = 1000,
                LeadSource = 'Webinar',
                Email = 'test' + i + '@example.com'
            ));
        }
        return leads;
    }
    
    public static List<Lead_Interest__c> createInterests(List<Lead> leads, Integer perLead) {
        // ...
    }
    
    public static List<Campaign> createCampaigns(Integer count) {
        // ...
    }
    
    public static List<CampaignMember> createCampaignMembers(...) {
        // ...
    }
}
```

### テストクラス（全 7 個、カバレッジ 90%+）

| クラス名 | 対象 | 目標カバレッジ |
|---|---|---|
| LeadControllerTest | LeadController | 90%+ |
| LeadServiceTest | LeadService | 90%+ |
| LeadScoringServiceTest | LeadScoringService | 95%+ |
| LeadAttributeScorerTest | LeadAttributeScorer | 95%+ |
| LeadBehaviorScorerTest | LeadBehaviorScorer | 95%+ |
| LeadInterestScorerTest | LeadInterestScorer | 95%+ |
| LeadValidatorTest | LeadValidator | 90%+ |
| LeadTriggerTest | 各 Trigger + Handler | 90%+ |

### テストのベストプラクティス

```
✓ @TestSetup で共通データを準備
✓ SeeAllData=true は絶対に使わない
✓ TestDataFactory パターンを使用
✓ ポジティブケース + ネガティブケース
✓ バルクテスト（200件）を必ず含める
✓ アサーションを充実
✓ Test.startTest() / Test.stopTest() でガバナ制限をリセット
✓ System.runAs() で異なるユーザーのテストも可能に
```

#### テストクラスの例

```apex
@isTest
private class LeadScoringServiceTest {
    
    @TestSetup
    static void setup() {
        List<Lead> leads = TestDataFactory.createLeads(10);
        insert leads;
    }
    
    @isTest
    static void testCalculateScoreForSingleLead() {
        Lead lead = [SELECT Id FROM Lead LIMIT 1];
        
        Test.startTest();
        LeadScoringService.calculateScore(lead.Id);
        Test.stopTest();
        
        Lead updated = [SELECT Score__c, Lead_Category__c FROM Lead WHERE Id = :lead.Id];
        System.assertNotEquals(0, updated.Score__c, 'スコアが計算されているはず');
        System.assertNotEquals(null, updated.Lead_Category__c, 'カテゴリが設定されているはず');
    }
    
    @isTest
    static void testCalculateScoresBulk() {
        // 200件のバルクテスト
        List<Lead> bulkLeads = TestDataFactory.createLeads(200);
        insert bulkLeads;
        Set<Id> leadIds = new Map<Id, Lead>(bulkLeads).keySet();
        
        Test.startTest();
        LeadScoringService.calculateScores(leadIds);
        Test.stopTest();
        
        List<Lead> updated = [SELECT Score__c FROM Lead WHERE Id IN :leadIds];
        System.assertEquals(200, updated.size(), '200件すべて更新されているはず');
    }
    
    @isTest
    static void testDetermineCategoryHot() {
        String category = LeadScoringService.determineCategory(200);
        System.assertEquals('Hot', category);
    }
    
    @isTest
    static void testDetermineCategoryLow() {
        String category = LeadScoringService.determineCategory(10);
        System.assertEquals('Low', category);
    }
    
    @isTest
    static void testCalculateScoresEmpty() {
        // ネガティブケース
        Test.startTest();
        LeadScoringService.calculateScores(new Set<Id>());
        Test.stopTest();
        // 例外が出ないことを確認
    }
}
```

---

## 9. 権限セット

### Lead_Management_User.permissionset-meta.xml

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Lead Management User</label>
    <hasActivationRequired>false</hasActivationRequired>
    
    <!-- Lead オブジェクト -->
    <objectPermissions>
        <object>Lead</object>
        <allowRead>true</allowRead>
        <allowCreate>true</allowCreate>
        <allowEdit>true</allowEdit>
        <allowDelete>true</allowDelete>
        <viewAllRecords>true</viewAllRecords>
        <modifyAllRecords>true</modifyAllRecords>
    </objectPermissions>
    
    <!-- カスタム項目 -->
    <fieldPermissions>
        <field>Lead.Score__c</field>
        <readable>true</readable>
        <editable>true</editable>
    </fieldPermissions>
    <!-- 全カスタム項目を同様に -->
    
    <!-- Lead_Interest__c -->
    <objectPermissions>
        <object>Lead_Interest__c</object>
        <allowRead>true</allowRead>
        <allowCreate>true</allowCreate>
        <allowEdit>true</allowEdit>
        <allowDelete>true</allowDelete>
    </objectPermissions>
    
    <!-- Apex クラスへのアクセス -->
    <classAccesses>
        <apexClass>LeadController</apexClass>
        <enabled>true</enabled>
    </classAccesses>
    <!-- 全クラスを同様に -->
    
    <!-- カスタムタブ -->
    <tabSettings>
        <tab>Lead_List</tab>
        <visibility>Visible</visibility>
    </tabSettings>
</PermissionSet>
```

---

## 10. シードデータ

### data/leads.json

50 件のリード。属性が多様で、カテゴリ判定が分散するように設計。

```json
{
    "records": [
        {
            "attributes": { "type": "Lead", "referenceId": "Lead_1" },
            "FirstName": "太郎",
            "LastName": "山田",
            "Company": "テックインダストリー株式会社",
            "Title": "CTO",
            "Industry": "Technology",
            "NumberOfEmployees": 5000,
            "LeadSource": "Webinar",
            "Email": "yamada@techindustry.example.com",
            "Last_Action_Date__c": "2026-09-01"
        }
    ]
}
```

### data/plan.json

```json
[
    {
        "sobject": "Campaign",
        "saveRefs": true,
        "resolveRefs": false,
        "files": ["campaigns.json"]
    },
    {
        "sobject": "Lead",
        "saveRefs": true,
        "resolveRefs": false,
        "files": ["leads.json"]
    },
    {
        "sobject": "CampaignMember",
        "saveRefs": false,
        "resolveRefs": true,
        "files": ["campaign-members.json"]
    },
    {
        "sobject": "Lead_Interest__c",
        "saveRefs": false,
        "resolveRefs": true,
        "files": ["interests.json"]
    }
]
```

### data/load-data.sh

```bash
#!/bin/bash
set -e

echo "Loading seed data..."
sf data import tree --plan data/plan.json --target-org default
echo "Done."
```

---

## 11. 実装の優先順位

### Phase 1: データモデル

```
1. Lead オブジェクトのカスタム項目
2. Lead_Interest__c カスタムオブジェクト
3. Lead_Scoring_Config__mdt
4. 初期メタデータレコード
```

### Phase 2: 定数とユーティリティ

```
5. LeadConstants
6. TestDataFactory（テスト用、Phase 4 までに）
```

### Phase 3: Apex クラス（コア）

```
7. LeadAttributeScorer
8. LeadBehaviorScorer
9. LeadInterestScorer
10. LeadScoringService
11. LeadTriggerHandler
12. LeadTrigger
13. LeadInterestTrigger
14. CampaignMemberTrigger
15. LeadValidator
16. LeadService
17. LeadController
```

### Phase 4: テストクラス

```
18. LeadAttributeScorerTest
19. LeadBehaviorScorerTest
20. LeadInterestScorerTest
21. LeadScoringServiceTest
22. LeadValidatorTest
23. LeadTriggerTest
24. LeadServiceTest
25. LeadControllerTest
```

### Phase 5: Flow

```
26. Lead_Status_Update_Flow
27. Lead_Validation_Flow
```

### Phase 6: LWC

```
28. leadList
29. leadSearch
30. leadScoreCard
31. leadDetail
32. leadInterestRadar
```

### Phase 7: UI 設定 + 権限

```
33. カスタムタブ
34. カスタムアプリ
35. Lightning ページ（FlexiPage）
36. 権限セット
```

### Phase 8: シードデータ

```
37. leads.json
38. campaigns.json
39. campaign-members.json
40. interests.json
41. load-data.sh
```

---

## 12. 受け入れ基準

### コード品質

```
✓ デプロイ成功（エラーなし）
✓ テストカバレッジ 90% 以上
✓ すべてのテストが Pass
✓ Apex のチェッカーで警告ゼロ
```

### 機能動作

```
✓ シードデータが正常に投入される
✓ 新規リード作成時にスコアが計算される
✓ Lead_Interest__c 追加時に興味スコアが更新される
✓ CampaignMember 追加時に行動スコアが更新される
✓ 200件のバルク insert でガバナ制限超過しない
✓ リード一覧でスコア順表示
✓ レコードページに leadScoreCard が表示される
✓ レコードページに leadInterestRadar が表示される
```

### セキュリティ

```
✓ 全 SOQL に WITH SECURITY_ENFORCED
✓ 動的 SOQL は String.escapeSingleQuotes() でエスケープ
✓ DML 前に CRUD/FLS チェック
✓ 適切な with sharing / without sharing
```

### コードの読みやすさ

```
✓ 定数は LeadConstants に集約
✓ マジックナンバーなし
✓ 命名が一貫している
✓ メソッドが 1 つの責務に絞られている
✓ クラス間の依存が一方向
```

---

## 13. Claude Code への指示

### 実装時に守ってほしいこと

```
1. このドキュメントの仕様に従って、ベストプラクティスで実装してください

2. Salesforce のベストプラクティスを完全に守ってください:
   - バルク化
   - WITH SECURITY_ENFORCED
   - エラーハンドリング
   - 定数の使用
   - 命名規則

3. テストカバレッジ 90% 以上を目標にしてください

4. デプロイ可能な状態で出力してください
   - メタデータファイル (.cls-meta.xml 等) も含む
   - sfdx-project.json の構成に従う

5. 各ファイルの先頭に簡潔なコメントを入れてください
   - クラスの責務
   - 主要なメソッドの説明
```

### 実装の進め方

```
1. Phase 1（データモデル）から順番に実装
2. 各 Phase が完了したらビルド・デプロイ確認
3. Phase 4（テスト）でカバレッジ確認
4. 全 Phase 完了後、シードデータ投入
5. 動作確認
```

### 質問や確認

```
- 不明点があれば必ず質問してください
- 仕様に書かれていない判断が必要な場合は確認してください
- 実装の方向性に複数の選択肢がある場合は、選択肢を提示してください
```

---

## 14. 参考情報

### スコアリングの計算例

リード A:
- Industry: Technology → +15
- NumberOfEmployees: 2000 → +20
- Title: CTO → +30
- LeadSource: Webinar → +20
- 属性スコア: 85

CampaignMember:
- Webinar 参加（10日前）: 30 × 0.95^10 = 17.96
- White Paper DL（5日前）: 15 × 0.95^5 = 11.60
- 行動スコア: 約 30

Lead_Interest__c:
- データ統合 Level 80 × 1.5 = 120 → 80 で頭打ち
- 興味スコア: 80

最終スコア: 85 + 30 + 80 = 195 → カテゴリ「Hot」

### 関連ドキュメント

- CLAUDE.md（プロジェクトルール、別途参照）
- ベースシステム仕様書_v2.md（人間向けの仕様書）

---

以上、この実装指示書に従って、リード管理・スコアリングシステム（クリーン版）を実装してください。
不明点があれば質問してから着手してください。
