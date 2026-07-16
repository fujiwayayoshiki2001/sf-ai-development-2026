# 設計書 — リード管理・スコアリングシステム（図解）

> 対象読者: 受講者・レビュアー・新規参画メンバー
> このドキュメントは ER図 / クラス図 / シーケンス図 / 全体構成図を **Mermaid 記法** で記載しています。
> GitHub・VS Code（Markdown Preview Mermaid Support 等の拡張）でそのまま図として表示され、
> PDF / PNG への書き出しも可能です。
>
> 文章中心の解説は `architecture-overview.md` / `class-by-class-guide.md` を参照してください。
> 本書は「図で全体像をつかむ」ことに特化しています。

---

## 0. 配布・閲覧について

| 環境 | 図の表示 | 備考 |
|---|---|---|
| GitHub（ブラウザ） | ✅ そのまま表示 | リポジトリ上で `.md` を開くだけ |
| VS Code | ✅ プレビューで表示 | 拡張「Markdown Preview Mermaid Support」推奨 |
| PDF / PNG 書き出し | ✅ 可能 | VS Code 拡張「Markdown PDF」、または Mermaid CLI（`mmdc`） |
| メール / Slack 添付 | △ | テキストのままだと図にならない。PDF 化して配布を推奨 |

> **PDF 化の例（Mermaid CLI）**:
> `npx @mermaid-js/mermaid-cli -i docs/design-diagrams.md -o design-diagrams.pdf`

---

## 1. システム概要

リード（見込み客）を **属性・行動・興味** の 3 軸で自動採点し、
スコア順に優先度（Hot/Warm/Cold/Low）を可視化するシステム。

```
最終スコア = 属性スコア(最大100) + 行動スコア(最大120) + 興味スコア(最大80) = 最大300点

  180点以上 → Hot   (即対応)
  100〜179  → Warm  (フォロー)
   50〜 99  → Cold  (育成)
    0〜 49  → Low   (低優先)
```

| 軸 | データソース | 種類 | 計算クラス |
|---|---|---|---|
| 属性 | Lead レコード自身 | 標準 | `LeadAttributeScorer` |
| 行動 | CampaignMember | 標準 | `LeadBehaviorScorer` |
| 興味 | Lead_Interest__c | カスタム | `LeadInterestScorer` |

---

## 2. ER図（データモデル）

各オブジェクトの主要項目とリレーションを示します。
`PK` = 主キー、`FK` = 外部キー（参照関係）。

```mermaid
erDiagram
    Lead ||--o{ Lead_Interest__c : "Interests (Lookup)"
    Lead ||--o{ CampaignMember : "参加 (LeadId)"
    Campaign ||--o{ CampaignMember : "メンバー (CampaignId)"
    Lead_Scoring_Config__mdt }o..o{ Lead : "重み参照 (Key で照合)"

    Lead {
        Id Id PK
        Text LastName "標準・必須"
        Text Company "標準"
        Picklist Industry "属性スコア対象"
        Number NumberOfEmployees "属性スコア対象"
        Text Title "属性スコア対象"
        Picklist LeadSource "属性スコア対象"
        Number Score__c "最終スコア(3,0)"
        Number Attribute_Score__c "属性(3,0)"
        Number Behavior_Score__c "行動(5,2)"
        Number Interest_Score__c "興味(3,0)"
        Picklist Lead_Category__c "Hot/Warm/Cold/Low"
        DateTime Score_Last_Calculated__c "最終計算時刻"
        Date Last_Action_Date__c "最終アクション日"
    }

    Lead_Interest__c {
        Id Id PK
        Lookup Lead__c FK "親Lead(削除時SetNull)"
        Picklist Interest_Topic__c "興味トピック"
        Number Interest_Level__c "関心度 1-100 (3,0)"
        Date Detected_Date__c "検知日"
        Text Source__c "検知元"
        TextArea Notes__c "備考"
    }

    CampaignMember {
        Id Id PK
        Lookup LeadId FK "参加リード"
        Lookup CampaignId FK "対象キャンペーン"
        Picklist Status "参加ステータス"
    }

    Campaign {
        Id Id PK
        Text Name "キャンペーン名"
        Picklist Type "種別"
        Checkbox IsActive "有効"
    }

    Lead_Scoring_Config__mdt {
        Id Id PK
        Text Key__c "照合キー(例:Type_Status)"
        Text Score_Type__c "軸種別(attribute/behavior/interest)"
        Number Weight__c "重み(5,2)"
        Checkbox Is_Active__c "有効フラグ"
    }
```

> **設計メモ — `Lead_Interest__c.Lead__c` が Lookup である理由**:
> 仕様上は主従関係（Master-Detail）が自然ですが、Lead は主従のマスターになれず、
> 必須 Lookup も削除制約の都合で不可のため、**任意 Lookup（削除時 SetNull）** で実装しています。
> 「親 Lead 必須」の制約はアプリ層（バリデーション）で担保する想定です。

> **`Lead_Scoring_Config__mdt` について**:
> カスタムメタデータ型はリレーションでつながるのではなく、各 Scorer が `Key__c` を
> キーに `Map` 化して照合します（点線で表現）。重みを変えたいときは Apex を変更せず
> このレコードを編集するだけで済みます。

---

## 3. 全体構成図（レイヤーアーキテクチャ）

呼び出しは **上の層から下の層への一方向**。逆流（下位→上位）はありません。

```mermaid
flowchart TD
    subgraph P["プレゼンテーション層"]
        LWC1["LWC: leadScoreCard"]
        LWC2["LWC: leadInterestRadar"]
    end

    subgraph C["コントローラ層"]
        CTRL["LeadController<br/>@AuraEnabled 窓口・例外整形"]
    end

    subgraph B["ビジネスロジック層"]
        SVC["LeadService<br/>取得・検索・更新"]
        VAL["LeadValidator<br/>入力チェック"]
        SCORE["LeadScoringService<br/>★スコア統括(司令塔)"]
    end

    subgraph S["スコアリング層（3つの専門家）"]
        ATTR["LeadAttributeScorer"]
        BEHV["LeadBehaviorScorer"]
        INT["LeadInterestScorer"]
    end

    subgraph CONF["定数・設定層"]
        CONST["LeadConstants<br/>(Apex定数)"]
        CMDT["Lead_Scoring_Config__mdt<br/>(重み表)"]
    end

    LWC1 --> CTRL
    LWC2 --> CTRL
    CTRL --> SVC
    CTRL --> SCORE
    SVC --> CONST
    SCORE --> ATTR
    SCORE --> BEHV
    SCORE --> INT
    SCORE --> CONST
    ATTR --> CMDT
    ATTR --> CONST
    BEHV --> CMDT
    BEHV --> CONST
    INT --> CMDT
    INT --> CONST
```

### トリガー発火マップ（イベント駆動の入口）

3 つのトリガーは「薄いトリガー → 専用 Handler → `LeadScoringService`」で統一されています。

```mermaid
flowchart TD
    E1["Lead を保存"] --> T1["LeadTrigger (薄)"]
    E2["CampaignMember を保存"] --> T2["CampaignMemberTrigger (薄)"]
    E3["Lead_Interest__c を保存"] --> T3["LeadInterestTrigger (薄)"]

    T1 --> H1["LeadTriggerHandler"]
    T2 --> H2["CampaignMemberTriggerHandler"]
    T3 --> H3["LeadInterestTriggerHandler"]

    H1 --> V["LeadValidator<br/>(before のみ)"]
    H1 --> SC["LeadScoringService<br/>.calculateScores(Set&lt;Id&gt;)"]
    H2 --> SC
    H3 --> SC

    SC --> R["合計 → カテゴリ判定 → Lead を update"]
```

---

## 4. クラス図（責務と依存関係）

主要メソッドと依存方向を UML クラス図で表します。

```mermaid
classDiagram
    class LeadController {
        <<Controller>>
        +getScoreBreakdown(Id) Map
        +getInterests(Id) List
        +recalculateScore(Id) void
        +updateLastActionDate(List~Id~) void
    }
    class LeadService {
        <<Service>>
        +getScoreBreakdown(Id) Map
        +getInterests(Id) List
        +updateLastActionDate(Set~Id~) void
        +getStaleLeads() List
    }
    class LeadValidator {
        <<Service>>
        +validate(List~Lead~) void
    }
    class LeadScoringService {
        <<Service>>
        +calculateScores(Set~Id~) void
        +calculateScore(Id) void
        +determineCategory(Decimal) String
    }
    class LeadAttributeScorer {
        <<Scorer>>
        +calculateBulk(List~Lead~) Map
    }
    class LeadBehaviorScorer {
        <<Scorer>>
        +calculateBulk(Set~Id~) Map
    }
    class LeadInterestScorer {
        <<Scorer>>
        +calculateBulk(Set~Id~) Map
    }
    class LeadConstants {
        <<Constants>>
        +HOT_THRESHOLD Integer
        +DECAY_FACTOR Decimal
    }
    class LeadTriggerHandler {
        <<Handler>>
        +bypassTrigger Boolean
        +beforeInsert(List) void
        +afterInsert(List, Map) void
        +afterUpdate(List, Map, Map) void
    }
    class CampaignMemberTriggerHandler {
        <<Handler>>
        +handle(...) void
    }
    class LeadInterestTriggerHandler {
        <<Handler>>
        +handle(...) void
    }

    LeadController --> LeadService
    LeadController --> LeadScoringService
    LeadService --> LeadConstants
    LeadScoringService --> LeadAttributeScorer
    LeadScoringService --> LeadBehaviorScorer
    LeadScoringService --> LeadInterestScorer
    LeadScoringService --> LeadConstants
    LeadAttributeScorer --> LeadConstants
    LeadBehaviorScorer --> LeadConstants
    LeadInterestScorer --> LeadConstants
    LeadTriggerHandler --> LeadValidator
    LeadTriggerHandler --> LeadScoringService
    CampaignMemberTriggerHandler --> LeadScoringService
    LeadInterestTriggerHandler --> LeadScoringService
```

> 3 つの Scorer は互いを知りません（独立）。`LeadScoringService` だけが 3 つをまとめます。
> これは「同じ採点という仕事を別アルゴリズムで行う」**Strategy パターン** に近い構成です。

---

## 5. シーケンス図

### 5-1. リード作成 → スコア確定（基本フロー）

新規 Lead を 1 件保存したときの処理を時系列で示します。

```mermaid
sequenceDiagram
    actor User as ユーザー
    participant DB as Salesforce(DB)
    participant TG as LeadTrigger
    participant H as LeadTriggerHandler
    participant V as LeadValidator
    participant SS as LeadScoringService
    participant AS as LeadAttributeScorer
    participant BS as LeadBehaviorScorer
    participant IS as LeadInterestScorer

    User->>DB: Lead を insert
    DB->>TG: トリガー発火

    rect rgb(245,245,220)
    Note over TG,V: before insert（保存前）
    TG->>H: beforeInsert(newLeads)
    H->>V: validate(newLeads)
    V-->>H: OK / NG(addErrorで保存中止)
    end

    DB->>DB: レコード保存・Id 採番

    rect rgb(220,235,245)
    Note over TG,IS: after insert（保存後）
    TG->>H: afterInsert(newLeads, newMap)
    H->>SS: calculateScores(leadIds)
    SS->>DB: SOQL: 対象 Lead を1回取得
    SS->>AS: calculateBulk(leads)
    AS-->>SS: 属性スコア Map
    SS->>BS: calculateBulk(leadIds)
    BS-->>SS: 行動スコア Map(時間減衰込み)
    SS->>IS: calculateBulk(leadIds)
    IS-->>SS: 興味スコア Map
    SS->>SS: 合計 → determineCategory()
    Note over SS: bypassTrigger = true
    SS->>DB: update(Score__c, 各軸, Category, 計算日時)
    Note over SS: finally で bypassTrigger = false
    end

    DB-->>User: 保存完了（スコア反映済み）
```

> **再帰防止の肝**: ⑤ の update が再び Lead トリガーを発火させると無限ループになります。
> そのため `bypassTrigger = true` にして再発火を抑止し、`finally` で必ず `false` に戻します。

### 5-2. スコア更新時の賢い分岐（after update）

更新時は **属性に影響する項目が変わった行だけ** 再計算します。

```mermaid
sequenceDiagram
    actor User as ユーザー
    participant DB as Salesforce(DB)
    participant H as LeadTriggerHandler
    participant SS as LeadScoringService

    User->>DB: Lead を update
    DB->>H: afterUpdate(newLeads, oldMap, newMap)
    loop 各 Lead
        H->>H: isAttributeChanged(old, new)?<br/>(Industry/NumberOfEmployees/Title/LeadSource)
    end
    alt 属性項目が変わった行がある
        H->>SS: calculateScores(変わった行のみ)
        SS->>DB: 再計算して update
    else 無関係な更新のみ
        Note over H: 何もしない（無駄なフル再計算を回避）
    end
```

### 5-3. 別の軸が動いたとき（行動 / 興味トリガー）

キャンペーン参加や興味レコードが変わると、別トリガーから同じ `calculateScores()` に合流します。

```mermaid
sequenceDiagram
    participant DB as Salesforce(DB)
    participant CMH as CampaignMemberTriggerHandler
    participant LIH as LeadInterestTriggerHandler
    participant SS as LeadScoringService

    alt CampaignMember が変更された
        DB->>CMH: トリガー発火
        Note over CMH: LeadId が null(Contact経由)は除外<br/>update は旧 LeadId も対象に含める
        CMH->>SS: calculateScores(関連 LeadId)
    else Lead_Interest__c が変更された
        DB->>LIH: トリガー発火
        Note over LIH: Lead__c が null は除外<br/>update は旧親 Lead も対象に含める
        LIH->>SS: calculateScores(関連 LeadId)
    end
    SS->>DB: 3軸再計算 → update
```

### 5-4. 画面からの再計算ボタン（LWC → Controller）

```mermaid
sequenceDiagram
    actor User as ユーザー
    participant LWC as leadScoreCard (LWC)
    participant CTRL as LeadController
    participant SS as LeadScoringService
    participant DB as Salesforce(DB)

    User->>LWC: 「再計算」ボタン押下
    LWC->>CTRL: recalculateScore(recordId) @AuraEnabled
    activate CTRL
    alt leadId が null
        CTRL-->>LWC: AuraHandledException("ID未指定")
    else 正常
        CTRL->>SS: calculateScores({leadId})
        SS->>DB: 3軸再計算 → update
        DB-->>SS: 完了
        SS-->>CTRL: 完了
        CTRL-->>LWC: 成功
        LWC->>CTRL: getScoreBreakdown(recordId) で再取得
        CTRL-->>LWC: { attribute, behavior, interest, total }
    end
    deactivate CTRL
    LWC-->>User: 最新スコアを表示
```

> Controller は内部例外をそのまま返さず、`AuraHandledException` でユーザー向けの
> 安全なメッセージに整形します。状態変更メソッドは `cacheable=false`、
> 読み取りメソッド（`getScoreBreakdown`/`getInterests`）は `cacheable=true` です。

---

## 6. スコア計算ロジック（補足図）

### 行動スコアの時間減衰

```
減衰係数 = 0.95 ^ 経過日数

  当日:   1.00 (100%)
  7日前:  0.70 ( 70%)
  14日前: 0.49 ( 49%)
  30日前: 0.21 ( 21%)
```

### カテゴリ判定フロー

```mermaid
flowchart LR
    A["最終スコア"] --> B{">= 180?"}
    B -- Yes --> Hot["Hot（即対応）"]
    B -- No --> C{">= 100?"}
    C -- Yes --> Warm["Warm（フォロー）"]
    C -- No --> D{">= 50?"}
    D -- Yes --> Cold["Cold（育成）"]
    D -- No --> Low["Low（低優先）"]
```

---

## 7. 関連ドキュメント

| ドキュメント | 内容 |
|---|---|
| `architecture-overview.md` | プロジェクト全体マップ（文章＋ASCII図） |
| `class-by-class-guide.md` | クラス別の詳細解説 |
| `design-diagrams.md` | 本書（ER図・クラス図・シーケンス図・全体構成図） |
| `CLAUDE.md` | プロジェクトルール・コーディング規約 |

---

最終更新: 2026年6月
