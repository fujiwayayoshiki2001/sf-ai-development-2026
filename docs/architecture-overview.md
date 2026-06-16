# プロジェクト全体マップ — リード管理・スコアリングシステム

> 対象読者: Salesforce 初学者（Java 経験あり）
> このドキュメントは `force-app/main/default/classes` 配下の全 Apex クラスと
> トリガーを俯瞰し、「どのクラスが何を担い、どう連携するか」を理解するためのものです。

---

## 1. このシステムは何をするか

**一言で**: リード（見込み客）を **属性・行動・興味** の 3 つの軸で自動採点し、
スコアの高い順に「今すぐ営業すべき相手」を可視化するシステムです。

**業務上の価値**: 営業担当は何百件ものリードを前に「どれから連絡するか」で迷います。
このシステムは、リードや関連データが更新されるたびに **自動でスコアを再計算** し、
`Hot / Warm / Cold / Low` のカテゴリに分類します。営業は **Hot から順に対応** すれば
よく、勘ではなくデータで優先順位を決められます。

```
最終スコア = 属性スコア(最大100) + 行動スコア(最大120) + 興味スコア(最大80)  = 最大300点

  180点以上 → Hot   (即対応)
  100〜179  → Warm  (フォロー)
   50〜 99  → Cold  (育成)
    0〜 49  → Low   (低優先)
```

| 軸 | 「何を見るか」 | データソース | 計算クラス |
|---|---|---|---|
| 属性 | リード自身の素性（業界・規模・役職・流入元） | Lead レコード | `LeadAttributeScorer` |
| 行動 | キャンペーンへの参加履歴（＋時間減衰） | CampaignMember（標準） | `LeadBehaviorScorer` |
| 興味 | 検知された関心トピックと関心度 | Lead_Interest__c（カスタム） | `LeadInterestScorer` |

---

## 2. アーキテクチャ図

### レイヤー構造（呼び出しは上から下への一方向）

```
 ┌─────────────────────────────────────────────────────────────┐
 │  プレゼンテーション層（画面）                                   │
 │   LWC:  leadScoreCard / leadInterestRadar                    │
 │   （一覧・検索・詳細は標準UI／レコードページに集約）             │
 └───────────────┬─────────────────────────────────────────────┘
                 │ @AuraEnabled 呼び出し（JSの fetch のようなもの）
                 ▼
 ┌─────────────────────────────────────────────────────────────┐
 │  コントローラ層   LeadController                              │
 │   画面の窓口。受け取って下層へ委譲し、例外を整形して返すだけ      │
 └───────────────┬─────────────────────────────────────────────┘
                 ▼
 ┌─────────────────────────────────────────────────────────────┐
 │  ビジネスロジック層                                            │
 │   LeadService(取得・検索)   LeadValidator(入力チェック)         │
 │   LeadScoringService(スコア統括) ←─ ここが司令塔               │
 └───────────────┬─────────────────────────────────────────────┘
                 ▼
 ┌─────────────────────────────────────────────────────────────┐
 │  スコアリング層（3つの専門家）                                  │
 │   LeadAttributeScorer   LeadBehaviorScorer   LeadInterestScorer│
 └───────────────┬─────────────────────────────────────────────┘
                 ▼
 ┌─────────────────────────────────────────────────────────────┐
 │  定数・設定                                                    │
 │   LeadConstants(Apex定数)   Lead_Scoring_Config__mdt(重み表)   │
 └─────────────────────────────────────────────────────────────┘
```

### トリガーの位置づけ（イベント駆動の入口）

トリガーは「データが変わった瞬間」に自動で割り込む仕組みです（Java の
イベントリスナーに近い）。このシステムでは **3 つのトリガーがすべて
「薄いトリガー → 専用 Handler → `LeadScoringService`」** の同一パターンで再計算します
（Handler パターンで統一）。

```
   [Lead を保存]          [CampaignMember を保存]      [Lead_Interest__c を保存]
        │                        │                            │
        ▼                        ▼                            ▼
   LeadTrigger            CampaignMemberTrigger        LeadInterestTrigger
        │  (薄い)                │  (薄い)                     │  (薄い)
        ▼                        ▼                            ▼
   LeadTriggerHandler   CampaignMemberTriggerHandler   LeadInterestTriggerHandler
        │                        │                            │
        └────────────────────────┼────────────────────────────┘
                                 ▼
                 LeadScoringService.calculateScores(対象LeadのId)
                                 │
             ┌───────────────────┼───────────────────┐
             ▼                   ▼                   ▼
      AttributeScorer      BehaviorScorer       InterestScorer
             └───────────────────┼───────────────────┘
                                 ▼
                     合計 → カテゴリ判定 → Lead を update
```

> **設計の統一（お手本）**: 3 トリガーはどれも「イベント種別で振り分けて Handler に委譲する」
> だけの薄い実装。再計算ロジックは各 Handler が持ち、最終的に `LeadScoringService` に合流する。
> 入口（オブジェクト）が違っても処理の形がそろっているため、読みやすく拡張しやすい。

> **ポイント**: 3 つの軸はそれぞれ別のオブジェクトに住んでいます。だから
> 「キャンペーンに参加した」「興味が検知された」など **どの軸が動いても**、
> 対応するトリガーが発火して同じ司令塔（`LeadScoringService`）に集約されます。

---

## 3. レイヤー別のクラス一覧

### 定数層
**役割**: マジックナンバー（180 や 0.95 などの謎の数字）をコードに直書きせず一元管理する。

| クラス | 1 行説明 |
|---|---|
| `LeadConstants` | 閾値(Hot=180 等)・スコア上限・減衰係数(0.95)・カテゴリ名・業界名などの `static final` 定数集。 |

> Java 対比: Java の `public static final` 定数クラスとほぼ同じ。`final` の意味も同じ（再代入不可）。

### スコアリング層（3 つの専門家）
**役割**: 1 つの軸だけを計算する「単機能の専門家」。重みは `Lead_Scoring_Config__mdt`（カスタムメタデータ＝コードを変えずに編集できる設定表）から読む。

| クラス | 1 行説明 |
|---|---|
| `LeadAttributeScorer` | リード自身の項目(業界/従業員数/役職/流入元)を重み表で採点。SOQL なし・最大100点で頭打ち。 |
| `LeadBehaviorScorer` | リードの CampaignMember を集計し、`Type_Status` の重み × 時間減衰(0.95^経過日数)で採点。最大120点。 |
| `LeadInterestScorer` | リードの Lead_Interest__c を集計し、トピック重み × 関心度(Interest_Level)で採点。最大80点。 |

> **カスタムメタデータ型(`__mdt`)とは**: 「設定値をレコードとして持てる仕組み」。
> 重みを変えたいときに Apex を書き換えず、設定レコードを編集するだけで済みます。
> Java で言えば、定数を `.properties` ファイルに外出しして読み込むイメージです。

### ビジネスロジック層
**役割**: 複数の処理を組み立てる「中核」。画面にもトリガーにも依存しない純粋なロジック。

| クラス | 1 行説明 |
|---|---|
| `LeadScoringService` | **司令塔**。3 Scorer を呼び合計→カテゴリ判定→Lead を一括 update。再帰防止フラグも管理。 |
| `LeadService` | リードの取得・検索・最終アクション日更新・陳腐化(Stale)候補抽出など汎用操作。 |
| `LeadValidator` | 保存前の入力チェック（姓・会社名の必須、メール形式）。会社名重複の参照も提供。 |

### トリガー層
**役割**: データ変更イベントを受け取り、ロジックは持たずハンドラ/サービスへ委譲する「薄い入口」。

| ファイル | 1 行説明 |
|---|---|
| `LeadTrigger`（trigger） | Lead の保存イベントを受け、`LeadTriggerHandler` に委譲するだけの薄いトリガー。 |
| `LeadTriggerHandler` | before=検証、afterInsert=全件採点、afterUpdate=属性項目が変わった行のみ再採点、と振り分ける。 |
| `CampaignMemberTrigger`（trigger） | `CampaignMemberTriggerHandler` に委譲するだけの薄いトリガー。 |
| `CampaignMemberTriggerHandler` | キャンペーン参加の変更で紐づく Lead を再計算（Contact 経由=LeadId null は除外、update は旧 LeadId も対象）。 |
| `LeadInterestTrigger`（trigger） | `LeadInterestTriggerHandler` に委譲するだけの薄いトリガー。 |
| `LeadInterestTriggerHandler` | 興味レコードの変更で紐づく Lead を再計算（Lead__c が null は除外、update は旧親も対象）。 |

> **なぜトリガーは「薄く」するのか**: Salesforce のベストプラクティス。トリガーに
> ロジックを書くとテスト・再利用・順序制御が難しくなるため、ロジックは必ず
> ハンドラ/サービスのクラス側に置きます（"One Trigger Per Object" + Handler パターン）。

### プレゼンテーション層（コントローラ）
**役割**: 画面(LWC)と裏側ロジックの橋渡し。`@AuraEnabled` で JS から呼べるようにする。

| クラス | 1 行説明 |
|---|---|
| `LeadController` | LWC 窓口。スコア内訳/興味一覧/再計算/最終アクション日更新を公開し、処理は下層へ委譲・例外を整形。 |

> `@AuraEnabled(cacheable=true)` = 読み取り専用でブラウザキャッシュ可（高速）。
> 状態を変えるメソッド（`recalculateScore`）は `cacheable=false`。

### テスト支援層
**役割**: テスト用データをまとめて生成する道具。

| クラス | 1 行説明 |
|---|---|
| `TestDataFactory` | リード/興味/キャンペーン/メンバーを生成して返す（あえて insert せず List を返す設計）。 |

---

## 4. 主要なデータの流れ — 「リード作成 → スコア確定」

新しいリードを 1 件保存したときに何が起きるかを順に追います。

```
① ユーザーが Lead を保存（insert）
        │
        ▼
② LeadTrigger が発火
   ├ before insert → LeadTriggerHandler.beforeInsert → LeadValidator.validate
   │                  （姓・会社名の必須、メール形式をチェック。NGなら addError で保存中止）
   │
   └ after insert  → LeadTriggerHandler.afterInsert
                          │  (この時点で Lead に Id が採番されている)
                          ▼
③ LeadScoringService.calculateScores( {そのLeadのId} )
        │
        │  1回の SOQL で対象 Lead を取得し、3 つの Scorer を呼ぶ
        ├─► LeadAttributeScorer.calculateBulk  → 属性スコア（CMDTの重み＋Lead項目）
        ├─► LeadBehaviorScorer.calculateBulk   → 行動スコア（CampaignMember＋時間減衰）
        └─► LeadInterestScorer.calculateBulk   → 興味スコア（Lead_Interest__c＋関心度）
                          │
                          ▼
④ 3スコアを合計 → determineCategory() で Hot/Warm/Cold/Low を判定
        │
        ▼
⑤ Lead を update（Score__c, 各軸スコア, Lead_Category__c, 計算日時 を反映）
        │  ※このとき bypassTrigger=true にして、update による
        │    トリガー再発火（無限ループ）を防止。finally で必ず false に戻す。
        ▼
⑥ 画面では leadScoreCard / leadInterestRadar が新しい値を表示
```

**更新時の賢い分岐**: リードを*更新*した場合、`afterUpdate` は
**属性に影響する項目（Industry / NumberOfEmployees / Title / LeadSource）が
変わった行だけ** を再計算します（`isAttributeChanged()`）。無関係な項目の更新で
毎回フル再計算しないための最適化です。

**別の軸が動いた場合**: キャンペーン参加や興味レコードが変わると、
`CampaignMemberTrigger` / `LeadInterestTrigger` が発火し、③ と同じ
`calculateScores()` に合流します（入口が違うだけで処理は共通）。

---

## 5. クラス間の依存関係

「A → B」は「A が B を呼ぶ」を表します。**矢印は常に上の層から下の層へ**だけ
向き、逆流（下位が上位を呼ぶ）はありません。これが保守しやすさの肝です。

```
LWC (leadInterestRadar 等)
   │
   ▼
LeadController
   ├──────────────► LeadService ───────────► LeadConstants
   └──────────────► LeadScoringService
                         ├──► LeadAttributeScorer ─► Lead_Scoring_Config__mdt / LeadConstants
                         ├──► LeadBehaviorScorer  ─► Lead_Scoring_Config__mdt / LeadConstants
                         ├──► LeadInterestScorer  ─► Lead_Scoring_Config__mdt / LeadConstants
                         └──► LeadConstants (カテゴリ判定の閾値)

LeadTrigger           ───► LeadTriggerHandler           ──┬──► LeadValidator ──► (SOQL: Lead)
                                                          └──► LeadScoringService
CampaignMemberTrigger ───► CampaignMemberTriggerHandler ─────► LeadScoringService
LeadInterestTrigger   ───► LeadInterestTriggerHandler   ─────► LeadScoringService
```

> 補足: `LeadController` は SOQL を持たず、スコア内訳・興味一覧の取得も
> `LeadService.getScoreBreakdown` / `getInterests` へ委譲する（SOQL はサービス層に集約）。
> また各層は例外の種類で責務を分ける: サービス層は標準例外（`SecurityException` 等）を投げ、
> Controller がそれを UI 向けの `AuraHandledException` に変換する。

箇条書きでの要点:
- **`LeadScoringService` が合流点**: 3 つのトリガー・`LeadController`・（再計算ボタン）から呼ばれる。
- **3 Scorer は互いを知らない**: それぞれ独立。`LeadScoringService` だけが 3 つをまとめる。
- **`LeadConstants` は誰からでも参照される葉ノード**: 何も呼ばない（依存の終端）。
- **`LeadValidator` と各 Scorer は同じ層だが互いを呼ばない**: 役割が独立しているため。
- **逆方向依存ゼロ**: 例えば `LeadAttributeScorer` が `LeadScoringService` を呼ぶことは無い。

> Java 対比: Controller → Service → （Strategy 的な）Scorer という典型的な
> レイヤードアーキテクチャです。Scorer 3 種は「同じ仕事(採点)を別アルゴリズムで行う」
> という意味で **Strategy パターン** に近い構成です。

---

## 6. テストクラスとの対応

Salesforce は **本番デプロイにコードカバレッジ 75% 以上** を要求します。
そのため原則 1 本番クラスにつき 1 テストクラスを用意しています。

| 本番クラス | 対応するテストクラス |
|---|---|
| `LeadAttributeScorer` | `LeadAttributeScorerTest` |
| `LeadBehaviorScorer` | `LeadBehaviorScorerTest` |
| `LeadInterestScorer` | `LeadInterestScorerTest` |
| `LeadScoringService` | `LeadScoringServiceTest` |
| `LeadService` | `LeadServiceTest` |
| `LeadValidator` | `LeadValidatorTest` |
| `LeadController` | `LeadControllerTest` |
| `LeadTrigger` / `LeadTriggerHandler` | `LeadTriggerTest` |
| `LeadInterestTrigger` / `LeadInterestTriggerHandler` | `LeadInterestTriggerHandlerTest`（+ `LeadTriggerTest`） |
| `CampaignMemberTrigger` / `CampaignMemberTriggerHandler` | `CampaignMemberTriggerHandlerTest`（+ `LeadTriggerTest`） |
| `TestDataFactory` | `TestDataFactoryTest` |
| `LeadConstants` | （専用テストなし。定数のため他テストで間接的にカバー） |

> **`TestDataFactory` 自身にもテストがある点に注目**: テスト用クラスでも
> カバレッジ対象なので、ファクトリ自体の動作確認テストを用意しています。

テストの基本パターン（このプロジェクトの方針）:
- `@TestSetup` で共通データを 1 度だけ作る
- `Test.startTest()` / `Test.stopTest()` で計測区間を囲む
- **200 件のバルクテスト**でガバナ制限（後述）に耐えるか検証する
- 正常系だけでなく **異常系（必須項目なし等）** も検証する

---

## 7. 受講者へのメッセージ — このプロジェクトから学べること

### ① 単一責任＋レイヤード設計（読みやすさの源泉）
1 クラス＝1 役割に徹し、呼び出しを一方向に保つと、変更の影響範囲が局所化されます。
「スコアの重みを変えたい」なら Scorer か CMDT、「画面の出し方を変えたい」なら
Controller/LWC、と **触る場所が一目で分かる** のが最大の利点です。

### ② トリガーは薄く、ロジックはクラスへ（Salesforce 必修パターン）
`LeadTrigger` は判定だけして `LeadTriggerHandler` に丸投げします。さらに
`bypassTrigger` フラグで **「自分の update が自分のトリガーを再発火させる無限ループ」**
を防いでいます。これは Salesforce 開発で必ず出会う定石です。

### ③ バルク化とガバナ制限（クラウド特有の最重要知識）
Salesforce は共有環境のため「1 処理あたり SOQL 100 回・DML 150 回まで」等の
**ガバナ制限** があります。だから各 Scorer は **ループの外で 1 回だけ SOQL** を
発行し、`Map<Id, Decimal>` で結果を引き当てます。

```apex
// ❌ Java感覚でやりがちな悪い例（ループ内クエリ → 200件で制限超過）
for (Lead l : leads) { List<CampaignMember> m = [SELECT ... WHERE LeadId = :l.Id]; }

// ✅ このプロジェクトの正しい例（クエリ1回 → Mapで引く）
List<CampaignMember> all = [SELECT ... WHERE LeadId IN :leadIds];
```

> Java の「N+1 問題」と同じ発想ですが、Salesforce では**違反すると即例外で停止**する
> という点でより厳格です。

### ④ セキュリティをコードで担保する
全 SOQL に `WITH SECURITY_ENFORCED`（実行ユーザーの項目アクセス権を強制）を付け、
検索文字列は `String.escapeSingleQuotes()` でエスケープしています。Controller は
内部例外をそのまま見せず `AuraHandledException` で安全なメッセージに整形します。

### ⑤ 設定はコードの外へ（カスタムメタデータの活用）
スコアの重みを Apex に直書きせず `Lead_Scoring_Config__mdt` に外出ししています。
**コードを修正・再デプロイせずに営業戦略（重み）を調整** でき、変更がデプロイ
パッケージに含まれて環境間で再現できます。

---

### 付録: 用語ミニ辞典（Java 経験者向け）

| 用語 | ざっくり言うと |
|---|---|
| SOQL | DB から SELECT するための専用言語（Salesforce 版 SQL、SELECT のみ）。 |
| DML | `insert`/`update`/`delete` など書き込み操作。 |
| ガバナ制限 | 1トランザクションあたりの SOQL/DML/CPU 等の上限。超えると例外。 |
| トリガー | レコード保存時に自動実行されるイベントハンドラ。 |
| `WITH SECURITY_ENFORCED` | クエリにFLS/オブジェクト権限チェックを強制する句。 |
| カスタムメタデータ型(`__mdt`) | 設定値をレコードで持てる仕組み（外部設定ファイル相当）。 |
| `@AuraEnabled` | Apex メソッドをフロント(LWC)から呼べるよう公開する注釈。 |
| `with sharing` | 実行ユーザーの共有ルール（レコード可視性）を尊重するクラス宣言。 |
| バルク化 | 1件ずつでなく複数件をまとめて処理する設計（ガバナ制限対策）。 |
```
