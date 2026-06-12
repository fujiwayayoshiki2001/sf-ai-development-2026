---
description: |
  指定された Apex クラスに対するテストクラスを生成するコマンド。
  Salesforce のベストプラクティスに従い、@TestSetup、バルクテスト、
  ポジティブ/ネガティブケースを含む高品質なテストを生成する。

argument-hint: <apex-class-path>
---

# テストクラス生成

このコマンドは、指定された Apex クラスに対する高品質なテストクラスを生成します。

## 引数

`$ARGUMENTS` にはテスト対象の Apex クラスのファイルパスが入ります。

例:
- `/test force-app/main/default/classes/LeadController.cls`
- `/test LeadScoringService.cls`

## 実行手順

### Step 1: 対象クラスの分析

1. `$ARGUMENTS` で指定されたクラスを読み込む
2. クラスの構造を理解：
   - public/private メソッド一覧
   - 引数とリターン型
   - @AuraEnabled の有無
   - 静的/インスタンスメソッド
   - 依存する他のクラス・オブジェクト
3. プロジェクトの CLAUDE.md を参照してテスト方針を確認

### Step 2: テストデータの設計

#### TestDataFactory の確認

```apex
// .claude/skills/review-test-quality/SKILL.md に従って
// TestDataFactory が存在するか確認
```

存在する場合：
- TestDataFactory のメソッドを使う
- 必要なら TestDataFactory にメソッドを追加提案

存在しない場合：
- TestDataFactory も同時に生成する

### Step 3: テストクラスの構造

以下の構造でテストクラスを生成してください。

```apex
/**
 * <対象クラス名>のテストクラス
 * 
 * カバレッジ目標: 90% 以上
 * 含めるテストパターン:
 * - ポジティブケース
 * - ネガティブケース
 * - バルクテスト（200件）
 * - 境界値テスト
 */
@isTest
private class <対象クラス名>Test {
    
    @TestSetup
    static void setup() {
        // 共通テストデータの準備
        List<Lead> leads = TestDataFactory.createLeads(10);
        insert leads;
    }
    
    // === ポジティブケース ===
    
    @isTest
    static void test<メソッド名>_PositiveCase() {
        // Arrange
        Lead testLead = [SELECT Id FROM Lead LIMIT 1];
        
        // Act
        Test.startTest();
        <メソッド呼び出し>
        Test.stopTest();
        
        // Assert
        <検証>
    }
    
    // === ネガティブケース ===
    
    @isTest
    static void test<メソッド名>_InvalidInput() {
        // 不正な入力でのテスト
        Boolean exceptionThrown = false;
        try {
            <メソッド呼び出し with 不正な入力>
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        System.assert(exceptionThrown, '例外が発生するはず');
    }
    
    @isTest
    static void test<メソッド名>_NullInput() {
        // null 入力のテスト
        ...
    }
    
    // === バルクテスト ===
    
    @isTest
    static void test<メソッド名>_BulkOperation() {
        // 200件でのテスト
        List<Lead> bulkLeads = TestDataFactory.createLeads(200);
        insert bulkLeads;
        Set<Id> leadIds = new Map<Id, Lead>(bulkLeads).keySet();
        
        Test.startTest();
        <メソッド呼び出し>
        Test.stopTest();
        
        // ガバナ制限超過しないことを検証
        List<Lead> updated = [SELECT Id, Score__c FROM Lead WHERE Id IN :leadIds];
        System.assertEquals(200, updated.size(), '200件すべて処理されているはず');
    }
    
    // === 境界値テスト ===
    
    @isTest
    static void test<メソッド名>_EmptyList() {
        // 空リストでのテスト
        ...
    }
}
```

### Step 4: テストパターンの網羅

各 public メソッドについて、以下を必ず含めてください。

#### 必須テストパターン

```
[ポジティブ]
✓ 通常の引数で正しい結果が返るか

[ネガティブ]
✓ null 引数での動作
✓ 空リスト/空セットでの動作
✓ 不正な値（境界値外）での動作
✓ 例外発生時の動作

[バルク]
✓ 200件の処理（必須）

[境界値]
✓ 最小値・最大値
✓ ちょうど閾値の値（カテゴリ判定など）
```

#### Salesforce 特有のテストパターン

```
[トリガーテスト]
✓ insert / update / delete でトリガーが発火するか
✓ トリガー内のロジックが正しく動くか
✓ 200件のバルク insert でガバナ制限超過しないか

[@AuraEnabled テスト]
✓ 正常系のレスポンス
✓ AuraHandledException がスローされる場合のテスト
✓ System.runAs() で異なるユーザー権限でのテスト

[セキュリティテスト]
✓ 権限のないユーザーでのアクセス制御
✓ WITH SECURITY_ENFORCED の動作確認
```

### Step 5: アサーションの充実

各テストには必ず以下を含めてください。

```apex
// 良い例: 何を期待しているかが明確
System.assertEquals(15, score, 'Technology industry should add 15 points');
System.assertNotEquals(null, lead.Score__c, 'Score should be calculated');
System.assert(lead.Score__c >= 0, 'Score should be non-negative');

// 悪い例: メッセージなし、何を確認しているか不明
System.assertEquals(15, score);
```

### Step 6: TestDataFactory の生成（必要な場合）

TestDataFactory が存在しない場合、以下のような構造で生成してください。

```apex
@isTest
public class TestDataFactory {
    
    /**
     * テスト用のリードを生成
     */
    public static List<Lead> createLeads(Integer count) {
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < count; i++) {
            leads.add(new Lead(
                FirstName = 'Test',
                LastName = 'User' + i,
                Company = 'Test Company ' + i,
                Title = 'Manager',
                Industry = 'Technology',
                NumberOfEmployees = 1000,
                LeadSource = 'Webinar',
                Email = 'test' + i + '@example.com'
            ));
        }
        return leads;
    }
    
    /**
     * テスト用のキャンペーンを生成
     */
    public static List<Campaign> createCampaigns(Integer count) {
        List<Campaign> campaigns = new List<Campaign>();
        for (Integer i = 0; i < count; i++) {
            campaigns.add(new Campaign(
                Name = 'Test Campaign ' + i,
                IsActive = true,
                Type = 'Webinar'
            ));
        }
        return campaigns;
    }
    
    // 他に必要なファクトリメソッド
}
```

### Step 7: 出力フォーマット

```markdown
# テストクラス生成結果

## 対象クラス
`<対象クラスのパス>`

## 生成するファイル
- `<対象クラス名>Test.cls`（テストクラス）
- `<対象クラス名>Test.cls-meta.xml`（メタデータ）
- `TestDataFactory.cls`（存在しない場合のみ）

## カバレッジ目標
90% 以上（CLAUDE.md の規約に準拠）

## テストパターン

| パターン | テストメソッド | 目的 |
|---|---|---|
| ポジティブ | test<...>_Success | 正常系 |
| ネガティブ | test<...>_InvalidInput | 不正入力 |
| ネガティブ | test<...>_NullInput | null 処理 |
| バルク | test<...>_BulkOperation | 200件処理 |
| 境界値 | test<...>_BoundaryValue | 閾値テスト |
| 例外 | test<...>_ExceptionHandling | 例外処理 |

## 生成コード

[テストクラスの全コード]

## 次のアクション

1. テストクラスをファイルに保存しますか？
2. デプロイしてカバレッジを確認しますか？
3. 不足しているテストパターンがあれば追加しますか？
```

## 注意事項

### テスト品質の原則

```
✓ アサーションを必ず書く
✓ メッセージ付きアサーション
✓ @TestSetup を使う
✓ Test.startTest() / Test.stopTest() を使う
✓ SeeAllData=true は禁止
✓ バルクテストは必須
✓ ネガティブケースも必ず含める
```

### Salesforce のテスト要件

```
[デプロイ要件]
- カバレッジ 75% 以上（必須）
- 推奨: 90% 以上
- 全テストが Pass

[Apex テストの制約]
- @isTest アノテーションが必要
- private クラスにする（推奨）
- isTest=true のメソッドで Test.startTest() を使う
```

### 研修教材としての配慮

- なぜこのテストパターンが必要かを説明
- アサーションメッセージで「何を確認しているか」を明確に
- バルクテストの重要性を強調

このように動作してください。
