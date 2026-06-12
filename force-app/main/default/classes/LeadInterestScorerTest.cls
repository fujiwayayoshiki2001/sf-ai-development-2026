/**
 * LeadInterestScorer の単体テスト。
 *
 * 興味スコア（Lead_Interest__c の Interest_Level__c × トピック重みを合算、上限 80）を検証する。
 * 重みは Lead_Scoring_Config__mdt（Score_Type='Interest'）に依存する:
 *   'AI 活用'=1.5 / 'データ統合'=1.5 / '業務効率化'=1.0 など。
 *
 * 検証観点: ポジティブ / 複数トピック合算 / 上限 / 空トピックのスキップ /
 *           興味なし / null・空 / バルク(200件)。
 */
@isTest
private class LeadInterestScorerTest {

    private static final String TOPIC_AI = 'AI 活用';          // 重み 1.5
    private static final String TOPIC_EFFICIENCY = '業務効率化'; // 重み 1.0

    /**
     * 既定リードを1件 insert して Id を返す。
     * （Lead 重複ルールを避けるため @TestSetup は使わず、各テストで個別生成する）
     */
    private static Id createLeadId() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        return leads[0].Id;
    }

    private static Lead_Interest__c interest(Id leadId, String topic, Decimal level) {
        return new Lead_Interest__c(
            Lead__c = leadId,
            Interest_Topic__c = topic,
            Interest_Level__c = level,
            Detected_Date__c = Date.today(),
            Source__c = 'Test'
        );
    }

    /**
     * 単一の興味（AI 活用・レベル20）→ 20 × 1.5 = 30。
     */
    @isTest
    static void testCalculateSingle() {
        Id leadId = createLeadId();
        insert interest(leadId, TOPIC_AI, 20);

        Test.startTest();
        Decimal score = LeadInterestScorer.calculate(leadId);
        Test.stopTest();

        System.assertEquals(30, score, 'AI 活用 レベル20 × 1.5 = 30 のはず');
    }

    /**
     * 複数トピックは単純合算されることを検証する。
     * AI 活用(10×1.5=15) + 業務効率化(20×1.0=20) = 35。
     */
    @isTest
    static void testMultipleInterests() {
        Id leadId = createLeadId();
        insert new List<Lead_Interest__c>{
            interest(leadId, TOPIC_AI, 10),
            interest(leadId, TOPIC_EFFICIENCY, 20)
        };

        Test.startTest();
        Decimal score = LeadInterestScorer.calculate(leadId);
        Test.stopTest();

        System.assertEquals(35, score, 'AI(15) + 業務効率化(20) = 35 のはず');
    }

    /**
     * 上限（INTEREST_MAX_SCORE=80）で頭打ちになることを検証する。
     * AI 活用 レベル100 × 1.5 = 150 → 80 にキャップ。
     */
    @isTest
    static void testMaxCap() {
        Id leadId = createLeadId();
        insert interest(leadId, TOPIC_AI, 100);

        Test.startTest();
        Decimal score = LeadInterestScorer.calculate(leadId);
        Test.stopTest();

        System.assertEquals(
            LeadConstants.INTEREST_MAX_SCORE, score,
            '150 は上限 80 にキャップされるはず'
        );
    }

    /**
     * 興味スコアがリード単位で正しく分離されることを検証する。
     * 興味を付与したリードのみ加点され、別リードは 0 のまま。
     */
    @isTest
    static void testInterestIsolatedPerLead() {
        List<Lead> leads = TestDataFactory.createLeads(2);
        insert leads;
        insert interest(leads[0].Id, TOPIC_AI, 20); // 30 点

        Test.startTest();
        Map<Id, Decimal> scores = LeadInterestScorer.calculateBulk(
            new Map<Id, Lead>(leads).keySet()
        );
        Test.stopTest();

        System.assertEquals(30, scores.get(leads[0].Id), '興味を持つリードは30のはず');
        System.assertEquals(0, scores.get(leads[1].Id), '興味を持たないリードは0のはず');
    }

    /**
     * 興味レコードが無いリードはスコア 0 であることを検証する。
     */
    @isTest
    static void testNoInterests() {
        Id leadId = createLeadId();

        Test.startTest();
        Map<Id, Decimal> scores = LeadInterestScorer.calculateBulk(new Set<Id>{ leadId });
        Test.stopTest();

        System.assertEquals(0, scores.get(leadId), '興味が無いリードは 0 のはず');
    }

    /**
     * null / 空集合 / null Id に対するガードを検証する。
     */
    @isTest
    static void testNullAndEmptyGuards() {
        Test.startTest();
        System.assertEquals(0, LeadInterestScorer.calculateBulk(null).size(),
            'null 集合は空 Map のはず');
        System.assertEquals(0, LeadInterestScorer.calculateBulk(new Set<Id>()).size(),
            '空集合は空 Map のはず');
        System.assertEquals(0, LeadInterestScorer.calculate(null),
            'null Id のスコアは 0 のはず');
        Test.stopTest();
    }

    /**
     * バルク（200件）で全リードが計算されることを検証する。
     * 各リードに AI 活用 レベル20（=30）を1件付与。
     */
    @isTest
    static void testBulk() {
        List<Lead> leads = TestDataFactory.createLeads(200);
        insert leads;

        List<Lead_Interest__c> interests = new List<Lead_Interest__c>();
        for (Lead lead : leads) {
            interests.add(interest(lead.Id, TOPIC_AI, 20));
        }

        Test.startTest();
        insert interests;
        Map<Id, Decimal> scores = LeadInterestScorer.calculateBulk(
            new Map<Id, Lead>(leads).keySet()
        );
        Test.stopTest();

        System.assertEquals(200, scores.size(), '200件すべてが計算されるはず');
        for (Id leadId : scores.keySet()) {
            System.assertEquals(30, scores.get(leadId),
                '全件が AI 活用 レベル20（=30）のはず');
        }
    }
}
