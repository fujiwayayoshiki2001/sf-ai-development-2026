/**
 * LeadInterestTriggerHandler の単体テスト。
 *
 * LeadInterestTrigger → LeadInterestTriggerHandler → LeadScoringService の委譲経路で、
 * 興味レコードの挿入・更新（付け替え）・削除・復元に応じて Lead の興味スコアが
 * 再計算されることを検証する。
 *
 * 検証観点:
 *   afterInsert   : 挿入で興味スコア反映
 *   afterUpdate   : 親付け替えで旧親・新親の双方を再計算
 *   afterDelete   : 削除で興味スコア0に再計算
 *   afterUndelete : 復元で興味スコア再反映
 *   bypassTrigger : フラグ ON で再計算がスキップされる
 *   ガード        : null / 空入力で安全に early-return
 *   バルク        : 200件
 */
@isTest
private class LeadInterestTriggerHandlerTest {

    private static final String TOPIC_AI = 'AI 活用'; // 重み 1.5

    private static Id createLeadId() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        return leads[0].Id;
    }

    private static Lead_Interest__c interest(Id leadId, String topic, Decimal level) {
        return new Lead_Interest__c(
            Lead__c = leadId, Interest_Topic__c = topic,
            Interest_Level__c = level, Detected_Date__c = Date.today(), Source__c = 'Test'
        );
    }

    private static Decimal interestScoreOf(Id leadId) {
        return [SELECT Interest_Score__c FROM Lead WHERE Id = :leadId].Interest_Score__c;
    }

    /**
     * 挿入で afterInsert が興味スコアを反映することを検証する（20×1.5=30）。
     */
    @isTest
    static void testAfterInsertRecalculates() {
        Id leadId = createLeadId();

        Test.startTest();
        insert interest(leadId, TOPIC_AI, 20);
        Test.stopTest();

        System.assertEquals(30, interestScoreOf(leadId),
            '挿入で興味スコア30が反映されるはず');
    }

    /**
     * 親付け替え（afterUpdate）で旧親が0、新親が30に再計算されることを検証する。
     */
    @isTest
    static void testAfterUpdateReparent() {
        List<Lead> leads = TestDataFactory.createLeads(2);
        insert leads;
        Lead_Interest__c rec = interest(leads[0].Id, TOPIC_AI, 20);
        insert rec;

        Test.startTest();
        rec.Lead__c = leads[1].Id;
        update rec;
        Test.stopTest();

        System.assertEquals(0, interestScoreOf(leads[0].Id), '旧親は0に再計算されるはず');
        System.assertEquals(30, interestScoreOf(leads[1].Id), '新親は30に再計算されるはず');
    }

    /**
     * 削除（afterDelete）で興味スコアが0に再計算されることを検証する。
     */
    @isTest
    static void testAfterDeleteRecalculates() {
        Id leadId = createLeadId();
        Lead_Interest__c rec = interest(leadId, TOPIC_AI, 20);
        insert rec;
        System.assertEquals(30, interestScoreOf(leadId), '挿入時点で30のはず');

        Test.startTest();
        delete rec;
        Test.stopTest();

        System.assertEquals(0, interestScoreOf(leadId), '削除後は0に再計算されるはず');
    }

    /**
     * 復元（afterUndelete）で興味スコアが再反映されることを検証する。
     */
    @isTest
    static void testAfterUndeleteRecalculates() {
        Id leadId = createLeadId();
        Lead_Interest__c rec = interest(leadId, TOPIC_AI, 20);
        insert rec;
        delete rec;
        System.assertEquals(0, interestScoreOf(leadId), '削除後は0のはず');

        Test.startTest();
        undelete rec;
        Test.stopTest();

        System.assertEquals(30, interestScoreOf(leadId), '復元後は30に再計算されるはず');
    }

    /**
     * bypassTrigger が ON のときは再計算がスキップされることを検証する。
     */
    @isTest
    static void testBypassSkipsRecalculation() {
        Id leadId = createLeadId();

        Test.startTest();
        LeadTriggerHandler.bypassTrigger = true;
        try {
            insert interest(leadId, TOPIC_AI, 20);
        } finally {
            LeadTriggerHandler.bypassTrigger = false;
        }
        Test.stopTest();

        System.assertEquals(0, interestScoreOf(leadId),
            'bypass ON 時は興味スコアが再計算されず0のままのはず');
    }

    /**
     * 各ハンドラメソッドが null / 空 / bypass で安全に early-return することを検証する。
     */
    @isTest
    static void testGuards() {
        Id leadId = createLeadId();
        List<Lead_Interest__c> dummy = new List<Lead_Interest__c>{ interest(leadId, TOPIC_AI, 20) };

        Test.startTest();
        // null / 空
        LeadInterestTriggerHandler.afterInsert(null);
        LeadInterestTriggerHandler.afterInsert(new List<Lead_Interest__c>());
        LeadInterestTriggerHandler.afterUpdate(null, null);
        LeadInterestTriggerHandler.afterUpdate(new List<Lead_Interest__c>(), new Map<Id, Lead_Interest__c>());
        LeadInterestTriggerHandler.afterDelete(null);
        LeadInterestTriggerHandler.afterDelete(new List<Lead_Interest__c>());
        LeadInterestTriggerHandler.afterUndelete(null);
        LeadInterestTriggerHandler.afterUndelete(new List<Lead_Interest__c>());

        // bypass ON（非空リストでも early-return する）
        LeadTriggerHandler.bypassTrigger = true;
        try {
            LeadInterestTriggerHandler.afterInsert(dummy);
            LeadInterestTriggerHandler.afterUpdate(dummy, null);
            LeadInterestTriggerHandler.afterDelete(dummy);
            LeadInterestTriggerHandler.afterUndelete(dummy);
        } finally {
            LeadTriggerHandler.bypassTrigger = false;
        }
        Test.stopTest();

        System.assertEquals(0, interestScoreOf(leadId),
            'ガード経路では再計算されず0のままのはず');
    }

    /**
     * バルク（200件）の興味挿入で全リードに反映されることを検証する。
     */
    @isTest
    static void testBulkInsert() {
        List<Lead> leads = TestDataFactory.createLeads(200);
        insert leads;
        List<Lead_Interest__c> interests = new List<Lead_Interest__c>();
        for (Lead lead : leads) {
            interests.add(interest(lead.Id, TOPIC_AI, 20));
        }

        Test.startTest();
        insert interests;
        Test.stopTest();

        System.assertEquals(200, [SELECT COUNT() FROM Lead WHERE Interest_Score__c = 30],
            '200件すべてに興味スコア30が反映されるはず');
    }
}
