---
name: review-error-handling
description: |
  Apex / LWC コードのエラーハンドリングをチェックするスキル。
  try-catch の使い方、例外処理、エラーメッセージ、ログ出力などをレビューする。

  以下のような場面で使用：
  - 「エラー処理の観点でレビューして」
  - 「try-catch が適切か確認して」
  - 「例外処理が漏れていないか」
  - /review-error-handling コマンドが実行されたとき
  - /review コマンドの一部として呼ばれたとき
---

# エラーハンドリングレビュー

このスキルは、Apex / LWC コードのエラーハンドリングをレビューします。

## あなたの役割

堅牢なシステム設計の専門家として、エラーハンドリングの観点でコードをレビューしてください。

## 必ずチェックする項目

### 1. try-catch の欠如

```apex
// 検出パターン
@AuraEnabled
public static void recalculateScore(Id leadId) {
    LeadScoringService.calculate(leadId);
    update [SELECT Id FROM Lead WHERE Id = :leadId];
}
```

**問題点**:
- DML が失敗したら例外がそのまま LWC まで伝搬する
- ユーザーに分かりにくいエラーが表示される
- ログが残らない

**改善案**:

```apex
@AuraEnabled
public static void recalculateScore(Id leadId) {
    try {
        LeadScoringService.calculate(leadId);
        update [SELECT Id FROM Lead WHERE Id = :leadId WITH SECURITY_ENFORCED];
    } catch (DmlException e) {
        System.debug(LoggingLevel.ERROR, 'DML エラー: ' + e.getMessage());
        throw new AuraHandledException('リードの更新に失敗しました: ' + e.getMessage());
    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, 
            '予期しないエラー: ' + e.getMessage() + '\n' + e.getStackTraceString());
        throw new AuraHandledException('スコア計算中にエラーが発生しました');
    }
}
```

### 2. 空 catch（例外の握りつぶし）

```apex
// 検出パターン
try {
    update lead;
} catch (Exception e) {
    // 何もしない  ← 危険
}
```

**問題点**: エラーが発生しても気付けない。

**改善案**:
最低限、ログは残す。

```apex
try {
    update lead;
} catch (DmlException e) {
    System.debug(LoggingLevel.ERROR, 
        'リード更新失敗 ID=' + lead.Id + ', メッセージ=' + e.getMessage());
    throw e;  // または適切に処理
}
```

### 3. 一般的すぎる例外キャッチ

```apex
// 検出パターン
try {
    // 複数の処理
} catch (Exception e) {  // ← 何でもキャッチ
    handleError(e);
}
```

**問題点**:
- DmlException、QueryException など、種類別の対応ができない
- バグを隠す可能性

**改善案**: 具体的な例外を個別にキャッチ。

```apex
try {
    Lead lead = [SELECT ... FROM Lead WHERE ... WITH SECURITY_ENFORCED];
    lead.Score__c = calculate(lead);
    update lead;
} catch (QueryException e) {
    System.debug(LoggingLevel.ERROR, 'クエリエラー: ' + e.getMessage());
    throw new AuraHandledException('リードが見つかりません');
} catch (DmlException e) {
    System.debug(LoggingLevel.ERROR, 'DML エラー: ' + e.getMessage());
    throw new AuraHandledException('保存に失敗しました');
} catch (Exception e) {
    // 想定外の例外は最後の砦
    System.debug(LoggingLevel.ERROR, 
        '想定外: ' + e.getTypeName() + ' / ' + e.getMessage());
    throw new AuraHandledException('予期しないエラーが発生しました');
}
```

### 4. Savepoint / Rollback の欠如

```apex
// 検出パターン
public static void complexOperation() {
    insert lead;
    insert account;
    insert contact;  // ← ここで失敗するとデータ不整合
}
```

**問題点**: 途中で失敗するとデータが半端な状態に。

**改善案**: Savepoint で全ロールバック可能に。

```apex
public static void complexOperation() {
    Savepoint sp = Database.setSavepoint();
    try {
        insert lead;
        insert account;
        insert contact;
    } catch (Exception e) {
        Database.rollback(sp);
        System.debug(LoggingLevel.ERROR, 'ロールバック: ' + e.getMessage());
        throw e;
    }
}
```

### 5. AuraHandledException の不適切な使用

```apex
// 検出パターン
@AuraEnabled
public static void doSomething() {
    try {
        // 処理
    } catch (Exception e) {
        throw e;  // ← 生の例外を LWC に投げている
    }
}
```

**問題点**: LWC では具体的なエラーメッセージが表示されない（"Internal Server Error" になる）。

**改善案**:

```apex
@AuraEnabled
public static void doSomething() {
    try {
        // 処理
    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, 'エラー詳細: ' + e.getMessage());
        throw new AuraHandledException('処理に失敗しました: ' + e.getMessage());
    }
}
```

### 6. null チェックの欠如

```apex
// 検出パターン
public static Decimal calculate(Lead lead) {
    return lead.NumberOfEmployees * 0.1;  // ← null で NullPointerException
}
```

**問題点**: 必須項目でない場合、null で NPE。

**改善案**:

```apex
public static Decimal calculate(Lead lead) {
    if (lead == null || lead.NumberOfEmployees == null) {
        return 0;
    }
    return lead.NumberOfEmployees * 0.1;
}
```

### 7. addError() の活用

```apex
// 検出パターン
public static void validate(List<Lead> leads) {
    for (Lead lead : leads) {
        if (String.isBlank(lead.Email)) {
            throw new CustomException('メールアドレスが空です');  // ← トリガーで全失敗
        }
    }
}
```

**問題点**: 1件の問題で全レコードが失敗。

**改善案**: addError() で該当レコードのみ失敗扱い。

```apex
public static void validate(List<Lead> leads) {
    for (Lead lead : leads) {
        if (String.isBlank(lead.Email)) {
            lead.Email.addError('メールアドレスは必須です');
        }
    }
}
```

### 8. LWC でのエラーハンドリング

```javascript
// 検出パターン
import getLeadList from '@salesforce/apex/LeadController.getLeadList';

handleClick() {
    getLeadList()
        .then(result => {
            this.leads = result;
        });
    // catch がない
}
```

**問題点**: エラー時にユーザーに何も表示されない。

**改善案**:

```javascript
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

handleClick() {
    getLeadList()
        .then(result => {
            this.leads = result;
        })
        .catch(error => {
            console.error('Lead 取得エラー:', error);
            this.dispatchEvent(new ShowToastEvent({
                title: 'エラー',
                message: error.body?.message || 'リードの取得に失敗しました',
                variant: 'error'
            }));
        });
}
```

## 出力フォーマット

```markdown
### [問題 N] try-catch の欠如

**場所**: `force-app/main/default/classes/LeadController.cls` 行 15-20

**現在のコード**:
```apex
@AuraEnabled
public static void doSomething() {
    update lead;
}
```

**問題**:
例外がそのまま LWC に伝搬します。

**改善案**:
```apex
@AuraEnabled
public static void doSomething() {
    try {
        update lead;
    } catch (DmlException e) {
        throw new AuraHandledException('更新に失敗: ' + e.getMessage());
    }
}
```

**優先度**: 中
```

## サマリー出力

```markdown
## エラーハンドリング レビュー サマリー

- 検出された問題: X 件
  - 高優先度（バグの原因）: X 件
  - 中優先度（ユーザビリティ）: X 件
  - 低優先度（保守性）: X 件

### 推奨される対応順序
1. 空 catch / 一般的すぎる catch の解消
2. AuraHandledException でラップ
3. null チェックの追加
4. ログ出力の充実
```

## 注意事項

- 例外を握りつぶさない
- ログには情報を残す
- ユーザーには分かりやすいエラーメッセージ
- LWC との連携を意識
