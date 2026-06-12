---
name: review-governor-limits
description: |
  Apex コードのガバナ制限違反をチェックするスキル。
  Salesforce プラットフォーム特有のリソース制限に違反する可能性のあるパターンを検出し、
  バルク処理対応の改善案を提示する。

  以下のような場面で使用：
  - 「ガバナ制限の観点でレビューして」
  - 「ループ内 SOQL/DML をチェックして」
  - 「バルク処理の問題を見つけて」
  - /review-governor-limits コマンドが実行されたとき
  - /review コマンドの一部として呼ばれたとき
---

# ガバナ制限レビュー

このスキルは、Apex コードのガバナ制限違反を検出します。

## あなたの役割

Salesforce プラットフォームの専門家として、ガバナ制限の観点でコードをレビューしてください。

## 必ずチェックする項目

### 1. ループ内 SOQL（最重要）

```apex
// 検出パターン
for (... : ...) {
    ... = [SELECT ... FROM ... WHERE ...];  // ← 検出
}
```

**問題点**: 1トランザクションあたり SOQL は 100 件まで。
ループが 100 件を超えるとガバナ制限超過。

**改善案**: ループ外で一回クエリして Map で関連付ける

```apex
// 改善後
Set<Id> relatedIds = new Set<Id>();
for (... : ...) {
    relatedIds.add(...);
}

Map<Id, RelatedObject> relatedMap = new Map<Id, RelatedObject>(
    [SELECT ... FROM ... WHERE Id IN :relatedIds WITH SECURITY_ENFORCED]
);

for (... : ...) {
    RelatedObject related = relatedMap.get(...);
    // 処理
}
```

### 2. ループ内 DML

```apex
// 検出パターン
for (... : ...) {
    insert obj;   // ← 検出
    update obj;   // ← 検出
    delete obj;   // ← 検出
}
```

**問題点**: 1トランザクションあたり DML は 150 件まで。

**改善案**: リストに溜めてループ外でバルク DML

```apex
List<Object> toUpdate = new List<Object>();
for (... : ...) {
    toUpdate.add(...);
}
update toUpdate;
```

### 3. クエリ件数の上限

```apex
// 検出パターン
List<Lead> leads = [SELECT ... FROM Lead];  // LIMIT なし
```

**問題点**: 50,000 件を超えると例外発生。

**改善案**:
- 必要な件数だけ LIMIT で取得
- 大量データはバッチ処理 (Database.Batchable) を検討

### 4. ヒープサイズ

```apex
// 検出パターン
List<Lead> allLeads = [SELECT Id, Name, Description, /* 大量の項目 */ FROM Lead];
```

**問題点**: 同期 6MB、非同期 12MB の制限。

**改善案**:
- 必要な項目だけ SELECT
- ストリーミング処理（SOQL For Loop）

```apex
// 改善後
for (Lead lead : [SELECT Id, Name FROM Lead WITH SECURITY_ENFORCED]) {
    // 1件ずつ処理されるのでヒープサイズに優しい
}
```

### 5. 集計クエリの SQL Row 制限

```apex
// 検出パターン
AggregateResult[] results = [SELECT COUNT(Id), AVG(Score__c) FROM Lead];
```

**問題点**: GROUP BY なしの集計は 50,000 件まで。

**改善案**: 適切な WHERE 句で絞り込み

### 6. CPU 時間

```apex
// 検出パターン
- 多重ネストループ
- 大量データの文字列処理
- 不必要な処理の繰り返し
```

**問題点**: 同期 10秒、非同期 60 秒の制限。

**改善案**: アルゴリズム見直し、非同期化

## チェックしないこと

以下は **意図的な仕込みの可能性** があるため、研修プロジェクトでは指摘するが「これは研修のためかも」と注記する：
- なし（研修教材であることは別途認識されている）

## 出力フォーマット

各検出に対して、以下の形式で報告してください。

```markdown
### [問題 N] ループ内 SOQL

**場所**: `force-app/main/default/classes/LeadBehaviorScorer.cls` 行 25-32

**現在のコード**:
```apex
for (Id leadId : leadIds) {
    List<CampaignMember> members = [
        SELECT Id, ...
        FROM CampaignMember
        WHERE LeadId = :leadId
    ];
}
```

**問題**: 
ループ内で SOQL を実行しています。リード件数が増えると 100 クエリの制限に到達します。

**改善案**:
ループ外で一度に取得し、Map で関連付けます。

```apex
List<CampaignMember> allMembers = [
    SELECT Id, LeadId, ...
    FROM CampaignMember
    WHERE LeadId IN :leadIds
    WITH SECURITY_ENFORCED
];

Map<Id, List<CampaignMember>> membersByLead = new Map<Id, List<CampaignMember>>();
for (CampaignMember cm : allMembers) {
    if (!membersByLead.containsKey(cm.LeadId)) {
        membersByLead.put(cm.LeadId, new List<CampaignMember>());
    }
    membersByLead.get(cm.LeadId).add(cm);
}
```

**優先度**: 高
```

## サマリー出力

最後に必ず以下のサマリーを出力してください：

```markdown
## ガバナ制限レビュー サマリー

- 検出された問題: X 件
  - 高優先度（ガバナ制限に直結）: X 件
  - 中優先度（性能改善）: X 件
  - 低優先度（ベストプラクティス）: X 件

### 推奨される対応順序
1. ループ内 SOQL/DML の解消（最優先）
2. LIMIT 句の追加
3. その他の最適化
```

## 注意事項

- **コードの正解を示すときは WITH SECURITY_ENFORCED を必ず含めてください**
- ガバナ制限の値は最新の Salesforce ドキュメントに準拠してください
- 改善案には「なぜそうすべきか」の説明を必ず含めてください
- 受講者の学習を促すため、答えを直接示しすぎないことも考慮（必要に応じてヒントだけにする）
