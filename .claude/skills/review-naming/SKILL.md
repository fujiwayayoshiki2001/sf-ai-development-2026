---
name: review-naming
description: |
  Apex / LWC コードの命名規則をチェックするスキル。
  クラス名、メソッド名、変数名、定数の命名が適切かをレビューする。

  以下のような場面で使用：
  - 「命名規則の観点でレビューして」
  - 「変数名が分かりにくい箇所を見つけて」
  - 「命名の一貫性をチェックして」
  - /review-naming コマンドが実行されたとき
  - /review コマンドの一部として呼ばれたとき
---

# 命名レビュー

このスキルは、命名規則の観点でコードをレビューします。

## あなたの役割

可読性の高いコードを書く専門家として、命名規則の観点でレビューしてください。

## 必ずチェックする項目

### 1. クラス名

#### 命名規則
- PascalCase（大文字始まり）
- 名詞または名詞句
- 役割が明確（〜Service、〜Controller、〜Handler、〜Validator など）

```apex
// 良い例
public class LeadScoringService { ... }
public class LeadController { ... }
public class LeadValidator { ... }

// 悪い例
public class lead_service { ... }       // snake_case
public class leadController { ... }     // camelCase
public class Process { ... }            // 役割が不明
public class Helper { ... }             // 抽象的すぎる
public class Utils { ... }              // 抽象的すぎる
```

### 2. メソッド名

#### 命名規則
- camelCase（小文字始まり）
- 動詞で始める
- 何をするかが明確

```apex
// 良い例
public void calculateScore() { ... }
public Lead getLead(Id leadId) { ... }
public Boolean isValid() { ... }
public void updateLeads(List<Lead> leads) { ... }

// 悪い例
public void Calculate() { ... }         // PascalCase
public void lead_update() { ... }       // snake_case
public void process() { ... }           // 何をするか不明
public void doIt() { ... }              // 抽象的すぎる
public void leadStuff() { ... }         // 動詞でない、不明確
```

#### よく使う動詞のパターン
- `get〜`: 取得
- `set〜`: 設定
- `is〜` / `has〜`: 真偽判定
- `update〜`: 更新
- `create〜`: 作成
- `delete〜` / `remove〜`: 削除
- `validate〜`: 検証
- `calculate〜`: 計算
- `process〜`: 処理（できれば具体的に）

### 3. 変数名

#### 命名規則
- camelCase
- 意味のある名前
- 1文字変数（ループカウンタの i, j, k 以外）は避ける
- 略語を避ける（一般的なものを除く）

```apex
// 良い例
List<Lead> highScoreLeads = ...;
Integer maxAttemptCount = 3;
Boolean isLeadActive = true;
Map<Id, User> usersByOwnerId = new Map<Id, User>();

// 悪い例
List<Lead> a = ...;                     // 何を表すか不明
List<Lead> ls = ...;                    // 略語が分かりにくい
Integer cnt = ...;                      // 略語
Boolean flag = ...;                     // 何のフラグか不明
List<Lead> myList = ...;                // 「my」は意味がない
Map<Id, User> mp = ...;                 // 略語
```

#### コレクションの命名
複数形にする：

```apex
// 良い例
List<Lead> leads = ...;
Set<Id> leadIds = ...;
Map<Id, Lead> leadsById = ...;
Map<String, List<Lead>> leadsByCompany = ...;

// 悪い例
List<Lead> lead = ...;                  // 単数形
List<Lead> leadList = ...;              // 「List」が冗長
List<Lead> listOfLeads = ...;           // 冗長
```

### 4. 定数

#### 命名規則
- ALL_CAPS_SNAKE_CASE
- 意味のある名前
- 専用の定数クラスに集約

```apex
// 良い例
public class LeadConstants {
    public static final Integer HOT_THRESHOLD = 180;
    public static final Integer WARM_THRESHOLD = 100;
    public static final String CATEGORY_HOT = 'Hot';
    public static final Decimal DECAY_FACTOR = 0.95;
}

// 悪い例
public static final Integer hotThreshold = 180;  // camelCase
public static final Integer THRESHOLD = 180;     // 何の閾値か不明
public static final Integer X = 180;             // 意味不明
```

### 5. マジックナンバー / マジック文字列

```apex
// 検出パターン
if (lead.Score__c >= 180) { ... }                // マジックナンバー
if (lead.LeadSource == 'Webinar') { ... }       // マジック文字列
```

**問題点**: 意味が伝わらない、変更が大変。

**改善案**: 定数化

```apex
if (lead.Score__c >= LeadConstants.HOT_THRESHOLD) { ... }
if (lead.LeadSource == LeadConstants.SOURCE_WEBINAR) { ... }
```

### 6. プレフィックス・サフィックスの一貫性

```apex
// 検出パターン
public class LeadService { ... }
public class LeadCtrl { ... }              // Controller を Ctrl に略
public class LeadValidationHelper { ... }  // Helper という曖昧な接尾辞
```

**問題点**: 命名規則がバラバラ。

**改善案**: 一貫した接尾辞を使う

```apex
// 統一された命名
public class LeadService { ... }
public class LeadController { ... }
public class LeadValidator { ... }
public class LeadScorer { ... }
```

### 7. メソッド名と動作の不一致

```apex
// 検出パターン
public Boolean checkLead(Lead lead) {
    update lead;       // ← check と言いながら update している
    return true;
}

public Lead getLead(Id leadId) {
    Lead lead = [SELECT ... FROM Lead WHERE Id = :leadId];
    lead.Score__c = 100;
    update lead;       // ← get と言いながら update もしている
    return lead;
}
```

**問題点**: メソッド名と動作が一致しない。副作用がある。

**改善案**: 名前と動作を一致させる、副作用を明確にする。

```apex
// get は読み取りのみ
public Lead getLead(Id leadId) {
    return [SELECT ... FROM Lead WHERE Id = :leadId WITH SECURITY_ENFORCED];
}

// update は明示的に
public void updateLeadScore(Id leadId, Decimal score) {
    Lead lead = getLead(leadId);
    lead.Score__c = score;
    update lead;
}
```

### 8. LWC コンポーネント名

#### 命名規則
- ディレクトリ名・ファイル名: camelCase
- HTML 内では kebab-case で参照

```javascript
// 良い例
lwc/leadList/leadList.js
lwc/leadScoreCard/leadScoreCard.js

<c-lead-list></c-lead-list>
<c-lead-score-card></c-lead-score-card>

// 悪い例
lwc/LeadList/  ← PascalCase
lwc/lead_list/ ← snake_case
<c-leadList>   ← camelCase で参照
```

## 出力フォーマット

```markdown
### [問題 N] 意味のない変数名

**場所**: `force-app/main/default/classes/LeadService.cls` 行 25

**現在のコード**:
```apex
List<Lead> a = [SELECT Id FROM Lead WHERE Score__c > 100];
```

**問題**:
変数名「a」が何を表すか不明です。

**改善案**:
```apex
List<Lead> highScoreLeads = [SELECT Id FROM Lead WHERE Score__c > 100 WITH SECURITY_ENFORCED];
```

**優先度**: 中
```

## サマリー出力

```markdown
## 命名レビュー サマリー

- 検出された問題: X 件
  - 高優先度（誤解を招く）: X 件
  - 中優先度（可読性）: X 件
  - 低優先度（一貫性）: X 件

### 推奨される対応順序
1. メソッド名と動作の不一致を解消
2. 意味不明な変数名のリネーム
3. マジックナンバー / マジック文字列の定数化
4. プレフィックス・サフィックスの統一
```

## 注意事項

- 命名は「読む人のため」のもの
- 短さよりも明確さを優先
- プロジェクト全体で一貫性を持たせる
- 改善案には WITH SECURITY_ENFORCED を含める（SOQL の場合）
