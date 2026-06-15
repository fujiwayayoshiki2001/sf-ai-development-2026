/**
 * CampaignMemberTriggerHandler の単体テスト。
 *
 * CampaignMemberTrigger → CampaignMemberTriggerHandler → LeadScoringService の委譲経路で、
 * キャンペーン参加の挿入・更新・削除に応じて Lead の行動スコアが再計算されることを検証する。
 * （CampaignMember は undelete 不可のため、afterUndelete はハンドラを直接呼び出して検証する）
 *
 * 検証観点:
 *   afterInsert   : 挿入で行動スコア反映（Webinar_Attended=30）
 *   afterUpdate   : ステータス変更で再計算（Registered=10 → Attended=30）
 *   afterDelete   : 削除で行動スコア0に再計算
 *   afterUndelete : ハンドラ直接呼び出しで再計算
 *   bypassTrigger : フラグ ON で再計算がスキップされる
 *   ガード        : null / 空入力で安全に early-return
 *   バルク        : 200件
 */
@isTest
private class CampaignMemberTriggerHandlerTest {

    /**
     * Webinar キャンペーンを作り 'Registered'(=10) / 'Attended'(=30) ステータスを追加して返す。
     */
    private static Campaign createCampaign(String name) {
        Campaign campaign = new Campaign(Name = name, Type = 'Webinar', IsActive = true);
        insert campaign;
        insert new List<CampaignMemberStatus>{
            new CampaignMemberStatus(CampaignId = campaign.Id, Label = 'Registered', SortOrder = 10, HasResponded = false),
            new CampaignMemberStatus(CampaignId = campaign.Id, Label = 'Attended', SortOrder = 11, HasResponded = true)
        };
        return campaign;
    }

    private static Decimal behaviorScoreOf(Id leadId) {
        return [SELECT Behavior_Score__c FROM Lead WHERE Id = :leadId].Behavior_Score__c;
    }

    /**
     * 挿入で afterInsert が行動スコアを反映することを検証する（Webinar_Attended=30）。
     */
    @isTest
    static void testAfterInsertRecalculates() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        Campaign campaign = createCampaign('CM Insert');

        Test.startTest();
        insert new CampaignMember(CampaignId = campaign.Id, LeadId = leads[0].Id, Status = 'Attended');
        Test.stopTest();

        System.assertEquals(30, behaviorScoreOf(leads[0].Id),
            'Webinar_Attended で行動スコア30が反映されるはず');
    }

    /**
     * ステータス更新（afterUpdate）で再計算されることを検証する（10 → 30）。
     */
    @isTest
    static void testAfterUpdateRecalculates() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        Campaign campaign = createCampaign('CM Update');
        CampaignMember member = new CampaignMember(
            CampaignId = campaign.Id, LeadId = leads[0].Id, Status = 'Registered'
        );
        insert member;
        System.assertEquals(10, behaviorScoreOf(leads[0].Id), '挿入時点で Registered=10 のはず');

        Test.startTest();
        member.Status = 'Attended';
        update member;
        Test.stopTest();

        System.assertEquals(30, behaviorScoreOf(leads[0].Id),
            'ステータス変更で 10→30 に再計算されるはず');
    }

    /**
     * 削除（afterDelete）で行動スコアが0に再計算されることを検証する。
     */
    @isTest
    static void testAfterDeleteRecalculates() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        Campaign campaign = createCampaign('CM Delete');
        CampaignMember member = new CampaignMember(
            CampaignId = campaign.Id, LeadId = leads[0].Id, Status = 'Attended'
        );
        insert member;
        System.assertEquals(30, behaviorScoreOf(leads[0].Id), '挿入時点で30のはず');

        Test.startTest();
        delete member;
        Test.stopTest();

        System.assertEquals(0, behaviorScoreOf(leads[0].Id), '削除後は0に再計算されるはず');
    }

    /**
     * afterUndelete をハンドラ直接呼び出しで検証する。
     * （CampaignMember は DML での undelete が不可のため）
     * 事前に Behavior_Score を別値に汚しておき、再計算で30に戻ることを確認する。
     */
    @isTest
    static void testAfterUndeleteRecalculates() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        Campaign campaign = createCampaign('CM Undelete');
        CampaignMember member = new CampaignMember(
            CampaignId = campaign.Id, LeadId = leads[0].Id, Status = 'Attended'
        );
        insert member; // ここで30になる

        // Behavior_Score をわざと汚す（bypass して直接 update）
        LeadTriggerHandler.bypassTrigger = true;
        update new Lead(Id = leads[0].Id, Behavior_Score__c = 999);
        LeadTriggerHandler.bypassTrigger = false;
        System.assertEquals(999, behaviorScoreOf(leads[0].Id), '汚し更新で999のはず');

        Test.startTest();
        CampaignMemberTriggerHandler.afterUndelete(new List<CampaignMember>{ member });
        Test.stopTest();

        System.assertEquals(30, behaviorScoreOf(leads[0].Id),
            'afterUndelete の再計算で30に戻るはず');
    }

    /**
     * bypassTrigger が ON のときは再計算がスキップされることを検証する。
     */
    @isTest
    static void testBypassSkipsRecalculation() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        Campaign campaign = createCampaign('CM Bypass');

        Test.startTest();
        LeadTriggerHandler.bypassTrigger = true;
        try {
            insert new CampaignMember(CampaignId = campaign.Id, LeadId = leads[0].Id, Status = 'Attended');
        } finally {
            LeadTriggerHandler.bypassTrigger = false;
        }
        Test.stopTest();

        System.assertEquals(0, behaviorScoreOf(leads[0].Id),
            'bypass ON 時は行動スコアが再計算されず0のままのはず');
    }

    /**
     * 各ハンドラメソッドが null / 空 / bypass で安全に early-return することを検証する。
     */
    @isTest
    static void testGuards() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        List<CampaignMember> dummy = new List<CampaignMember>{
            new CampaignMember(LeadId = leads[0].Id)
        };

        Test.startTest();
        LeadTriggerHandler.bypassTrigger = false;
        // null / 空
        CampaignMemberTriggerHandler.afterInsert(null);
        CampaignMemberTriggerHandler.afterInsert(new List<CampaignMember>());
        CampaignMemberTriggerHandler.afterUpdate(null, null);
        CampaignMemberTriggerHandler.afterUpdate(new List<CampaignMember>(), new Map<Id, CampaignMember>());
        CampaignMemberTriggerHandler.afterDelete(null);
        CampaignMemberTriggerHandler.afterDelete(new List<CampaignMember>());
        CampaignMemberTriggerHandler.afterUndelete(null);
        CampaignMemberTriggerHandler.afterUndelete(new List<CampaignMember>());

        // bypass ON（非空リストでも early-return する）
        LeadTriggerHandler.bypassTrigger = true;
        try {
            CampaignMemberTriggerHandler.afterInsert(dummy);
            CampaignMemberTriggerHandler.afterUpdate(dummy, null);
            CampaignMemberTriggerHandler.afterDelete(dummy);
            CampaignMemberTriggerHandler.afterUndelete(dummy);
        } finally {
            LeadTriggerHandler.bypassTrigger = false;
        }
        Test.stopTest();

        System.assertEquals(0, behaviorScoreOf(leads[0].Id),
            'ガード経路では再計算されず0のままのはず');
    }

    /**
     * バルク（200件）のメンバー挿入で全リードに反映されることを検証する。
     */
    @isTest
    static void testBulkInsert() {
        List<Lead> leads = TestDataFactory.createLeads(200);
        insert leads;
        Campaign campaign = createCampaign('CM Bulk');

        List<CampaignMember> members = new List<CampaignMember>();
        for (Lead lead : leads) {
            members.add(new CampaignMember(CampaignId = campaign.Id, LeadId = lead.Id, Status = 'Attended'));
        }

        Test.startTest();
        insert members;
        Test.stopTest();

        System.assertEquals(200, [SELECT COUNT() FROM Lead WHERE Behavior_Score__c = 30],
            '200件すべてに行動スコア30が反映されるはず');
    }
}
