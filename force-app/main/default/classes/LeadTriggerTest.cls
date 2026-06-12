/**
 * トリガー群（LeadTrigger / CampaignMemberTrigger / LeadInterestTrigger）の統合テスト。
 *
 * 各トリガーが LeadTriggerHandler / LeadScoringService / LeadValidator へ正しく委譲し、
 * スコアの再計算とバリデーションが発火することを検証する。
 *
 * 検証観点:
 *   LeadTrigger        : 挿入時スコア計算 / 属性更新時の再計算 / 非属性更新時は据え置き /
 *                        挿入時バリデーション / バルク(200件)
 *   CampaignMemberTrigger : 挿入で行動スコア反映 / 削除・復元で再計算
 *   LeadInterestTrigger   : 挿入で興味スコア反映 / 親付け替え / 削除で再計算
 */
@isTest
private class LeadTriggerTest {

    /**
     * Webinar キャンペーンを作り 'Attended'(=30) ステータスを追加して返す。
     */
    private static Campaign createAttendedCampaign(String name) {
        Campaign campaign = new Campaign(Name = name, Type = 'Webinar', IsActive = true);
        insert campaign;
        insert new CampaignMemberStatus(
            CampaignId = campaign.Id, Label = 'Attended', SortOrder = 10, HasResponded = true
        );
        return campaign;
    }

    private static Lead_Interest__c interest(Id leadId, String topic, Decimal level) {
        return new Lead_Interest__c(
            Lead__c = leadId, Interest_Topic__c = topic,
            Interest_Level__c = level, Detected_Date__c = Date.today(), Source__c = 'Test'
        );
    }

    // ===== LeadTrigger =====

    /**
     * 挿入時に afterInsert がスコアを計算・反映することを検証する。
     */
    @isTest
    static void testLeadInsertComputesScore() {
        Test.startTest();
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        Test.stopTest();

        Lead result = [
            SELECT Score__c, Attribute_Score__c, Lead_Category__c, Score_Last_Calculated__c
            FROM Lead WHERE Id = :leads[0].Id
        ];
        System.assertEquals(70, result.Score__c, '挿入時に属性70が計算されるはず');
        System.assertEquals(LeadConstants.CATEGORY_COLD, result.Lead_Category__c,
            '70点は Cold のはず');
        System.assertNotEquals(null, result.Score_Last_Calculated__c,
            '計算日時がセットされるはず');
    }

    /**
     * 属性項目（Title）更新で afterUpdate が再計算することを検証する。
     * Manager(15) → CEO(C-level 30) で属性 70 → 85。
     */
    @isTest
    static void testLeadAttributeUpdateRecalculates() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;

        Test.startTest();
        update new Lead(Id = leads[0].Id, Title = 'CEO');
        Test.stopTest();

        Lead result = [SELECT Score__c FROM Lead WHERE Id = :leads[0].Id];
        System.assertEquals(85, result.Score__c,
            '役職を CEO に変更で属性 70→85 になるはず');
    }

    /**
     * 非属性項目のみの更新では再計算されず、スコアが据え置かれることを検証する。
     */
    @isTest
    static void testLeadNonAttributeUpdateKeepsScore() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads; // Score 70

        Test.startTest();
        update new Lead(Id = leads[0].Id, Last_Action_Date__c = Date.today());
        Test.stopTest();

        Lead result = [SELECT Score__c FROM Lead WHERE Id = :leads[0].Id];
        System.assertEquals(70, result.Score__c,
            '属性に影響しない更新ではスコアは据え置き70のはず');
    }

    /**
     * 挿入時バリデーション（beforeInsert）が不正メールを弾くことを検証する。
     */
    @isTest
    static void testLeadValidationOnInsert() {
        Lead bad = new Lead(LastName = 'Yamada', Company = 'Acme', Email = 'invalid-email');

        Test.startTest();
        Database.SaveResult result = Database.insert(bad, false);
        Test.stopTest();

        System.assert(!result.isSuccess(), '不正メールの挿入は失敗するはず');
        System.assert(
            result.getErrors()[0].getMessage().contains('メール'),
            'メール形式エラーが返るはず: ' + result.getErrors()[0].getMessage()
        );
    }

    /**
     * バルク（200件）挿入で全件にスコアが反映されることを検証する。
     */
    @isTest
    static void testLeadBulkInsert() {
        Test.startTest();
        List<Lead> leads = TestDataFactory.createLeads(200);
        insert leads;
        Test.stopTest();

        System.assertEquals(
            200,
            [SELECT COUNT() FROM Lead WHERE Score__c = 70],
            '200件すべてに属性スコア70が反映されるはず'
        );
    }

    /**
     * ハンドラの各イベントメソッドが null / 空入力で安全に early-return することを検証する。
     * （トリガー経由では通らないガード行を直接呼び出して確認する）
     */
    @isTest
    static void testHandlerGuards() {
        Test.startTest();
        LeadTriggerHandler.beforeInsert(null);
        LeadTriggerHandler.beforeInsert(new List<Lead>());
        LeadTriggerHandler.beforeUpdate(null, null);
        LeadTriggerHandler.beforeUpdate(new List<Lead>(), new Map<Id, Lead>());
        LeadTriggerHandler.afterInsert(null, null);
        LeadTriggerHandler.afterInsert(new List<Lead>(), new Map<Id, Lead>());
        LeadTriggerHandler.afterUpdate(null, null, null);
        LeadTriggerHandler.afterUpdate(new List<Lead>(), new Map<Id, Lead>(), new Map<Id, Lead>());
        Test.stopTest();
        System.assert(true, 'すべてのガードが例外なく early-return するはず');
    }

    // ===== CampaignMemberTrigger =====

    /**
     * CampaignMember 挿入で行動スコアが反映されることを検証する。
     */
    @isTest
    static void testCampaignMemberInsertRecalculates() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        Campaign campaign = createAttendedCampaign('CM Insert');

        Test.startTest();
        insert new CampaignMember(
            CampaignId = campaign.Id, LeadId = leads[0].Id, Status = 'Attended'
        );
        Test.stopTest();

        Lead result = [SELECT Behavior_Score__c, Score__c FROM Lead WHERE Id = :leads[0].Id];
        System.assertEquals(30, result.Behavior_Score__c,
            'Webinar_Attended で行動スコア30が反映されるはず');
        System.assertEquals(100, result.Score__c, '属性70+行動30=100のはず');
    }

    /**
     * CampaignMember の削除で行動スコアが0に再計算されることを検証する。
     * （CampaignMember は undelete 不可のため削除のみ検証する）
     */
    @isTest
    static void testCampaignMemberDelete() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        Campaign campaign = createAttendedCampaign('CM Delete');
        CampaignMember member = new CampaignMember(
            CampaignId = campaign.Id, LeadId = leads[0].Id, Status = 'Attended'
        );
        insert member;
        // 挿入時点で行動スコア30が反映されている前提
        System.assertEquals(30,
            [SELECT Behavior_Score__c FROM Lead WHERE Id = :leads[0].Id].Behavior_Score__c,
            '挿入時点で行動スコア30のはず');

        Test.startTest();
        delete member;
        Test.stopTest();

        System.assertEquals(0,
            [SELECT Behavior_Score__c FROM Lead WHERE Id = :leads[0].Id].Behavior_Score__c,
            '削除後は行動スコア0に再計算されるはず');
    }

    // ===== LeadInterestTrigger =====

    /**
     * Lead_Interest__c 挿入で興味スコアが反映されることを検証する。
     */
    @isTest
    static void testLeadInterestInsertRecalculates() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;

        Test.startTest();
        insert interest(leads[0].Id, 'AI 活用', 20); // 20×1.5=30
        Test.stopTest();

        Lead result = [SELECT Interest_Score__c, Score__c FROM Lead WHERE Id = :leads[0].Id];
        System.assertEquals(30, result.Interest_Score__c,
            'AI 活用 レベル20で興味スコア30が反映されるはず');
        System.assertEquals(100, result.Score__c, '属性70+興味30=100のはず');
    }

    /**
     * 興味レコードの親付け替え（update）で旧親・新親の双方が再計算されることを検証する。
     */
    @isTest
    static void testLeadInterestReparent() {
        List<Lead> leads = TestDataFactory.createLeads(2);
        insert leads;
        Lead_Interest__c rec = interest(leads[0].Id, 'AI 活用', 20);
        insert rec;

        Test.startTest();
        rec.Lead__c = leads[1].Id; // leadA → leadB へ付け替え
        update rec;
        Test.stopTest();

        Lead leadA = [SELECT Interest_Score__c FROM Lead WHERE Id = :leads[0].Id];
        Lead leadB = [SELECT Interest_Score__c FROM Lead WHERE Id = :leads[1].Id];
        System.assertEquals(0, leadA.Interest_Score__c,
            '旧親(leadA)の興味スコアは0に再計算されるはず');
        System.assertEquals(30, leadB.Interest_Score__c,
            '新親(leadB)の興味スコアは30に再計算されるはず');
    }

    /**
     * 興味レコードの削除で興味スコアが0に再計算されることを検証する。
     */
    @isTest
    static void testLeadInterestDelete() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        Lead_Interest__c rec = interest(leads[0].Id, 'AI 活用', 20);
        insert rec;

        Test.startTest();
        delete rec;
        Test.stopTest();

        Lead result = [SELECT Interest_Score__c FROM Lead WHERE Id = :leads[0].Id];
        System.assertEquals(0, result.Interest_Score__c,
            '興味削除後は興味スコア0に再計算されるはず');
    }
}
