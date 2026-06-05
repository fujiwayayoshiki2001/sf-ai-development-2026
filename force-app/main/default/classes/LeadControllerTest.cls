/**
 * LeadController / LeadTriggerHandler / LeadTrigger のテスト。
 * ハッピーパスと異常系の両方を検証し、カバレッジ75%以上を満たす。
 */
@isTest(SeeAllData=false)
private class LeadControllerTest {
    private static final String STATUS_OPEN = 'Open - Not Contacted';

    /**
     * 共通テストデータを作成する。
     * - highLead : 高スコア（30以上）になる条件を満たすリード
     * - lowLead  : 加点要素のない低スコアのリード
     */
    @TestSetup
    static void setupData() {
        List<Lead> leads = new List<Lead>();

        // 高スコア狙い: Email+Phone+Industry+Source+Hot+高売上+大規模 = 10+10+5+5+20+20+20 = 90
        leads.add(new Lead(
            LastName = 'High',
            Company = '高スコア株式会社',
            Status = STATUS_OPEN,
            Email = 'high@example.com',
            Phone = '03-0000-0001',
            Industry = 'Technology',
            LeadSource = 'Web',
            Rating = 'Hot',
            AnnualRevenue = 500000000,
            NumberOfEmployees = 5000
        ));

        // 低スコア: 加点要素なし = 0
        leads.add(new Lead(
            LastName = 'Low',
            Company = '低スコア株式会社',
            Status = STATUS_OPEN
        ));

        insert leads;
    }

    @isTest
    static void testTriggerScore_HappyPath() {
        Lead highLead = [SELECT Score__c FROM Lead WHERE LastName = 'High' LIMIT 1];
        Lead lowLead = [SELECT Score__c FROM Lead WHERE LastName = 'Low' LIMIT 1];

        System.assertEquals(90, highLead.Score__c, '高スコアリードのスコアが想定と異なります');
        System.assertEquals(0, lowLead.Score__c, '低スコアリードは0点のはずです');
    }

    @isTest
    static void testTriggerScore_RecalculateOnUpdate() {
        Lead lowLead = [SELECT Id, Score__c FROM Lead WHERE LastName = 'Low' LIMIT 1];
        System.assertEquals(0, lowLead.Score__c, '更新前は0点のはずです');

        lowLead.Email = 'updated@example.com';
        lowLead.Rating = 'Warm';

        Test.startTest();
        update lowLead;
        Test.stopTest();

        Lead updated = [SELECT Score__c FROM Lead WHERE Id = :lowLead.Id];
        // Email(10) + Warm(10) = 20
        System.assertEquals(20, updated.Score__c, '更新時にスコアが再計算されていません');
    }

    @isTest
    static void testCalculateScore_NullLead() {
        System.assertEquals(0, LeadController.calculateScore(null), 'null は0点であるべきです');
    }

    @isTest
    static void testCalculateScore_ScoreCappedAt100() {
        Lead maxLead = new Lead(
            LastName = 'Max', Company = 'Max',
            Email = 'm@example.com', Phone = '1', Industry = 'Tech',
            LeadSource = 'Web', Rating = 'Hot',
            AnnualRevenue = 999999999, NumberOfEmployees = 99999
        );
        Integer score = LeadController.calculateScore(maxLead);
        System.assert(score <= 100, 'スコアは100を超えてはいけません');
    }

    @isTest
    static void testGetLeads_AllAndFilter() {
        Test.startTest();
        List<Lead> all = LeadController.getLeads(null, false);
        List<Lead> highOnly = LeadController.getLeads(null, true);
        List<Lead> byStatus = LeadController.getLeads(STATUS_OPEN, false);
        Test.stopTest();

        System.assertEquals(2, all.size(), '全件取得は2件のはずです');
        System.assertEquals(1, highOnly.size(), '高スコアは1件のはずです');
        System.assertEquals('High', highOnly[0].LastName, '高スコアリードはHighのはずです');
        System.assertEquals(2, byStatus.size(), 'ステータス絞り込みは2件のはずです');
    }

    @isTest
    static void testGetHighScoreLeads_HappyPath() {
        Test.startTest();
        List<Lead> highLeads = LeadController.getHighScoreLeads();
        Test.stopTest();

        System.assertEquals(1, highLeads.size(), '高スコアリードは1件のはずです');
        System.assert(highLeads[0].Score__c >= 30, '取得したリードは30点以上であるべきです');
    }

    @isTest
    static void testRecalculateScores_HappyPath() {
        List<Id> leadIds = new List<Id>();
        for (Lead ld : [SELECT Id FROM Lead]) {
            leadIds.add(ld.Id);
        }

        Test.startTest();
        List<Lead> result = LeadController.recalculateScores(leadIds);
        Test.stopTest();

        System.assertEquals(2, result.size(), '再計算結果は2件のはずです');
    }

    @isTest
    static void testRecalculateScores_NullInput() {
        try {
            LeadController.recalculateScores(null);
            System.assert(false, '例外が発生するはずです');
        } catch (LeadScoreException e) {
            System.assert(
                e.getMessage().contains('指定されていません'),
                '想定外のエラーメッセージです: ' + e.getMessage()
            );
        }
    }

    @isTest
    static void testRecalculateScores_EmptyTargets() {
        // 存在しないIDを指定（型として有効な Lead の偽ID）
        List<Id> fakeIds = new List<Id>{ '00Q000000000001AAA' };
        try {
            LeadController.recalculateScores(fakeIds);
            System.assert(false, '例外が発生するはずです');
        } catch (LeadScoreException e) {
            System.assert(
                e.getMessage().contains('見つかりません'),
                '想定外のエラーメッセージです: ' + e.getMessage()
            );
        }
    }

    @isTest
    static void testTriggerBulk_TwoHundredLeads() {
        List<Lead> bulkLeads = new List<Lead>();
        for (Integer i = 0; i < 200; i++) {
            bulkLeads.add(new Lead(
                LastName = 'Bulk' + i,
                Company = 'Bulk Co ' + i,
                Status = STATUS_OPEN,
                Email = 'bulk' + i + '@example.com'
            ));
        }

        Test.startTest();
        insert bulkLeads;
        Test.stopTest();

        List<Lead> inserted = [SELECT Score__c FROM Lead WHERE LastName LIKE 'Bulk%'];
        System.assertEquals(200, inserted.size(), '200件登録されるはずです');
        for (Lead ld : inserted) {
            System.assertEquals(10, ld.Score__c, 'Emailのみで10点のはずです');
        }
    }
}