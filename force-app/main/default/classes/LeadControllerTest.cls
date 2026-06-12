/**
 * LeadController の単体テスト。
 *
 * LWC 窓口の @AuraEnabled メソッドを検証する。例外は AuraHandledException で
 * ラップされるため、ネガティブケースは try-catch で型を確認する。
 *
 * 検証観点: 一覧取得 / 検索 / スコア内訳 / 興味一覧 / 再計算 /
 *           null 入力時の AuraHandledException / 存在しない Id。
 */
@isTest
private class LeadControllerTest {

    private static Id createScoredLead() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads; // afterInsert で属性スコア70・Cold が反映される
        return leads[0].Id;
    }

    /**
     * カテゴリ別一覧取得を検証する。
     */
    @isTest
    static void testGetLeadList() {
        createScoredLead();

        Test.startTest();
        List<Lead> result = LeadController.getLeadList(LeadConstants.CATEGORY_COLD, 50);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Cold リードが1件返るはず');
    }

    /**
     * カテゴリ空（「All」）では全カテゴリのリードが返ることを検証する。
     */
    @isTest
    static void testGetLeadListAll() {
        List<Lead> leads = TestDataFactory.createLeads(3);
        insert leads;
        leads[0].Score__c = 200; leads[0].Lead_Category__c = LeadConstants.CATEGORY_HOT;
        leads[1].Score__c = 60;  leads[1].Lead_Category__c = LeadConstants.CATEGORY_COLD;
        leads[2].Score__c = 30;  leads[2].Lead_Category__c = LeadConstants.CATEGORY_LOW;
        LeadTriggerHandler.bypassTrigger = true;
        update leads;
        LeadTriggerHandler.bypassTrigger = false;

        Test.startTest();
        List<Lead> result = LeadController.getLeadList('', 50); // 空文字 = All
        Test.stopTest();

        System.assertEquals(3, result.size(), 'All では全カテゴリ3件が返るはず');
        System.assertEquals(200, result[0].Score__c, 'スコア降順で先頭は200のはず');
    }

    /**
     * 検索を検証する。
     */
    @isTest
    static void testSearchLeads() {
        createScoredLead();

        Test.startTest();
        List<Lead> result = LeadController.searchLeads('Test Company');
        Test.stopTest();

        System.assertEquals(1, result.size(), '会社名検索で1件返るはず');
    }

    /**
     * スコア内訳の取得を検証する（属性70・他0・合計70）。
     */
    @isTest
    static void testGetScoreBreakdown() {
        Id leadId = createScoredLead();

        Test.startTest();
        Map<String, Decimal> breakdown = LeadController.getScoreBreakdown(leadId);
        Test.stopTest();

        System.assertEquals(70, breakdown.get('attribute'), '属性スコアは70のはず');
        System.assertEquals(0, breakdown.get('behavior'), '行動スコアは0のはず');
        System.assertEquals(0, breakdown.get('interest'), '興味スコアは0のはず');
        System.assertEquals(70, breakdown.get('total'), '合計は70のはず');
    }

    /**
     * スコア内訳: null Id は AuraHandledException を投げることを検証する。
     */
    @isTest
    static void testGetScoreBreakdownNullId() {
        Test.startTest();
        try {
            LeadController.getScoreBreakdown(null);
            System.assert(false, 'null Id では例外が投げられるはず');
        } catch (AuraHandledException e) {
            System.assert(true, '想定どおり AuraHandledException が投げられた');
        }
        Test.stopTest();
    }

    /**
     * スコア内訳: 存在しない Id では「見つかりません」例外（AuraHandledException）になることを検証する。
     */
    @isTest
    static void testGetScoreBreakdownNotFound() {
        Id leadId = createScoredLead();
        delete [SELECT Id FROM Lead WHERE Id = :leadId];

        Test.startTest();
        try {
            LeadController.getScoreBreakdown(leadId);
            System.assert(false, '存在しないリードでは例外が投げられるはず');
        } catch (AuraHandledException e) {
            System.assert(true, '想定どおり AuraHandledException が投げられた');
        }
        Test.stopTest();
    }

    /**
     * 興味一覧の取得を検証する（レベル降順）。
     */
    @isTest
    static void testGetInterests() {
        Id leadId = createScoredLead();
        insert new List<Lead_Interest__c>{
            new Lead_Interest__c(Lead__c = leadId, Interest_Topic__c = 'AI 活用',
                Interest_Level__c = 30, Detected_Date__c = Date.today(), Source__c = 'T'),
            new Lead_Interest__c(Lead__c = leadId, Interest_Topic__c = '業務効率化',
                Interest_Level__c = 80, Detected_Date__c = Date.today(), Source__c = 'T')
        };

        Test.startTest();
        List<Lead_Interest__c> result = LeadController.getInterests(leadId);
        Test.stopTest();

        System.assertEquals(2, result.size(), '興味は2件返るはず');
        System.assertEquals(80, result[0].Interest_Level__c,
            'レベル降順で先頭は80のはず');
    }

    /**
     * 興味一覧: null Id は AuraHandledException を投げることを検証する。
     */
    @isTest
    static void testGetInterestsNullId() {
        Test.startTest();
        try {
            LeadController.getInterests(null);
            System.assert(false, 'null Id では例外が投げられるはず');
        } catch (AuraHandledException e) {
            System.assert(true, '想定どおり AuraHandledException が投げられた');
        }
        Test.stopTest();
    }

    /**
     * スコア再計算を検証する（属性のみ70が反映される）。
     */
    @isTest
    static void testRecalculateScore() {
        Id leadId = createScoredLead();
        // 一旦スコアをクリアしてから再計算で復元されることを確認する
        LeadTriggerHandler.bypassTrigger = true;
        update new Lead(Id = leadId, Score__c = 0, Lead_Category__c = LeadConstants.CATEGORY_LOW);
        LeadTriggerHandler.bypassTrigger = false;

        Test.startTest();
        LeadController.recalculateScore(leadId);
        Test.stopTest();

        Lead result = [SELECT Score__c, Lead_Category__c FROM Lead WHERE Id = :leadId];
        System.assertEquals(70, result.Score__c, '再計算で属性70が復元されるはず');
        System.assertEquals(LeadConstants.CATEGORY_COLD, result.Lead_Category__c,
            '70点は Cold のはず');
    }

    /**
     * 再計算: null Id は AuraHandledException を投げることを検証する。
     */
    @isTest
    static void testRecalculateScoreNullId() {
        Test.startTest();
        try {
            LeadController.recalculateScore(null);
            System.assert(false, 'null Id では例外が投げられるはず');
        } catch (AuraHandledException e) {
            System.assert(true, '想定どおり AuraHandledException が投げられた');
        }
        Test.stopTest();
    }

    /**
     * アクセス権限が無いユーザーでは、各メソッドが内部例外を捕捉して
     * AuraHandledException にラップして返すこと（catch ブロック）を検証する。
     * 最小アクセスユーザーでは WITH SECURITY_ENFORCED クエリが失敗するため、
     * すべての公開メソッドが AuraHandledException を投げるはず。
     */
    @isTest
    static void testMethodsThrowAuraHandledWithoutAccess() {
        Id leadId = createScoredLead();
        // User（setup オブジェクト）の DML は MIXED_DML 回避のため runAs 内で行う
        User minUser = buildMinimumAccessUser();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert minUser;
        }

        System.runAs(minUser) {
            Test.startTest();
            assertThrowsAura('getLeadList', new Map<String, Object>{ 'category' => LeadConstants.CATEGORY_COLD });
            assertThrowsAura('searchLeads', null);
            assertThrowsAura('getScoreBreakdown', new Map<String, Object>{ 'leadId' => leadId });
            assertThrowsAura('getInterests', new Map<String, Object>{ 'leadId' => leadId });
            assertThrowsAura('recalculateScore', new Map<String, Object>{ 'leadId' => leadId });
            Test.stopTest();
        }
    }

    /**
     * 指定メソッドが AuraHandledException を投げることを確認するヘルパー。
     */
    private static void assertThrowsAura(String methodName, Map<String, Object> params) {
        Boolean threw = false;
        try {
            if (methodName == 'getLeadList') {
                LeadController.getLeadList((String) params.get('category'), 50);
            } else if (methodName == 'searchLeads') {
                LeadController.searchLeads('Test');
            } else if (methodName == 'getScoreBreakdown') {
                LeadController.getScoreBreakdown((Id) params.get('leadId'));
            } else if (methodName == 'getInterests') {
                LeadController.getInterests((Id) params.get('leadId'));
            } else if (methodName == 'recalculateScore') {
                LeadController.recalculateScore((Id) params.get('leadId'));
            }
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, methodName + ' はアクセス権限不足で AuraHandledException を投げるはず');
    }

    /**
     * 最小アクセス権限のユーザーを生成する（未 insert）。
     */
    private static User buildMinimumAccessUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        String unique = 'minacc' + System.now().getTime();
        return new User(
            Alias = 'minacc',
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
}
