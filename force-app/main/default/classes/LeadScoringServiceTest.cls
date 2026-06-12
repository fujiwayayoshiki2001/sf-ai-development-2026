/**
 * LeadScoringService の単体テスト。
 *
 * 3軸スコア（属性・行動・興味）の統括計算と Lead への反映、カテゴリ判定を検証する。
 *
 * 検証観点: 3軸合算とカテゴリ反映 / カテゴリ閾値の境界(180/100/50) /
 *           単一計算 / 存在しない Id / null・空ガード / バルク(200件)。
 */
@isTest
private class LeadScoringServiceTest {

    /**
     * 既定リードを1件 insert して Id を返す。
     */
    private static Id createLeadId() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        return leads[0].Id;
    }

    /**
     * Webinar キャンペーンを作り 'Attended'(=30) ステータスを追加して返す。
     */
    private static Campaign createAttendedCampaign() {
        Campaign campaign = new Campaign(Name = 'Score WB', Type = 'Webinar', IsActive = true);
        insert campaign;
        insert new CampaignMemberStatus(
            CampaignId = campaign.Id, Label = 'Attended', SortOrder = 10, HasResponded = true
        );
        return campaign;
    }

    /**
     * 3軸を合算して Lead に反映し、カテゴリが Hot になることを検証する。
     * 属性70 + 興味80(キャップ) + 行動30 = 180 → Hot。
     */
    @isTest
    static void testCalculateScoresFull() {
        Id leadId = createLeadId();

        // 興味: AI 活用 レベル100 × 1.5 = 150 → 80 にキャップ
        insert new Lead_Interest__c(
            Lead__c = leadId, Interest_Topic__c = 'AI 活用',
            Interest_Level__c = 100, Detected_Date__c = Date.today(), Source__c = 'Test'
        );
        // 行動: Webinar_Attended = 30（当日・減衰なし）
        Campaign campaign = createAttendedCampaign();
        insert new CampaignMember(CampaignId = campaign.Id, LeadId = leadId, Status = 'Attended');

        Test.startTest();
        LeadScoringService.calculateScores(new Set<Id>{ leadId });
        Test.stopTest();

        Lead result = [
            SELECT Attribute_Score__c, Behavior_Score__c, Interest_Score__c,
                   Score__c, Lead_Category__c, Score_Last_Calculated__c
            FROM Lead WHERE Id = :leadId
        ];
        System.assertEquals(70, result.Attribute_Score__c, '属性スコアは70のはず');
        System.assertEquals(80, result.Interest_Score__c, '興味スコアは上限80のはず');
        System.assertEquals(30, result.Behavior_Score__c, '行動スコアは30のはず');
        System.assertEquals(180, result.Score__c, '合計は70+80+30=180のはず');
        System.assertEquals(LeadConstants.CATEGORY_HOT, result.Lead_Category__c,
            '180点は Hot のはず');
        System.assertNotEquals(null, result.Score_Last_Calculated__c,
            '計算日時がセットされるはず');
    }

    /**
     * 単一 Lead 用 calculateScore(Id)。属性のみ70 → Cold(50-99)。
     */
    @isTest
    static void testCalculateScoreSingle() {
        Id leadId = createLeadId();

        Test.startTest();
        LeadScoringService.calculateScore(leadId);
        Test.stopTest();

        Lead result = [SELECT Score__c, Lead_Category__c FROM Lead WHERE Id = :leadId];
        System.assertEquals(70, result.Score__c, '属性のみで70のはず');
        System.assertEquals(LeadConstants.CATEGORY_COLD, result.Lead_Category__c,
            '70点は Cold のはず');
    }

    /**
     * カテゴリ判定の境界値（180/100/50）と null を検証する。
     */
    @isTest
    static void testDetermineCategoryBoundaries() {
        Test.startTest();
        System.assertEquals(LeadConstants.CATEGORY_HOT,
            LeadScoringService.determineCategory(300), '300は Hot');
        System.assertEquals(LeadConstants.CATEGORY_HOT,
            LeadScoringService.determineCategory(180), '180(境界)は Hot');
        System.assertEquals(LeadConstants.CATEGORY_WARM,
            LeadScoringService.determineCategory(179), '179は Warm');
        System.assertEquals(LeadConstants.CATEGORY_WARM,
            LeadScoringService.determineCategory(100), '100(境界)は Warm');
        System.assertEquals(LeadConstants.CATEGORY_COLD,
            LeadScoringService.determineCategory(99), '99は Cold');
        System.assertEquals(LeadConstants.CATEGORY_COLD,
            LeadScoringService.determineCategory(50), '50(境界)は Cold');
        System.assertEquals(LeadConstants.CATEGORY_LOW,
            LeadScoringService.determineCategory(49), '49は Low');
        System.assertEquals(LeadConstants.CATEGORY_LOW,
            LeadScoringService.determineCategory(0), '0は Low');
        System.assertEquals(LeadConstants.CATEGORY_LOW,
            LeadScoringService.determineCategory(null), 'null は Low');
        Test.stopTest();
    }

    /**
     * 存在しない（削除済み）Id を渡しても例外なく早期 return することを検証する。
     */
    @isTest
    static void testNonExistentLead() {
        Id leadId = createLeadId();
        delete [SELECT Id FROM Lead WHERE Id = :leadId];

        Test.startTest();
        LeadScoringService.calculateScores(new Set<Id>{ leadId }); // 例外が出ないこと
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Id = :leadId],
            '対象リードは存在しないはず');
    }

    /**
     * null / 空集合 / null Id のガードを検証する（例外なく何もしない）。
     */
    @isTest
    static void testNullAndEmptyGuards() {
        Test.startTest();
        LeadScoringService.calculateScores(null);
        LeadScoringService.calculateScores(new Set<Id>());
        LeadScoringService.calculateScore(null);
        Test.stopTest();
        // 例外が発生しないことが検証内容
        System.assert(true, 'ガードにより例外なく完了するはず');
    }

    /**
     * バルク（200件）で全リードにスコア・カテゴリが反映されることを検証する。
     */
    @isTest
    static void testBulk() {
        List<Lead> leads = TestDataFactory.createLeads(200);
        insert leads;
        Set<Id> leadIds = new Map<Id, Lead>(leads).keySet();

        Test.startTest();
        LeadScoringService.calculateScores(leadIds);
        Test.stopTest();

        List<Lead> results = [
            SELECT Score__c, Lead_Category__c, Score_Last_Calculated__c
            FROM Lead WHERE Id IN :leadIds
        ];
        System.assertEquals(200, results.size(), '200件すべて取得できるはず');
        for (Lead lead : results) {
            System.assertEquals(70, lead.Score__c, '属性のみで全件70のはず');
            System.assertEquals(LeadConstants.CATEGORY_COLD, lead.Lead_Category__c,
                '70点は全件 Cold のはず');
            System.assertNotEquals(null, lead.Score_Last_Calculated__c,
                '計算日時が全件セットされるはず');
        }
    }
}
