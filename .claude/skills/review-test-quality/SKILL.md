---
name: review-test-quality
description: |
  Apex テストクラスの品質をチェックするスキル。
  カバレッジ、テストパターン、アサーション、@TestSetup の使い方などをレビューする。

  以下のような場面で使用：
  - 「テストクラスの品質をレビューして」
  - 「テストカバレッジが十分か確認して」
  - 「@TestSetup が使われているか」
  - 「バルクテストがあるか」
  - /review-test-quality コマンドが実行されたとき
  - /review コマンドの一部として呼ばれたとき（テストクラスの場合）
---

# テスト品質レビュー

このスキルは、Apex テストクラスの品質をレビューします。

## あなたの役割

テスト駆動開発の専門家として、テストクラスの品質をレビューしてください。

## 必ずチェックする項目

### 1. SeeAllData=true の使用（重大）

```apex
// 検出パターン
@isTest(SeeAllData=true)
private class LeadServiceTest {
    static testMethod void testGetLeads() {
        ...
    }
}
```

**問題点**:
- 本番組織のデータに依存（環境ごとに結果が変わる）
- テストの独立性が失われる
- パッケージ化できない

**改善案**: テストデータを自分で作成。

```apex
@isTest
private class LeadServiceTest {
    
    @TestSetup
    static void setup() {
        List<Lead> leads = TestDataFactory.createLeads(10);
        insert leads;
    }
    
    @isTest
    static void testGetLeads() {
        Test.startTest();
        List<Lead> result = LeadService.getLeadsByCategory('Hot', 10);
        Test.stopTest();
        
        System.assertEquals(...);
    }
}
```

### 2. @TestSetup の不使用

```apex
// 検出パターン
@isTest
private class LeadServiceTest {
    
    @isTest
    static void test1() {
        // ここで insert lead
        Lead lead1 = new Lead(LastName='Test1', Company='Test');
        insert lead1;
        // テスト
    }
    
    @isTest
    static void test2() {
        // ここでも insert lead（重複）
        Lead lead2 = new Lead(LastName='Test2', Company='Test');
        insert lead2;
        // テスト
    }
}
```

**問題点**: テストごとにデータを作り直すのは非効率。

**改善案**: @TestSetup で共通データ準備。

```apex
@isTest
private class LeadServiceTest {
    
    @TestSetup
    static void setup() {
        List<Lead> leads = TestDataFactory.createLeads(10);
        insert leads;
    }
    
    @isTest
    static void test1() {
        // 既にデータがある状態でテスト
    }
    
    @isTest
    static void test2() {
        // 同じく
    }
}
```

### 3. アサーションの不足

```apex
// 検出パターン
@isTest
static void testSomething() {
    Lead lead = new Lead(LastName='Test', Company='Test');
    insert lead;
    
    LeadService.process(lead.Id);
    
    // アサーションなし → 「動いた」だけで何も検証していない
}
```

**問題点**: テストが「実行されただけ」で意味がない。

**改善案**: 必ずアサーションを書く。

```apex
@isTest
static void testProcessLead() {
    Lead lead = new Lead(LastName='Test', Company='Test', Industry='Technology');
    insert lead;
    
    Test.startTest();
    LeadService.process(lead.Id);
    Test.stopTest();
    
    Lead updated = [SELECT Score__c, Lead_Category__c FROM Lead WHERE Id = :lead.Id];
    System.assertEquals(15, updated.Score__c, 
        'Technology industry score should be 15');
    System.assertNotEquals(null, updated.Lead_Category__c, 
        'Lead category should be set');
}
```

### 4. バルクテストの欠如

```apex
// 検出パターン
@isTest
private class LeadServiceTest {
    
    @isTest
    static void testProcessSingleLead() {
        Lead lead = new Lead(...);
        insert lead;
        LeadService.process(new Set<Id>{lead.Id});
        // 1件のテストだけ
    }
}
```

**問題点**: 200件処理した時の動作が確認されていない。
ガバナ制限超過のバグを見逃す。

**改善案**: 必ずバルクテストを含める。

```apex
@isTest
static void testProcessBulk() {
    List<Lead> bulkLeads = TestDataFactory.createLeads(200);
    insert bulkLeads;
    
    Set<Id> leadIds = new Map<Id, Lead>(bulkLeads).keySet();
    
    Test.startTest();
    LeadService.process(leadIds);
    Test.stopTest();
    
    List<Lead> updated = [SELECT Id, Score__c FROM Lead WHERE Id IN :leadIds];
    System.assertEquals(200, updated.size(), 'All 200 leads should be processed');
}
```

### 5. ネガティブケースの欠如

```apex
// 検出パターン
@isTest
private class LeadValidatorTest {
    
    @isTest
    static void testValidLead() {
        // 正常系のみ
    }
    // ネガティブケースなし
}
```

**問題点**: エラーパスがテストされていない。

**改善案**: 例外発生時のテストも書く。

```apex
@isTest
static void testInvalidEmail() {
    Lead lead = new Lead(LastName='Test', Company='Test', Email='invalid-email');
    
    Boolean exceptionThrown = false;
    try {
        Test.startTest();
        insert lead;
        Test.stopTest();
    } catch (DmlException e) {
        exceptionThrown = true;
        System.assert(e.getMessage().contains('メールアドレス'), 
            'Email validation error should be raised');
    }
    
    System.assert(exceptionThrown, 'DmlException should be thrown for invalid email');
}
```

### 6. Test.startTest() / Test.stopTest() の不使用

```apex
// 検出パターン
@isTest
static void testProcess() {
    Lead lead = new Lead(...);
    insert lead;
    LeadService.process(lead.Id);  // ← startTest/stopTest なし
    
    System.assertEquals(...);
}
```

**問題点**:
- ガバナ制限のリセットがない
- 非同期処理（@future、Queueable）のテストができない

**改善案**:

```apex
@isTest
static void testProcess() {
    Lead lead = new Lead(...);
    insert lead;  // setup（制限カウント対象）
    
    Test.startTest();  // ← ここでカウンタリセット
    LeadService.process(lead.Id);  // 本番想定の処理
    Test.stopTest();   // ← 非同期処理もここで完了
    
    System.assertEquals(...);
}
```

### 7. System.runAs() の使い方

```apex
// 検出パターン
@isTest
static void testUserAccess() {
    // 管理者として実行されるので権限テストにならない
    LeadController.getLeadList(...);
}
```

**問題点**: 異なる権限のユーザーでのテストができない。

**改善案**:

```apex
@isTest
static void testUserAccess() {
    User testUser = TestDataFactory.createUser('Standard User');
    insert testUser;
    
    System.runAs(testUser) {
        Test.startTest();
        List<Lead> result = LeadController.getLeadList('Hot', 10);
        Test.stopTest();
        
        System.assertEquals(...);
    }
}
```

### 8. アサーションメッセージの欠如

```apex
// 検出パターン
System.assertEquals(15, score);
System.assertNotEquals(null, lead.Score__c);
```

**問題点**: 失敗時に何が間違っているか分かりにくい。

**改善案**: 第3引数でメッセージを付ける。

```apex
System.assertEquals(15, score, 'Technology industry should add 15 points');
System.assertNotEquals(null, lead.Score__c, 'Score should be calculated after trigger');
```

### 9. カバレッジ目標

```
[目標]
- 全体: 75% 以上（デプロイ要件）
- 推奨: 90% 以上
- 各クラス: 75% 以上
```

カバレッジが低そうなクラスを指摘する。
（テストクラスから対応する本番クラスの何をテストしているかを推測）

## 出力フォーマット

```markdown
### [問題 N] アサーションの不足

**場所**: `force-app/main/default/classes/LeadServiceTest.cls` 行 25-30

**現在のコード**:
```apex
@isTest
static void testProcessLead() {
    LeadService.process(lead.Id);
    // アサーションなし
}
```

**問題**:
処理結果を検証するアサーションがありません。

**改善案**:
```apex
@isTest
static void testProcessLead() {
    Test.startTest();
    LeadService.process(lead.Id);
    Test.stopTest();
    
    Lead updated = [SELECT Score__c FROM Lead WHERE Id = :lead.Id];
    System.assertNotEquals(0, updated.Score__c, 'Score should be calculated');
}
```

**優先度**: 高
```

## サマリー出力

```markdown
## テスト品質レビュー サマリー

- 検出された問題: X 件
  - 高優先度（テストの信頼性に影響）: X 件
  - 中優先度（カバレッジ・効率）: X 件
  - 低優先度（保守性）: X 件

### 推奨される対応順序
1. SeeAllData=true の除去
2. アサーションの追加
3. バルクテストの追加
4. @TestSetup の活用
5. ネガティブケースの追加
```

## 注意事項

- テストはコードと同じくらい重要
- カバレッジを稼ぐためだけのテストはNG（アサーションが本質）
- バルクテスト（200件）は必須
- @TestSetup で効率化
