# クラス別 詳細解説ガイド

> 対象読者: リファクタリング演習に入る前の受講者（Salesforce 初学者・Java 経験あり）
> 読み方: 依存関係の浅い順（基盤 → 計算 → 統括 → トリガー → ロジック → 画面）に並べています。
> 上から順に読むと「下層を理解した状態で上層を読める」ので理解が積み上がります。
>
> 各章は **役割 / 全体の流れ / 主要メソッド / 学べること / よくある間違い（リファクタ題材）** の
> 構成です。「よくある間違い」は *このコードが必ずしも悪いという意味ではなく*、
> 演習で議論する価値のある論点を挙げています。

---

# Layer 1: 基盤

## 1. LeadConstants — 定数集約

### 役割
プロジェクト全体で使う「魔法の数字・固定文字列」を 1 箇所に集めた定数クラス。

### 全体の流れ
処理は持ちません。`public static final` なフィールドが並ぶだけの「定数の倉庫」です。
閾値（Hot=180 等）・スコア上限（100/120/80/300）・
カテゴリ名（Hot/Warm/Cold/Low）・業界名・リードソース名などを保持します。

```apex
public class LeadConstants {
    // カテゴリ閾値
    public static final Integer HOT_THRESHOLD  = 180;
    public static final Integer WARM_THRESHOLD = 100;
    public static final Integer COLD_THRESHOLD = 50;
    // スコア上限
    public static final Integer ATTRIBUTE_MAX_SCORE = 100;
    public static final Integer BEHAVIOR_MAX_SCORE  = 120;
    public static final Integer INTEREST_MAX_SCORE  = 80;
    ...
}
```

### 主要なメソッドの解説
メソッドはありません。定数のみです。

> **Salesforce 特有のポイント**: SOQL/DML を一切持たないクラスなので
> `with sharing` / `without sharing`（実行ユーザーのレコード可視性を尊重するか）の
> 宣言は不要です。共有設定はレコードにアクセスするクラスにだけ意味があります。

### このクラスから学べること
- **マジックナンバーの排除**: `if (score >= 180)` と直書きせず `>= LeadConstants.HOT_THRESHOLD` と書く。
  数字の意味が名前で分かり、変更が 1 箇所で済む。
- Java 対比: Java の `public static final` 定数クラス／`enum` とまったく同じ考え方。
  `final` は再代入不可（定数）という意味も Java と同一です。

### よくある間違い（リファクタ題材の候補）
- **まだ外に残っている魔法の数字**: 例えば `LeadAttributeScorer` には従業員規模の境界
  `1000 / 100 / 10` や、`'NumberOfEmployees_1000+'` のようなキー文字列が直書きされています。
  「定数化が徹底されているか？」は良い議論テーマです。
- **型の不一致**: 閾値は `Integer`、スコアは `Decimal`。比較は自動変換で動きますが、
  「上限・閾値も `Decimal` に揃えるべきか」は検討余地あり。

---

# Layer 2: スコア計算

3 つの Scorer は **兄弟クラス**で、構造がそっくりです（同じ「重み表を引いて合算し上限で頭打ち」
というアルゴリズムの別バージョン）。まず属性で型を理解すれば、残り 2 つは差分だけ読めます。

## 2. LeadAttributeScorer — 属性スコア

### 役割
リード *自身* の項目（業界・従業員数・役職・流入元）を見て属性スコアを算出する。

### 全体の流れ
```
重み表(CMDT)を読む → 各Leadごとに 業界+規模+役職+流入元 の重みを合算 → 100点で頭打ち
```
SOQL を持たず、参照するのは **カスタムメタデータ `Lead_Scoring_Config__mdt`** と
Lead の項目だけです。

### 主要なメソッドの解説

#### `calculateBulk(List<Lead> leads) → Map<Id, Decimal>`
- **何をするか**: 複数リードの属性スコアをまとめて計算し、`LeadのId → スコア` の Map で返す。
- **コードのキモ**:
  ```apex
  Map<String, Decimal> weightMap = getWeightMap();   // 重み表を1回だけ構築
  for (Lead lead : leads) {
      Decimal score = 0;
      score += getIndustryWeight(lead.Industry, weightMap);
      score += getSizeWeight(lead.NumberOfEmployees, weightMap);
      score += getTitleWeight(lead.Title, weightMap);
      score += getSourceWeight(lead.LeadSource, weightMap);
      score = Math.min(score, LeadConstants.ATTRIBUTE_MAX_SCORE);  // 上限で頭打ち
      scoreMap.put(lead.Id, score);
  }
  ```
- **なぜこの実装か**: ループの *外* で重み表を 1 度だけ作り、ループ内では Map 参照だけ。
  200 件でも重み表構築は 1 回で済みます（後述のバルク化）。

#### `calculate(Lead lead) → Decimal`
- 単一リード版。中身は `calculateBulk(new List<Lead>{ lead })` を呼ぶ薄いラッパー。
- **なぜ**: ロジックの本体を 1 つ（バルク版）に集約し、二重実装を避けるため。

#### `getWeightMap() → Map<String, Decimal>`（private）
- CMDT を読み、`Score_Type__c='Attribute'` かつ有効な行だけを `キー(小文字) → 重み` の Map に。
- **トランザクション内キャッシュ**: `cachedWeightMap` が既にあれば再構築しない。
  ```apex
  private static Map<String, Decimal> cachedWeightMap;   // staticは1トランザクション内で生存
  if (cachedWeightMap != null) return cachedWeightMap;
  ```

> **Salesforce 特有のポイント**:
> - `Lead_Scoring_Config__mdt.getAll()` は **SOQL を消費しない**（メタデータはメモリから取得）。
>   ガバナ制限の SOQL カウントに含まれないので、ループ外で呼ぶ価値が大きい。
> - 役職判定は `title.toLowerCase().contains('ceo')` のような **部分一致**。
>   大文字小文字や表記揺れを吸収する狙い。

### このクラスから学べること
- **Strategy パターン的な責務分割**: 「属性だけ」を計算する単機能クラス。
- **静的キャッシュ**で同一トランザクション内の無駄な再構築を防ぐ。
- **上限ガード** `Math.min(score, MAX)` で仕様（最大100点）をコードで保証。

### よくある間違い（リファクタ題材の候補）
- **単一版 `calculate()` をループで呼ぶ**: それ自体は SOQL を使いませんが、
  兄弟クラス（Behavior/Interest）の `calculate(Id)` は **中で SOQL を打つ** ため、
  ループ内で呼ぶと N+1 になります。「単一版はいつ使ってよいか」を意識する題材。
- **役職判定の部分一致の脆さ**: `contains('vp')` は "VP" 以外（例: 単語の一部）にも
  反応し得ます。判定ルールをどう堅牢化/設定化するかは議論の余地あり。
- **規模境界 `1000/100/10` の直書き**: 定数化や CMDT 化の候補。

---

## 3. LeadBehaviorScorer — 行動スコア

### 役割
リードのキャンペーン参加履歴（CampaignMember）を集計して評価する。

### 全体の流れ
```
対象LeadのCampaignMemberを1回のSOQLで取得
  → 各メンバーを「Type_Status」キーで重み引きして加算
  → 120点で頭打ち
```

### 主要なメソッドの解説

#### `calculateBulk(Set<Id> leadIds) → Map<Id, Decimal>`
- **何をするか**: 複数リードの行動スコアを計算。最初に全 Lead を 0 で初期化してから加算する。
- **コードのキモ**:
  ```apex
  List<CampaignMember> members = [
      SELECT Id, LeadId, Campaign.Type, Status
      FROM CampaignMember WHERE LeadId IN :leadIds WITH SECURITY_ENFORCED
  ];                                    // ← ループの外で1回だけクエリ（バルク化）
  for (CampaignMember m : members) {
      String key = (m.Campaign.Type + '_' + m.Status).toLowerCase();   // 例: webinar_attended
      Decimal weight = weightMap.containsKey(key) ? weightMap.get(key) : 0;
      if (weight == 0) continue;
      scoreMap.put(m.LeadId, scoreMap.get(m.LeadId) + weight);
  }
  ```
- **なぜこの実装か**: 「キャンペーン種別×ステータス」の組み合わせごとに重みが違うため、
  両者を連結したキーで重み表を引く設計。

#### `getWeightMap()`（private）
- 属性版と同型。`Score_Type__c='Behavior'` の行をキャッシュ。

> **Salesforce 特有のポイント**:
> - `Campaign.Type` のように `.`（ドット）でたどると、**親（Campaign）の項目を子（CampaignMember）から
>   参照**できます（リレーション項目。Java の `member.getCampaign().getType()` 相当）。
> - `CampaignMember` は Lead だけでなく Contact にも紐づくため `LeadId` が null の行があり得ます。

### このクラスから学べること
- **集計の定石**: 「先に 0 で初期化 → ループで加算」。データが無い Lead も結果 Map に 0 で残せる。

### よくある間違い（リファクタ題材の候補）
- **ステータスのローカライズ不一致**: 組織既定の CampaignMemberStatus が日本語（「送信」等）だと、
  キー `webinar_attended` と一致せず重み 0 になります。設定依存の落とし穴で、良い議論テーマ。
- **単一版 `calculate(Id)` のループ呼び出し → N+1 SOQL**: 属性版と同じ注意点。

---

## 4. LeadInterestScorer — 興味スコア

### 役割
リードに紐づく興味レコード（Lead_Interest__c）を集計し、関心の強さをスコア化する。

### 全体の流れ
```
対象LeadのLead_Interest__cを1回のSOQLで取得
  → 各興味の「トピック重み × 関心度(Interest_Level__c)」を加算
  → 80点で頭打ち
```

### 主要なメソッドの解説

#### `calculateBulk(Set<Id> leadIds) → Map<Id, Decimal>`
- **コードのキモ**:
  ```apex
  List<Lead_Interest__c> interests = [
      SELECT Id, Lead__c, Interest_Topic__c, Interest_Level__c
      FROM Lead_Interest__c WHERE Lead__c IN :leadIds WITH SECURITY_ENFORCED
  ];
  for (Lead_Interest__c i : interests) {
      if (i.Lead__c == null || String.isBlank(i.Interest_Topic__c) || i.Interest_Level__c == null) continue;
      Decimal weight = weightMap.get(i.Interest_Topic__c.trim().toLowerCase());
      if (weight == null || weight == 0) continue;
      scoreMap.put(i.Lead__c, scoreMap.get(i.Lead__c) + (i.Interest_Level__c * weight));  // 関心度×重み
  }
  ```
- **なぜこの実装か**: 「トピックの重み（種類の価値）」×「関心度（その人の強さ）」という
  2 要素の掛け算でスコア化。同じトピックが複数あれば単純合算（仕様）。

> **Salesforce 特有のポイント**: `Lead__c` は **任意 Lookup**（必須でない参照）です。
> そのため `Lead__c == null` の興味レコードがあり得るので、集計前に明示的に除外しています。

### このクラスから学べること
- **null/空チェックを集計の入口で**まとめて行い、以降の計算を単純化する防御的設計。
- 3 Scorer が **同じ骨格**（取得→重み引き→加算→頭打ち）であること。共通化の余地＝設計議論の入口。

### よくある間違い（リファクタ題材の候補）
- **3 Scorer の重複コード**: `getWeightMap()` のキャッシュ機構や「0初期化→加算→Math.min」が
  ほぼ同型。共通の親クラス/ユーティリティへ抽出すべきか（DRY 原則）は絶好のリファクタ題材。
- **単一版 `calculate(Id)` のループ呼び出し → N+1**。

---

# Layer 3: 統括

## 5. LeadScoringService — 3 軸統括（司令塔）

### 役割
3 つの Scorer を呼び出し、合計してカテゴリを判定し、Lead に書き戻す **オーケストレーター**。

### 全体の流れ
```
対象Leadを1回SOQL取得
  → 3 Scorer を呼ぶ（属性/行動/興味）
  → 合計 → determineCategory でカテゴリ決定
  → bypassTrigger=true にして Lead を一括 update（再帰防止）→ finally で false に戻す
```

### 主要なメソッドの解説

#### `calculateScores(Set<Id> leadIds) → void`
- **基本にして中核**のメソッド。すべてのトリガー・コントローラがここに合流します。
- **コードのキモ**:
  ```apex
  Map<Id, Lead> leadMap = new Map<Id, Lead>([
      SELECT Id, Industry, NumberOfEmployees, Title, LeadSource
      FROM Lead WHERE Id IN :leadIds WITH SECURITY_ENFORCED
  ]);
  Map<Id, Decimal> attr = LeadAttributeScorer.calculateBulk(leadMap.values());
  Map<Id, Decimal> beh  = LeadBehaviorScorer.calculateBulk(leadMap.keySet());
  Map<Id, Decimal> intr = LeadInterestScorer.calculateBulk(leadMap.keySet());
  for (Id id : leadMap.keySet()) {
      Decimal total = attr.get(id) + beh.get(id) + intr.get(id);   // ※実際はcontainsKeyで防御
      leadsToUpdate.add(new Lead(Id=id, Score__c=total, Lead_Category__c=determineCategory(total), ...));
  }
  LeadTriggerHandler.bypassTrigger = true;
  try { update leadsToUpdate; }
  finally { LeadTriggerHandler.bypassTrigger = false; }   // ← 必ず戻す
  ```
- **なぜ try/finally か**: スコア反映の `update` が再び Lead トリガーを発火させると **無限ループ**に
  なります。直前にフラグを立てて再発火を抑止し、`finally` で確実にフラグを戻します
  （途中で例外が出てもフラグが立ちっぱなしにならない）。

#### `calculateScore(Id leadId) → void`
- 単一版。`calculateScores(new Set<Id>{ leadId })` を呼ぶラッパー。

#### `determineCategory(Decimal score) → String`
- 閾値（`LeadConstants`）でカテゴリを判定。`score==null` は安全側に倒して `Low`。
  ```apex
  if (score >= LeadConstants.HOT_THRESHOLD)  return LeadConstants.CATEGORY_HOT;   // 180+
  if (score >= LeadConstants.WARM_THRESHOLD) return LeadConstants.CATEGORY_WARM;  // 100+
  if (score >= LeadConstants.COLD_THRESHOLD) return LeadConstants.CATEGORY_COLD;  // 50+
  return LeadConstants.CATEGORY_LOW;
  ```

> **Salesforce 特有のポイント**:
> - `new Map<Id, Lead>([SOQL])` は **クエリ結果を一発で Id→レコードの Map に**できる便利構文。
> - `bypassTrigger` の再帰制御は Salesforce 開発の超頻出パターン。

### このクラスから学べること
- **オーケストレーション**: 自分では細かい計算をせず、専門家（Scorer）に委譲して束ねる。
- **再帰トリガー制御**の定石（static フラグ + try/finally）。
- **冪等な書き戻し**: 何度呼んでも同じ入力なら同じ結果。

### よくある間違い（リファクタ題材の候補）
- **`update` の純増 SOQL/DML**: この 1 メソッドで SOQL 4 回（Lead + 3 Scorer のうち SOQL を打つ
  2 つ + …）・DML 1 回。トリガーから大量レコードを処理する時の合計コストを意識する題材。
- **例外の握り潰し vs 再スロー**: `catch (DmlException e) { System.debug(...); throw e; }` は
  ログ後に再スローしていて妥当。一方で「ログだけして握り潰す」誤りとの対比を学べる。
- **単一版の乱用**: `calculateScore(Id)` をループで呼ぶ実装に出会ったら、
  `calculateScores(Set<Id>)` への置き換えが定番リファクタ。

---

# Layer 4: トリガー

## 6. LeadTriggerHandler — トリガー処理本体

### 役割
Lead トリガーから呼ばれ、イベント種別ごとに「検証」と「再計算」へ振り分ける司令役。

### 全体の流れ
```
before insert/update → LeadValidator.validate（保存前チェック）
after  insert        → 全件 calculateScores（新規は必ず採点）
after  update        → 属性項目が変わった行だけ calculateScores（無駄な再計算を回避）
```

### 主要なメソッドの解説

#### `bypassTrigger`（static Boolean フラグ）
- `LeadScoringService` がスコア反映の `update` をする間だけ true になり、トリガー再発火を抑止。
- `@TestVisible` でテストから参照可能。

#### `afterInsert(List<Lead>, Map<Id,Lead>) → void`
- 新規リードは全件 `LeadScoringService.calculateScores(newMap.keySet())`。

#### `afterUpdate(...) → void`
- **賢い分岐**: 属性に影響する項目が変わった行だけを集めて再計算。
  ```apex
  for (Lead newLead : newLeads) {
      Lead oldLead = oldMap.get(newLead.Id);
      if (oldLead == null || isAttributeChanged(oldLead, newLead)) leadsToRecalc.add(newLead.Id);
  }
  ```

#### `isAttributeChanged(old, new) → Boolean`（private）
- `Industry / NumberOfEmployees / Title / LeadSource` のいずれかが変わったか。
  ```apex
  return old.Industry != new.Industry || old.NumberOfEmployees != new.NumberOfEmployees
      || old.Title != new.Title || old.LeadSource != new.LeadSource;
  ```

> **Salesforce 特有のポイント**: `Trigger.oldMap`/`newMap` で「変更前/後」を比較できます
> （Java の Web フレームワークの「before/after エンティティ」に相当）。変更検知して
> 必要な行だけ処理するのは、ガバナ制限と性能の両面で重要。

### このクラスから学べること
- **Handler パターン**: トリガー本体は薄く、ロジックはハンドラへ。テスト容易＆再利用可。
- **差分検知による最適化**（不要な再計算をしない）。

### よくある間違い（リファクタ題材の候補）
- **static フラグの副作用**: `bypassTrigger` は同一トランザクション内で共有されるため、
  複雑な一括処理で「意図せず別の更新まで抑止」する可能性。フレームワーク化の議論題材。
- **before での検証を Handler に置くか Validator に置くか**: 責務境界の議論。

---

## 7. LeadTrigger — Lead 用トリガー

### 役割
Lead の保存イベントを受け取り、`LeadTriggerHandler` に委譲するだけの「薄い入口」。

### 全体の流れ
```
bypassTrigger が立っていれば即 return（再帰防止）
before insert → handler.beforeInsert        after insert → handler.afterInsert
before update → handler.beforeUpdate        after update → handler.afterUpdate
```
```apex
trigger LeadTrigger on Lead (before insert, before update, after insert, after update) {
    if (LeadTriggerHandler.bypassTrigger) return;
    if (Trigger.isBefore) {
        if (Trigger.isInsert) LeadTriggerHandler.beforeInsert(Trigger.new);
        else if (Trigger.isUpdate) LeadTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    } else if (Trigger.isAfter) { ... }
}
```

### このクラスから学べること
- **One Trigger Per Object**: 1 オブジェクトにつきトリガーは 1 本だけにし、分岐は中で行う。
- トリガーに **ロジックを書かない**（条件分岐と委譲のみ）。

### よくある間違い（リファクタ題材の候補）
- トリガー内に SOQL/DML やビジネスロジックを直書きする（このクラスは正しく回避できている良い例）。

> **Salesforce 特有のポイント**: `Trigger.isBefore/isAfter/isInsert/isUpdate` は
> 「今どのイベントか」を表すコンテキスト変数。Java のイベントオブジェクトの種別判定に近い。

---

## 8. LeadInterestTrigger / LeadInterestTriggerHandler — Lead_Interest__c 用

### 役割
興味レコードの変更（追加・更新・削除・復元）で、紐づく Lead のスコアを再計算する。
トリガーは委譲のみ、ロジックは `LeadInterestTriggerHandler` が持つ（`LeadTrigger` と同一パターン）。

### 全体の流れ
```
LeadInterestTrigger（薄い）         LeadInterestTriggerHandler（本体）
  bypassTrigger なら return          afterInsert/Undelete : Trigger.new の親を集約
  after イベント種別で振り分け  ──►   afterUpdate          : 新親 + 旧親（付け替え元）を集約
                                     afterDelete          : Trigger.old の親を集約
                                          → LeadScoringService.calculateScores(leadIds)
```
```apex
// トリガー：委譲のみ
trigger LeadInterestTrigger on Lead_Interest__c (after insert, after update, after delete, after undelete) {
    if (LeadTriggerHandler.bypassTrigger) return;
    if (Trigger.isAfter) {
        if (Trigger.isInsert)        LeadInterestTriggerHandler.afterInsert(Trigger.new);
        else if (Trigger.isUpdate)   LeadInterestTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        else if (Trigger.isDelete)   LeadInterestTriggerHandler.afterDelete(Trigger.old);
        else if (Trigger.isUndelete) LeadInterestTriggerHandler.afterUndelete(Trigger.new);
    }
}
```

### このクラスから学べること
- **Handler パターンの統一**: トリガーは「種別で振り分けて委譲」だけ。ロジックはハンドラへ。
- **親集約パターン**: 子（興味）の変更で親（Lead）を再計算する際は、影響する親 Id を Set に
  集めて最後に 1 回だけサービスを呼ぶ（バルク化）。
- **付け替え対応**: update では「新しい親」と「元の親（`oldMap`）」の双方を再計算対象に含める。

### 設計ポイント（このお手本で守っていること）
- delete 時に `Trigger.new` を触ると null で落ちるため、delete は `Trigger.old` を使う。
- `bypassTrigger` 早期 return をトリガー・ハンドラ双方に置き、`LeadTrigger` と挙動を揃える。

---

## 9. CampaignMemberTrigger / CampaignMemberTriggerHandler — CampaignMember 用

### 役割
キャンペーン参加の変更で、紐づく Lead の（行動）スコアを再計算する。
こちらも委譲のみのトリガー + `CampaignMemberTriggerHandler` の構成。

### 全体の流れ
```
afterInsert/Undelete : Trigger.new の LeadId を集約
afterUpdate          : 新 LeadId + 旧 LeadId を集約
afterDelete          : Trigger.old の LeadId を集約
  → Contact 経由（LeadId == null）はスキップ → LeadScoringService.calculateScores(leadIds)
```

### このクラスから学べること
- `LeadInterestTriggerHandler` と **同じ親集約パターン**。CampaignMember は Lead/Contact 両対応なので
  `LeadId == null`（＝Contact 由来）を除外する判断が入る。

### 設計ポイント
- `CampaignMember` は DML での undelete が不可。そのため `afterUndelete` は実運用では呼ばれにくいが、
  パターンの一貫性のためにメソッドは用意し、テストはハンドラ直接呼び出しで担保している。

> **3 トリガーの統一構造（修正済み・お手本の完成形）**:
> ```
>   LeadTrigger            → LeadTriggerHandler            → LeadScoringService
>   LeadInterestTrigger    → LeadInterestTriggerHandler    → LeadScoringService
>   CampaignMemberTrigger  → CampaignMemberTriggerHandler  → LeadScoringService
> ```
> 3 トリガーすべてが「薄いトリガー + Handler 委譲 + bypassTrigger 早期 return」で統一されている。

---

# Layer 5: ビジネスロジック・バリデーション

## 10. LeadValidator — バリデーション

### 役割
保存前にリードの妥当性（必須項目・メール形式）をチェックする検証専門クラス。

### 全体の流れ
```
validate(リスト) → 各Leadに対して 必須項目チェック + メール形式チェック
不正は例外ではなく addError() で該当項目にエラー表示（その行だけ保存中止）
```

### 主要なメソッドの解説

#### `validate(List<Lead>) → void`
- バルク入口。各リードに `validateRequiredFields` と `validateEmail` を適用。

#### `validateRequiredFields(Lead) / validateEmail(Lead)`
- **`addError()` の使い方が肝**:
  ```apex
  if (String.isBlank(lead.LastName)) lead.LastName.addError('姓は必須項目です');
  if (!Pattern.matches(EMAIL_PATTERN, lead.Email)) lead.Email.addError('メールアドレスの形式が正しくありません');
  ```
- メールは **空ならスキップ**（任意項目扱い）。入っている時だけ正規表現で検証。

#### `findDuplicatesByCompany(Set<String>) → Map<String, List<Lead>>`
- 会社名で既存リードを引き、`会社名 → 一致リード群` の Map を返す（警告レベルの参照用）。

> **Salesforce 特有のポイント**: `addError()` は **例外を投げずに保存をブロック**する仕組み。
> Java の例外（throw）と違い、**正常な行は保存され、不正な行だけ拒否**できます。
> 200 件中 1 件が不正でも、残り 199 件は通せる（部分成功）のが利点。

### このクラスから学べること
- **`addError()` による行単位の検証**（バルク処理での部分成功）。
- 検証ロジックを 1 クラスに集約し、トリガー/ハンドラから切り離す。

### よくある間違い（リファクタ題材の候補）
- **検証で `throw` してしまう**: 1 件の不正で全件ロールバックになりがち。`addError()` との
  違いを体感する好題材（このクラスは正しく `addError()` を使えている良い見本）。
- メール正規表現をコードに直書き → カスタムラベル/定数化の検討余地。

---

## 11. LeadService — ビジネスロジック中核

### 役割
リードの取得・検索・更新など「画面にもトリガーにも依存しない汎用操作」を提供する。

### 全体の流れ
取得系（カテゴリ別/全件/検索）は **SOQL に `WITH SECURITY_ENFORCED` と `LIMIT`** を付けて
安全に返す。

### 主要なメソッドの解説

#### `getLeadsByCategory(String, Integer) / getAllLeads(Integer)`
- カテゴリ別／全件をスコア降順で取得。`normalizeLimit()` で件数を 1〜200 に正規化。

#### `searchLeads(String searchTerm, Integer) → List<Lead>`
- 名前・会社名の部分一致検索。
  ```apex
  String escaped = String.escapeSingleQuotes(searchTerm);   // 規約に従いエスケープ
  String pattern = '%' + escaped + '%';
  return [SELECT ... WHERE Name LIKE :pattern OR Company LIKE :pattern WITH SECURITY_ENFORCED ...];
  ```
- **バインド変数 `:pattern`** を使っているので、本来 SOQL インジェクションは起きません
  （エスケープは二重の安全策）。

> **Salesforce 特有のポイント**:
> - `WITH SECURITY_ENFORCED` = クエリに **項目/オブジェクトのアクセス権チェックを強制**。
> - **バインド変数（`:変数`）** は値を安全に埋め込む仕組み（Java の PreparedStatement の `?` 相当）。
> - `isUpdateable()` 等の **CRUD/FLS チェック**は、ユーザー権限を尊重する Apex の作法。

> **このサービスが SOQL の唯一の置き場所**: スコア内訳 `getScoreBreakdown(Id)` と
> 興味一覧 `getInterests(Id)`（関心度降順・`LIMIT 100`）もここに集約されている。
> Controller からはこれらを **委譲呼び出し** するだけ（修正2で SOQL を Controller から移設）。

### このクラスから学べること
- **SOQL の作法**: `WITH SECURITY_ENFORCED` + `LIMIT` + `ORDER BY` をセットで。
- **入力の正規化**（`normalizeLimit`）で上限暴走を防ぐ。

### よくある間違い（リファクタ題材の候補）
- **エスケープとバインドの二重掛け**: `searchLeads` はバインド変数を使っているため
  `String.escapeSingleQuotes` は実質不要。害はないが「どちらか一方で十分」という
  理解の確認に使える小ネタ（明確な欠陥ではない設計判断レベル）。

---

# Layer 6: プレゼンテーション

## 12. LeadController — LWC からの窓口

### 役割
画面（Lightning Web Component）から呼ばれる入口。処理は下層へ委譲し、例外を整形して返すだけ。

### 全体の流れ
```
@AuraEnabled メソッドを公開
  → try で下層（LeadService / LeadScoringService）を呼ぶ
  → catch でログを残し、ユーザーには分かりやすい AuraHandledException を返す
読み取り系は cacheable=true、状態変更系は cacheable=false
```

### 主要なメソッドの解説

> **UI 整理の経緯**: 一覧（leadList）・検索（leadSearch）・詳細（leadDetail）の各 LWC は
> 標準 UI／レコードページで代替できるため廃止した。これに伴い、それらの窓口だった
> `getLeadList` / `searchLeads`（Controller の `@AuraEnabled` メソッド）も撤去した。
> ただし一覧取得・検索の **ビジネスロジック自体は `LeadService`** に
> （`getAllLeads` / `getLeadsByCategory` / `searchLeads`）残してあり、将来の再利用に備えている。

#### `recalculateScore(Id) → void`
- 再計算は `LeadScoringService.calculateScores` へ委譲。
- `recalculateScore` は **状態を変える** ので `@AuraEnabled`（cacheable なし）。

#### `getScoreBreakdown(Id) / getInterests(Id)`
- スコア内訳・興味一覧を返す。**いずれも `LeadService` へ委譲のみ**（修正2で SOQL を撤去）。
  サービスが投げる標準例外（`IllegalArgumentException` / `QueryException`）を
  `catch (Exception e)` でまとめて `AuraHandledException` にラップする。

> **Salesforce 特有のポイント**:
> - `@AuraEnabled` = この Apex メソッドを **JS(LWC) から呼べるよう公開**する印。
> - `cacheable=true` = 読み取り専用としてクライアントキャッシュ可（高速・`@wire` で使える）。
> - `AuraHandledException` = **内部のスタックトレースを隠し**、ユーザーには安全な文言だけ見せる。
>   生の例外を返すと実装詳細が漏れるため、必ずラップするのが作法。

### このクラスから学べること
- **薄いコントローラ（お手本）**: SOQL を一切持たず、`LeadService` / `LeadScoringService` への
  委譲＋例外整形に徹する。SOQL はすべてサービス層に集約されている（修正2で是正済み）。
- **例外変換は Controller の責務**: サービス層の標準例外（`SecurityException` /
  `QueryException` / `IllegalArgumentException` / `DmlException`）を、ここで初めて
  ユーザー向けの `AuraHandledException` に変換する。**層の境界で例外の種類を切り替える**のが要点。
- 読み取り/書き込みで **cacheable を使い分ける**。

### 設計ポイント（このお手本で守っていること）
- 生の例外メッセージ（実装詳細やスタックトレース）を画面に出さず、`AuraHandledException` の
  安全な日本語文言に置き換える。

---

## まとめ — リファクタリング演習の着眼点（全体）

### ✅ 構造的逸脱は是正済み（このリポジトリは「完璧なお手本」）

以下は **構造的なベストプラクティス逸脱**で、すでに修正済みです。お手本として
「どう直したか」を読むこと自体が学習材料になります。

| 是正項目 | 修正内容 |
|---|---|
| **トリガー設計の統一** | 3 トリガーすべてを「薄いトリガー + 専用 Handler 委譲」に統一（`LeadInterestTriggerHandler` / `CampaignMemberTriggerHandler` を新設）。 |
| **層の責務（SOQL）** | Controller 直書きの SOQL を `LeadService.getScoreBreakdown` / `getInterests` へ移設。Controller は委譲のみ。 |
| **層の責務（例外）** | サービス層は標準例外（`SecurityException` 等）を投げ、UI 向け `AuraHandledException` への変換は Controller の責務に分離。 |

### 🔍 残る「議論題材」（演習で扱う ＝ 明確な悪ではなく設計判断の余地）

| 観点 | 具体例（このコード内の候補） |
|---|---|
| **重複排除(DRY)** | 3 Scorer の `getWeightMap()` キャッシュ機構と「0初期化→加算→`Math.min`」の骨格がほぼ同型。共通の親クラス/ユーティリティへ抽出するか？（ただし Strategy として独立を保つ判断もあり得る） |
| **定数化（マジックナンバー/文字列）** | 規模境界 `1000/100/10`、CMDT キー文字列（`'NumberOfEmployees_1000+'` 等）、役職キーワード、メール正規表現などの外出し。どこまで `LeadConstants`/CMDT に寄せるか。 |
| **単一版メソッドの扱い** | `calculate()` / `calculateScore(Id)` をループで呼ぶと N+1。残すべきか、バルク版に一本化すべきか。 |
| **設定依存の堅牢性** | CampaignMemberStatus の言語不一致（日本語既定）でキーが一致せず重み0になる等、データ設定に依存する箇所の扱い。 |
| **差分検知の最適化** | CampaignMember/興味の更新で、重みに影響しない変更でも再計算する。属性更新（`isAttributeChanged`）のような差分検知を他にも広げるか。 |

> 上段（✅）は「直すべき構造的欠陥」として是正済み。下段（🔍）は **「なぜそうなっているか」**
> を考える議論ポイントで、あえて残しています。演習では下段を題材に、
> **変更がテストで守られているか**（各クラスに対応テストあり）を確認しながら進めてください。
