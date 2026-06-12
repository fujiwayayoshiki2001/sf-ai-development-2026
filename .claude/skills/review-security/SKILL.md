---
name: review-security
description: |
  Apex / LWC コードのセキュリティ問題をチェックするスキル。
  Salesforce プラットフォームでよく見られるセキュリティ脆弱性を検出する。

  以下のような場面で使用：
  - 「セキュリティの観点でレビューして」
  - 「WITH SECURITY_ENFORCED が抜けていないか確認して」
  - 「SOQL インジェクションの可能性をチェックして」
  - 「CRUD/FLS チェックが適切か見て」
  - /review-security コマンドが実行されたとき
  - /review コマンドの一部として呼ばれたとき
---

# セキュリティレビュー

このスキルは、Apex / LWC コードのセキュリティ問題を検出します。

## あなたの役割

Salesforce セキュリティの専門家として、コードのセキュリティ脆弱性をレビューしてください。

## 必ずチェックする項目

### 1. WITH SECURITY_ENFORCED の欠如（最重要）

```apex
// 検出パターン
List<Lead> leads = [SELECT Id, Name FROM Lead WHERE ...];  // ← WITH SECURITY_ENFORCED なし
```

**問題点**: 
ユーザーがアクセス権限のない項目・オブジェクトの情報を取得してしまう可能性。
特に AuraEnabled メソッドからの呼び出しでは深刻。

**改善案**:

```apex
List<Lead> leads = [
    SELECT Id, Name 
    FROM Lead 
    WHERE ...
    WITH SECURITY_ENFORCED   // ← 追加
];
```

### 2. CRUD/FLS チェック漏れ

```apex
// 検出パターン
update lead;   // ← 権限チェックなしで DML
insert lead;
delete lead;
```

**問題点**: ユーザーが該当オブジェクトの編集権限を持たない場合でも書き込みできてしまう。

**改善案**:

```apex
if (Schema.sObjectType.Lead.isUpdateable()) {
    update lead;
} else {
    throw new AuraHandledException('リードの更新権限がありません');
}
```

または、Salesforce.UserPermissions と stripInaccessible を使う：

```apex
SObjectAccessDecision decision = Security.stripInaccessible(
    AccessType.UPDATABLE,
    leads
);
update decision.getRecords();
```

### 3. SOQL インジェクション

```apex
// 検出パターン
String query = 'SELECT Id FROM Lead WHERE Name LIKE \'%' + userInput + '%\'';
List<Lead> results = Database.query(query);  // ← 危険
```

**問題点**: ユーザー入力に SOQL のメタ文字（' など）が含まれていると、意図しないクエリが実行される。

**改善案**:

```apex
// 方法1: バインド変数を使う
String pattern = '%' + userInput + '%';
List<Lead> results = [
    SELECT Id FROM Lead 
    WHERE Name LIKE :pattern
    WITH SECURITY_ENFORCED
];

// 方法2: エスケープする
String escaped = String.escapeSingleQuotes(userInput);
String query = 'SELECT Id FROM Lead WHERE Name LIKE \'%' + escaped + '%\' WITH SECURITY_ENFORCED';
```

### 4. シェアリング設定の問題

```apex
// 検出パターン
public class LeadController {  // ← with/without sharing 指定なし
    ...
}

public without sharing class LeadController {  // ← 不必要な without sharing
    ...
}
```

**問題点**:
- 宣言なしだと、呼び出し元のシェアリング設定を継承（予測しにくい）
- 不必要な without sharing は、レコードレベルの権限を無視

**改善案**:

```apex
// 基本は with sharing
public with sharing class LeadController {
    ...
}

// 明示的な理由がある場合のみ without sharing
public without sharing class SystemLevelService {
    // バッチ処理など、システム権限が必要な処理
}
```

### 5. AuraEnabled メソッドの権限

```apex
// 検出パターン
@AuraEnabled
public static void deleteAllLeads() {  // ← 権限チェックなし
    delete [SELECT Id FROM Lead];
}
```

**問題点**: LWC から呼ばれる @AuraEnabled メソッドは、ユーザーセキュリティのみで動作する想定だが、`without sharing` で書かれていると危険。

**改善案**:

```apex
@AuraEnabled
public static void deleteLead(Id leadId) {
    if (!Schema.sObjectType.Lead.isDeletable()) {
        throw new AuraHandledException('削除権限がありません');
    }
    
    Lead toDelete = [SELECT Id FROM Lead WHERE Id = :leadId WITH SECURITY_ENFORCED];
    delete toDelete;
}
```

### 6. ハードコードされた認証情報

```apex
// 検出パターン
String apiKey = 'sk-1234567890abcdef';  // ← ハードコード
HttpRequest req = new HttpRequest();
req.setHeader('Authorization', 'Bearer abc123xyz');
```

**問題点**: コードに認証情報が露出。Git に流出する危険。

**改善案**:
- Named Credentials を使う
- Custom Settings / Custom Metadata で管理（暗号化テキスト項目を使う）

### 7. LWC でのエスケープ

```javascript
// 検出パターン
this.template.querySelector('.container').innerHTML = userInput;  // ← XSS リスク
```

**問題点**: ユーザー入力をそのまま innerHTML に設定すると XSS の可能性。

**改善案**:
- `innerText` を使う
- テンプレート構文で安全にバインド

## 出力フォーマット

```markdown
### [問題 N] WITH SECURITY_ENFORCED の欠如

**場所**: `force-app/main/default/classes/LeadController.cls` 行 25-30

**現在のコード**:
```apex
List<Lead> leads = [SELECT Id, Name FROM Lead];
```

**問題**: 
項目レベルセキュリティが適用されません。

**改善案**:
```apex
List<Lead> leads = [SELECT Id, Name FROM Lead WITH SECURITY_ENFORCED];
```

**優先度**: 高
```

## サマリー出力

```markdown
## セキュリティレビュー サマリー

- 検出された問題: X 件
  - 高優先度（脆弱性）: X 件
  - 中優先度（保守性）: X 件
  - 低優先度（推奨事項）: X 件

### 推奨される対応順序
1. SOQL インジェクション対策（最優先）
2. WITH SECURITY_ENFORCED の追加
3. CRUD/FLS チェックの実装
4. その他
```

## 注意事項

- 改善案には WITH SECURITY_ENFORCED を必ず含める
- セキュリティ問題は優先度を「高」に設定（ユーザーデータに関わる）
- 受講者の学習を促すため、なぜ危険なのかを丁寧に説明する
