/**
 * LeadService の単体テスト。
 *
 * カテゴリ別取得・検索・最終アクション日更新・陳腐化リード取得を検証する。
 *
 * 検証観点: カテゴリ別取得とスコア降順 / 件数制限 / 検索 / 空入力 /
 *           アクション日更新 / 陳腐化判定 / null・空ガード / バルク(200件)。
 */
@isTest
private class LeadServiceTest {

    /**
     * トリガーを迂回してスコア・カテゴリを任意値に設定する（並び順・カテゴリ検証用）。
     */
    private static void setScoresBypassingTrigger(List<Lead> leads) {
        LeadTriggerHandler.bypassTrigger = true;
        update leads;
        LeadTriggerHandler.bypassTrigger = false;
    }

    /**
     * カテゴリ別取得がスコア降順で返ることを検証する。
     */
    @isTest
    static void testGetLeadsByCategoryOrdered() {
        List<Lead> leads = TestDataFactory.createLeads(3);
        insert leads;
        leads[0].Score__c = 200; leads[0].Lead_Category__c = LeadConstants.CATEGORY_HOT;
        leads[1].Score__c = 150; leads[1].Lead_Category__c = LeadConstants.CATEGORY_HOT;
        leads[2].Score__c = 190; leads[2].Lead_Category__c = LeadConstants.CATEGORY_HOT;
        setScoresBypassingTrigger(leads);

        Test.startTest();
        List<Lead> result = LeadService.getLeadsByCategory(LeadConstants.CATEGORY_HOT, 50);
        Test.stopTest();

        System.assertEquals(3, result.size(), 'Hot リードが3件返るはず');
        System.assertEquals(200, result[0].Score__c, '1件目は最高スコア200のはず');
        System.assertEquals(190, result[1].Score__c, '2件目は190のはず');
        System.assertEquals(150, result[2].Score__c, '3件目は150のはず');
    }

    /**
     * 取得件数の上限（limit）が効くことを検証する。
     */
    @isTest
    static void testGetLeadsByCategoryLimit() {
        List<Lead> leads = TestDataFactory.createLeads(5);
        insert leads; // 全件 Cold(70)

        Test.startTest();
        List<Lead> limited = LeadService.getLeadsByCategory(LeadConstants.CATEGORY_COLD, 2);
        List<Lead> defaulted = LeadService.getLeadsByCategory(LeadConstants.CATEGORY_COLD, null);
        Test.stopTest();

        System.assertEquals(2, limited.size(), 'limit=2 で2件のはず');
        System.assertEquals(5, defaulted.size(), 'limit=null は既定50で全5件のはず');
    }

    /**
     * カテゴリが空の場合は空リストを返すことを検証する。
     */
    @isTest
    static void testGetLeadsByCategoryBlank() {
        Test.startTest();
        System.assertEquals(0, LeadService.getLeadsByCategory('', 10).size(),
            '空カテゴリは空リストのはず');
        System.assertEquals(0, LeadService.getLeadsByCategory(null, 10).size(),
            'null カテゴリは空リストのはず');
        Test.stopTest();
    }

    /**
     * 名前・会社名による検索を検証する。
     */
    @isTest
    static void testSearchLeads() {
        List<Lead> leads = TestDataFactory.createLeads(3);
        insert leads;

        Test.startTest();
        List<Lead> byCompany = LeadService.searchLeads('Test Company', null);
        List<Lead> blank = LeadService.searchLeads('', null);
        Test.stopTest();

        System.assertEquals(3, byCompany.size(), '会社名部分一致で3件返るはず');
        System.assertEquals(0, blank.size(), '空文字検索は空リストのはず');
    }

    /**
     * 最終アクション日が本日に更新されることを検証する。
     */
    @isTest
    static void testUpdateLastActionDate() {
        List<Lead> leads = TestDataFactory.createLeads(3);
        insert leads;
        Set<Id> ids = new Map<Id, Lead>(leads).keySet();

        Test.startTest();
        LeadService.updateLastActionDate(ids);
        Test.stopTest();

        List<Lead> updated = [
            SELECT Last_Action_Date__c FROM Lead WHERE Id IN :ids
        ];
        for (Lead lead : updated) {
            System.assertEquals(Date.today(), lead.Last_Action_Date__c,
                '最終アクション日が本日に更新されるはず');
        }
    }

    /**
     * updateLastActionDate の null / 空ガードを検証する。
     */
    @isTest
    static void testUpdateLastActionDateGuards() {
        Test.startTest();
        LeadService.updateLastActionDate(null);
        LeadService.updateLastActionDate(new Set<Id>());
        Test.stopTest();
        System.assert(true, 'ガードにより例外なく完了するはず');
    }

    /**
     * 陳腐化リード（最終アクション日が STALE_DAYS 日以上前）が取得されることを検証する。
     */
    @isTest
    static void testGetStaleLeads() {
        List<Lead> leads = TestDataFactory.createLeads(2);
        insert leads;
        // 1件目は40日前、2件目は本日
        leads[0].Last_Action_Date__c = Date.today().addDays(-40);
        leads[1].Last_Action_Date__c = Date.today();
        setScoresBypassingTrigger(leads);

        Test.startTest();
        List<Lead> stale = LeadService.getStaleLeads();
        Test.stopTest();

        System.assertEquals(1, stale.size(), '40日前の1件のみ陳腐化候補のはず');
        System.assertEquals(leads[0].Id, stale[0].Id, '40日前のリードが返るはず');
    }

    /**
     * バルク（200件）でカテゴリ別取得・アクション日更新が動作することを検証する。
     */
    @isTest
    static void testBulk() {
        List<Lead> leads = TestDataFactory.createLeads(200);
        insert leads; // 全件 Cold(70)
        Set<Id> ids = new Map<Id, Lead>(leads).keySet();

        Test.startTest();
        List<Lead> result = LeadService.getLeadsByCategory(LeadConstants.CATEGORY_COLD, 200);
        LeadService.updateLastActionDate(ids);
        Test.stopTest();

        System.assertEquals(200, result.size(), '200件すべて取得できるはず');
        System.assertEquals(
            200,
            [SELECT COUNT() FROM Lead WHERE Last_Action_Date__c = TODAY],
            '200件すべて本日に更新されるはず'
        );
    }
}
