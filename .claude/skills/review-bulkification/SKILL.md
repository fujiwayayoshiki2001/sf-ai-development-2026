---
name: review-bulkification
description: |
  Apex コードのバルク処理対応をチェックするスキル。
  単一レコード前提のコードや、複数レコード処理時に非効率な実装を検出する。

  以下のような場面で使用：
  - 「バルク処理の観点でレビューして」
  - 「複数件処理に対応しているか確認」
  - 「Set/List/Map の使い方が適切か」
  - /review-bulkification コマンドが実行されたとき
  - /review コマンドの一部として呼ばれたとき
---

# バルク化レビュー

このスキルは、Apex コードがバルク処理（複数レコード処理）に対応しているかをレビューします。

## あなたの役割

Salesforce のバルク処理パターンの専門家として、コードがバルク処理に対応しているかをレビューしてください。

## 必ずチェックする項目

### 1. 単一レコード前提のメソッドシグネチャ

```apex
// 検出パターン
public static void updateScore(Lead lead) {  // ← 単一の Lead のみ
    ...
}

public static Lead getLead(Id leadId) {  // ← 単一の Id のみ
    return [SELECT ... FROM Lead WHERE Id = :leadId];
}
```

**問題点**: 200件のトリガーから呼ばれると、200回メソッドが呼ばれる。

**改善案**: バルク対応のシグネチャに変える。

```apex
// 改善後
public static void updateScores(List<Lead> leads) {
    ...
}

public static Map<Id, Lead> getLeads(Set<Id> leadIds) {
    return new Map<Id, Lead>([
        SELECT Id, ... 
        FROM Lead 
        WHERE Id IN :leadIds
        WITH SECURITY_ENFORCED
    ]);
}

// 単一版が必要なら、バルク版を呼ぶ形で
public static Lead getLead(Id leadId) {
    return getLeads(new Set<Id>{leadId}).get(leadId);
}
```

### 2. Trigger 内の単一処理

```apex
// 検出パターン
trigger LeadTrigger on Lead (after insert) {
    for (Lead lead : Trigger.new) {
        LeadService.processSingle(lead);  // ← 1件ずつ処理
    }
}
```

**問題点**: 200件のリードが同時に作成されるとガバナ制限超過のリスク。

**改善案**: バルク対応のメソッドを 1 回呼ぶ。

```apex
// 改善後
trigger LeadTrigger on Lead (after insert) {
    LeadService.processLeads(Trigger.new);
}
```

### 3. ループ内の集約処理

```apex
// 検出パターン
for (Lead lead : leads) {
    Decimal score = 0;
    List<CampaignMember> members = [...];  // ループ内 SOQL
    for (CampaignMember cm : members) {
        score += getWeight(cm);
    }
    lead.Score__c = score;
}
```

**問題点**: ループ外で取得して Map で関連付けるべき。

**改善案**:

```apex
// Step 1: リードIDを収集
Set<Id> leadIds = new Map<Id, Lead>(leads).keySet();

// Step 2: 関連データを一度に取得
List<CampaignMember> allMembers = [
    SELECT Id, LeadId, ...
    FROM CampaignMember
    WHERE LeadId IN :leadIds
    WITH SECURITY_ENFORCED
];

// Step 3: Map に整理
Map<Id, List<CampaignMember>> membersByLead = new Map<Id, List<CampaignMember>>();
for (CampaignMember cm : allMembers) {
    if (!membersByLead.containsKey(cm.LeadId)) {
        membersByLead.put(cm.LeadId, new List<CampaignMember>());
    }
    membersByLead.get(cm.LeadId).add(cm);
}

// Step 4: ループ処理
for (Lead lead : leads) {
    Decimal score = 0;
    List<CampaignMember> members = membersByLead.get(lead.Id);
    if (members != null) {
        for (CampaignMember cm : members) {
            score += getWeight(cm);
        }
    }
    lead.Score__c = score;
}
```

### 4. 個別 update の積み重ね

```apex
// 検出パターン
public static void processLeads(List<Lead> leads) {
    for (Lead lead : leads) {
        lead.Score__c = calculate(lead);
        update lead;  // ← 1件ずつ
    }
}
```

**問題点**: ガバナ制限超過 + 性能問題。

**改善案**:

```apex
// 改善後
public static void processLeads(List<Lead> leads) {
    for (Lead lead : leads) {
        lead.Score__c = calculate(lead);
    }
    update leads;  // ← 一度にバルク update
}
```

### 5. Set / List / Map の活用不足

```apex
// 検出パターン
for (Lead lead : leads) {
    for (Account acc : accounts) {  // ネストループ
        if (lead.AccountId == acc.Id) {
            lead.Industry = acc.Industry;
        }
    }
}
```

**問題点**: O(N×M) の計算量。

**改善案**: Map で O(N+M) に。

```apex
// 改善後
Map<Id, Account> accountMap = new Map<Id, Account>(accounts);
for (Lead lead : leads) {
    Account acc = accountMap.get(lead.AccountId);
    if (acc != null) {
        lead.Industry = acc.Industry;
    }
}
```

### 6. 不要な SOQL の繰り返し

```apex
// 検出パターン
public static void processLeads(List<Lead> leads) {
    for (Lead lead : leads) {
        User owner = [SELECT Id, Name FROM User WHERE Id = :lead.OwnerId];  // 毎回 SOQL
        ...
    }
}
```

**問題点**: ループ内 SOQL かつ重複クエリ。

**改善案**:

```apex
// オーナーIDを収集
Set<Id> ownerIds = new Set<Id>();
for (Lead lead : leads) {
    if (lead.OwnerId != null) ownerIds.add(lead.OwnerId);
}

// 一度に取得
Map<Id, User> ownerMap = new Map<Id, User>([
    SELECT Id, Name FROM User 
    WHERE Id IN :ownerIds
    WITH SECURITY_ENFORCED
]);

// ループで参照
for (Lead lead : leads) {
    User owner = ownerMap.get(lead.OwnerId);
    ...
}
```

## 出力フォーマット

```markdown
### [問題 N] 単一レコード前提のメソッド

**場所**: `force-app/main/default/classes/LeadService.cls` 行 15-25

**現在のコード**:
```apex
public static void updateScore(Lead lead) {
    ...
}
```

**問題**:
バルク処理に対応していません。

**改善案**:
```apex
public static void updateScores(List<Lead> leads) {
    ...
}
```

**優先度**: 高
```

## サマリー出力

```markdown
## バルク化レビュー サマリー

- 検出された問題: X 件
  - 高優先度（ガバナ制限直結）: X 件
  - 中優先度（性能改善）: X 件
  - 低優先度（コード品質）: X 件

### 推奨される対応順序
1. ループ内 SOQL/DML の解消
2. メソッドシグネチャのバルク化
3. Map による効率化
```

## 注意事項

- バルク版メソッドを基本とし、単一版は内部で呼ぶだけにする
- Set / List / Map の使い分けを意識
- 改善案には WITH SECURITY_ENFORCED を含める
