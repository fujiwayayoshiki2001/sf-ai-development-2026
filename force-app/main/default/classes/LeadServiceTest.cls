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
     * getAllLeads が全カテゴリをスコア降順で返すことを検証する。
     */
    @isTest
    static void testGetAllLeads() {
        List<Lead> leads = TestDataFactory.createLeads(3);
        insert leads;
        leads[0].Score__c = 120; leads[0].Lead_Category__c = LeadConstants.CATEGORY_WARM;
        leads[1].Score__c = 200; leads[1].Lead_Category__c = LeadConstants.CATEGORY_HOT;
        leads[2].Score__c = 30;  leads[2].Lead_Category__c = LeadConstants.CATEGORY_LOW;
        setScoresBypassingTrigger(leads);

        Test.startTest();
        List<Lead> result = LeadService.getAllLeads(200);
        Test.stopTest();

        System.assertEquals(3, result.size(), '全カテゴリ3件が返るはず');
        System.assertEquals(200, result[0].Score__c, '先頭は最高スコア200のはず');
        System.assertEquals(120, result[1].Score__c, '2件目は120のはず');
        System.assertEquals(30, result[2].Score__c, '3件目は30のはず');
    }

    /**
     * getAllLeads が件数上限を尊重することを検証する。
     */
    @isTest
    static void testGetAllLeadsLimit() {
        insert TestDataFactory.createLeads(5);

        Test.startTest();
        List<Lead> limited = LeadService.getAllLeads(2);
        Test.stopTest();

        System.assertEquals(2, limited.size(), 'limit=2 で2件のはず');
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

    // ===== getScoreBreakdown =====

    /**
     * スコア内訳が { attribute, behavior, interest, total } で返ることを検証する。
     * TestDataFactory の既定リードは属性70・他0・合計70。
     */
    @isTest
    static void testGetScoreBreakdown_Success() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;

        Test.startTest();
        Map<String, Decimal> breakdown = LeadService.getScoreBreakdown(leads[0].Id);
        Test.stopTest();

        System.assertEquals(70, breakdown.get('attribute'), '属性スコアは70のはず');
        System.assertEquals(0, breakdown.get('behavior'), '行動スコアは0のはず');
        System.assertEquals(0, breakdown.get('interest'), '興味スコアは0のはず');
        System.assertEquals(70, breakdown.get('total'), '合計は70のはず');
    }

    /**
     * null Id では IllegalArgumentException（標準例外）が投げられることを検証する。
     */
    @isTest
    static void testGetScoreBreakdown_NullId() {
        Boolean threw = false;
        Test.startTest();
        try {
            LeadService.getScoreBreakdown(null);
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'null Id では IllegalArgumentException が投げられるはず');
    }

    /**
     * 存在しない Id では QueryException（標準例外）が投げられることを検証する。
     */
    @isTest
    static void testGetScoreBreakdown_NotFound() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        Id leadId = leads[0].Id;
        delete [SELECT Id FROM Lead WHERE Id = :leadId];

        Boolean threw = false;
        Test.startTest();
        try {
            LeadService.getScoreBreakdown(leadId);
        } catch (QueryException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, '存在しない Id では QueryException が投げられるはず');
    }

    // ===== getInterests =====

    /**
     * 興味レコードが関心度（Interest_Level__c）の降順で返ることを検証する。
     */
    @isTest
    static void testGetInterests_Success() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        insert new List<Lead_Interest__c>{
            new Lead_Interest__c(Lead__c = leads[0].Id, Interest_Topic__c = 'AI 活用',
                Interest_Level__c = 30, Detected_Date__c = Date.today(), Source__c = 'T'),
            new Lead_Interest__c(Lead__c = leads[0].Id, Interest_Topic__c = '業務効率化',
                Interest_Level__c = 80, Detected_Date__c = Date.today(), Source__c = 'T')
        };

        Test.startTest();
        List<Lead_Interest__c> result = LeadService.getInterests(leads[0].Id);
        Test.stopTest();

        System.assertEquals(2, result.size(), '興味は2件返るはず');
        System.assertEquals(80, result[0].Interest_Level__c, 'レベル降順で先頭は80のはず');
        System.assertEquals(30, result[1].Interest_Level__c, '2件目は30のはず');
    }

    /**
     * null Id では IllegalArgumentException（標準例外）が投げられることを検証する。
     */
    @isTest
    static void testGetInterests_NullId() {
        Boolean threw = false;
        Test.startTest();
        try {
            LeadService.getInterests(null);
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'null Id では IllegalArgumentException が投げられるはず');
    }

    /**
     * 興味レコードが無いリードでは空リストが返ることを検証する。
     */
    @isTest
    static void testGetInterests_EmptyResult() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;

        Test.startTest();
        List<Lead_Interest__c> result = LeadService.getInterests(leads[0].Id);
        Test.stopTest();

        System.assertEquals(0, result.size(), '興味が無いリードは空リストのはず');
    }

    /**
     * 興味レコードが上限（INTEREST_LIMIT=100）を超えても 100 件で打ち止めになることを検証する。
     */
    @isTest
    static void testGetInterests_BulkCount() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        List<Lead_Interest__c> interests = new List<Lead_Interest__c>();
        for (Integer i = 0; i < 120; i++) {
            interests.add(new Lead_Interest__c(
                Lead__c = leads[0].Id, Interest_Topic__c = 'AI 活用',
                Interest_Level__c = i + 1, Detected_Date__c = Date.today(), Source__c = 'T'
            ));
        }
        insert interests;

        Test.startTest();
        List<Lead_Interest__c> result = LeadService.getInterests(leads[0].Id);
        Test.stopTest();

        System.assertEquals(100, result.size(), '120件あっても上限100件で打ち止めのはず');
        System.assertEquals(120, result[0].Interest_Level__c,
            '降順のため先頭は最大レベル120のはず');
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
     * 更新権限の無いユーザーでは SecurityException（標準例外）が投げられることを検証する。
     * サービス層は UI 向けの AuraHandledException ではなく標準例外を投げる。
     */
    @isTest
    static void testUpdateLastActionDateThrowsSecurityWithoutAccess() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        Set<Id> ids = new Map<Id, Lead>(leads).keySet();

        // User（setup オブジェクト）の DML は MIXED_DML 回避のため runAs 内で行う
        User minUser = buildMinimumAccessUser();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert minUser;
        }

        Boolean threw = false;
        System.runAs(minUser) {
            Test.startTest();
            try {
                LeadService.updateLastActionDate(ids);
            } catch (SecurityException e) {
                threw = true;
            }
            Test.stopTest();
        }
        System.assert(threw,
            '更新権限の無いユーザーでは SecurityException が投げられるはず');
    }

    /**
     * 最小アクセス権限のユーザーを生成する（未 insert）。
     */
    private static User buildMinimumAccessUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        String unique = 'minsvc' + System.now().getTime();
        return new User(
            Alias = 'minsvc',
            Email = unique + '@example.com.invalid',
            LastName = 'MinAccess',
            Username = unique + '@example.com.invalid',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
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
