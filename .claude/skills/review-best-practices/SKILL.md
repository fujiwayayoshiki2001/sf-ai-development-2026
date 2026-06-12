---
name: review-best-practices
description: |
  Apex / LWC コードのその他のベストプラクティスをチェックするスキル。
  ハードコード、コメント、メソッドの長さ、責務分離、再帰トリガー対策など、
  他のレビュー観点（ガバナ制限・セキュリティ・バルク化・エラー処理・命名・テスト）に
  含まれない一般的なベストプラクティスを確認する。

  以下のような場面で使用：
  - 「コードの一般的なベストプラクティスでレビューして」
  - 「ハードコードがないか」
  - 「責務分離は適切か」
  - 「再帰トリガー対策があるか」
  - /review-best-practices コマンドが実行されたとき
  - /review コマンドの一部として呼ばれたとき
---

# ベストプラクティスレビュー

このスキルは、その他の一般的なベストプラクティスの観点でコードをレビューします。

## あなたの役割

ソフトウェア設計の専門家として、Salesforce 開発のベストプラクティスに沿っているかをレビューしてください。

## 必ずチェックする項目

### 1. ハードコーディング

#### プロファイル ID

```apex
// 検出パターン
if (UserInfo.getProfileId() == '00e3D000000xxxxx') { ... }
```

**問題点**: 環境ごとに ID が異なるので動かない。

**改善案**:

```apex
// プロファイル名で判定
Id sysAdminProfileId = [
    SELECT Id FROM Profile 
    WHERE Name = 'System Administrator' 
    LIMIT 1
].Id;

if (UserInfo.getProfileId() == sysAdminProfileId) { ... }

// またはカスタムメタデータで管理
```

#### URL / メールアドレス

```apex
// 検出パターン
String adminEmail = 'admin@example.com';
String webhookUrl = 'https://api.example.com/webhook';
```

**問題点**: 環境ごとに変える必要がある。

**改善案**: カスタム設定 / カスタムメタデータで管理。

```apex
String adminEmail = Custom_Config__mdt.getInstance('Default').Admin_Email__c;
```

#### レコード ID

```apex
// 検出パターン
String defaultOwnerId = '005d0000001abc';
```

**改善案**: メタデータか、コード内で動的に取得。

### 2. メソッドの長さ

```apex
// 検出パターン
public static void process(...) {
    // 200行以上のメソッド
    // 複数の責務が混在
}
```

**問題点**:
- 可読性が低い
- テストが困難
- バグが入りやすい

**改善案**: 責務ごとに分割。

```apex
public static void processLead(Lead lead) {
    validateLead(lead);
    calculateScore(lead);
    updateCategory(lead);
    notifyOwner(lead);
}

private static void validateLead(Lead lead) { ... }
private static void calculateScore(Lead lead) { ... }
// ...
```

### 3. 責務分離の欠如

```apex
// 検出パターン
public class LeadController {
    @AuraEnabled
    public static void process(Id leadId) {
        // SOQL
        Lead lead = [SELECT ... FROM Lead WHERE Id = :leadId];
        
        // スコア計算
        Decimal score = 0;
        if (lead.Industry == 'Technology') score += 15;
        // ... 大量のビジネスロジック
        
        // DML
        lead.Score__c = score;
        update lead;
        
        // メール送信
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        ...
    }
}
```

**問題点**:
- Controller がすべてをやっている
- テストが困難
- 再利用できない

**改善案**: 層を分ける。

```apex
// Controller: LWC との接続だけ
public class LeadController {
    @AuraEnabled
    public static void process(Id leadId) {
        LeadService.process(leadId);
    }
}

// Service: ビジネスロジック
public class LeadService {
    public static void process(Id leadId) {
        Lead lead = getLead(leadId);
        Decimal score = LeadScoringService.calculate(lead);
        // ...
    }
}

// Scorer: 計算ロジック
public class LeadScoringService {
    public static Decimal calculate(Lead lead) { ... }
}
```

### 4. 再帰トリガー対策の欠如

```apex
// 検出パターン
trigger LeadTrigger on Lead (after update) {
    for (Lead lead : Trigger.new) {
        lead.Score__c = calculate(lead);
    }
    update Trigger.new;  // ← 再帰呼び出し！
}
```

**問題点**: 無限ループのリスク。

**改善案**: フラグで防止。

```apex
public class LeadTriggerHandler {
    @TestVisible
    public static Boolean bypassTrigger = false;
    
    public static void afterUpdate(...) {
        if (bypassTrigger) return;
        
        bypassTrigger = true;
        try {
            // 更新処理
            update leadsToUpdate;
        } finally {
            bypassTrigger = false;
        }
    }
}
```

### 5. コメントの不足 / 過剰

```apex
// 検出パターン1: コメントなし
public static Decimal calculate(Lead lead) {
    Decimal result = 0;
    if (lead.NumberOfEmployees != null) {
        result += Math.log(lead.NumberOfEmployees) * 5;
    }
    return result;
}

// 検出パターン2: 過剰なコメント
public static Decimal calculate(Lead lead) {
    // 結果を 0 で初期化
    Decimal result = 0;
    // null チェック
    if (lead.NumberOfEmployees != null) {
        // 対数計算
        result += Math.log(lead.NumberOfEmployees) * 5;
    }
    // 結果を返す
    return result;
}
```

**改善案**: 「なぜ」をコメントに。

```apex
/**
 * 従業員数を対数スケールでスコア化する
 * (大企業は線形より緩やかにスコアを上げる)
 */
public static Decimal calculate(Lead lead) {
    Decimal result = 0;
    if (lead.NumberOfEmployees != null) {
        // 対数スケール: 100人=10点、1000人=15点、10000人=20点
        result += Math.log(lead.NumberOfEmployees) * 5;
    }
    return result;
}
```

### 6. with sharing / without sharing の明示

```apex
// 検出パターン
public class LeadService {  // ← 明示なし
    ...
}
```

**問題点**: 呼び出し元のシェアリングを継承（予測しにくい）。

**改善案**: 明示する。

```apex
public with sharing class LeadService { ... }
```

### 7. final / private の活用

```apex
// 検出パターン
public class LeadConstants {
    public static Integer HOT_THRESHOLD = 180;  // final なし、変更可能
}
```

**問題点**: 値が書き換えられる可能性。

**改善案**:

```apex
public class LeadConstants {
    public static final Integer HOT_THRESHOLD = 180;
}
```

メソッドも `private` を活用：

```apex
public class LeadService {
    // 外部から呼ばれるのは public
    public static void process(List<Lead> leads) {
        validateInput(leads);
        // ...
    }
    
    // 内部だけで使うのは private
    private static void validateInput(List<Lead> leads) { ... }
}
```

### 8. カスタムメタデータ / カスタム設定の活用

```apex
// 検出パターン
public static Decimal getWeight(String industry) {
    if (industry == 'Technology') return 15;
    if (industry == 'Manufacturing') return 15;
    if (industry == 'Financial Services') return 10;
    return 0;
}
```

**問題点**: 重みを変えたければコード修正が必要。

**改善案**: カスタムメタデータで管理。

```apex
public static Decimal getWeight(String industry) {
    List<Lead_Scoring_Config__mdt> configs = [
        SELECT Weight__c FROM Lead_Scoring_Config__mdt
        WHERE Score_Type__c = 'Attribute' 
        AND Key__c = :industry
        AND Is_Active__c = true
    ];
    return configs.isEmpty() ? 0 : configs[0].Weight__c;
}
```

### 9. デッドコード

```apex
// 検出パターン
public static void process(Lead lead) {
    // ...
    /*
    Boolean oldFlag = false;  // 使われていないコメントアウト
    if (oldFlag) { ... }
    */
    
    String unused = 'abc';  // 使われていない変数
}
```

**改善案**: 削除する。Git 履歴があるので、コメントアウトで残す必要はない。

## 出力フォーマット

```markdown
### [問題 N] ハードコーディング

**場所**: `force-app/main/default/classes/LeadService.cls` 行 25

**現在のコード**:
```apex
if (UserInfo.getProfileId() == '00e3D000000xxxxx') { ... }
```

**問題**:
プロファイル ID をハードコードしています。環境ごとに ID が変わります。

**改善案**:
```apex
Id sysAdminProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
if (UserInfo.getProfileId() == sysAdminProfileId) { ... }
```

**優先度**: 高
```

## サマリー出力

```markdown
## ベストプラクティス レビュー サマリー

- 検出された問題: X 件
  - 高優先度（バグの原因）: X 件
  - 中優先度（保守性）: X 件
  - 低優先度（コード品質）: X 件

### 推奨される対応順序
1. ハードコーディングの解消
2. 再帰トリガー対策の実装
3. 責務分離の実施
4. メソッドの分割
```

## 注意事項

- 「動くコード」と「良いコード」の違いを意識
- 設計の観点も含める
- 改善案には WITH SECURITY_ENFORCED を含める（SOQL の場合）
