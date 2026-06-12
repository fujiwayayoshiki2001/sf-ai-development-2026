/**
 * LeadAttributeScorer の単体テスト。
 *
 * 属性スコア（業界・規模・役職・リードソースの重み合算）を検証する。
 * 重みは Lead_Scoring_Config__mdt（Score_Type='Attribute'）の値に依存する:
 *   業界: Technology=15 / Manufacturing=15 / Financial Services=10
 *   規模: 1000+=20 / 100-999=10 / 10-99=5
 *   役職: C-level=30 / VP=25 / Manager=15
 *   ソース: Webinar=20 / Web=10 / Trade Show=15
 *
 * 検証観点: ポジティブ / 各重みの境界 / null・空ガード / バルク(200件)。
 */
@isTest
private class LeadAttributeScorerTest {

    /**
     * TestDataFactory の既定リード（Tech / 1000名 / Manager / Webinar）の属性スコアを検証する。
     * 期待値: 15 + 20 + 15 + 20 = 70。
     */
    @isTest
    static void testDefaultLeadScore() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        List<Lead> queried = [
            SELECT Id, Industry, NumberOfEmployees, Title, LeadSource FROM Lead
        ];

        Test.startTest();
        Map<Id, Decimal> scores = LeadAttributeScorer.calculateBulk(queried);
        Test.stopTest();

        System.assertEquals(
            70,
            scores.get(leads[0].Id),
            '既定リードの属性スコアは Tech15+規模20+Manager15+Webinar20=70 のはず'
        );
    }

    /**
     * 業界・規模・役職・ソースの各重みと境界（規模 1000/100/10、役職 C/VP/Manager/該当なし）を検証する。
     */
    @isTest
    static void testIndividualFactorWeights() {
        List<Lead> leads = new List<Lead>{
            // Finance(10) + 規模50→Small(5) + CEO→C-level(30) + Web(10) = 55
            new Lead(LastName = 'Finance', Company = 'Co A',
                     Industry = 'Financial Services', NumberOfEmployees = 50,
                     Title = 'CEO', LeadSource = 'Web'),
            // Manufacturing(15) + 規模500→Medium(10) + VP(25) + Trade Show(15) = 65
            new Lead(LastName = 'Manuf', Company = 'Co B',
                     Industry = 'Manufacturing', NumberOfEmployees = 500,
                     Title = 'VP of Sales', LeadSource = 'Trade Show'),
            // 該当業界なし + 規模9→0 + 役職該当なし + ソースなし = 0
            new Lead(LastName = 'None', Company = 'Co C',
                     Industry = 'Agriculture', NumberOfEmployees = 9,
                     Title = 'Engineer', LeadSource = null)
        };
        insert leads;
        List<Lead> queried = [
            SELECT Id, Industry, NumberOfEmployees, Title, LeadSource FROM Lead
        ];

        Test.startTest();
        Map<Id, Decimal> scores = LeadAttributeScorer.calculateBulk(queried);
        Test.stopTest();

        System.assertEquals(55, scores.get(leads[0].Id),
            'Finance10+Small5+CEO30+Web10=55 のはず');
        System.assertEquals(65, scores.get(leads[1].Id),
            'Manuf15+Medium10+VP25+TradeShow15=65 のはず');
        System.assertEquals(0, scores.get(leads[2].Id),
            '該当する重みが無い場合は 0 のはず');
    }

    /**
     * 単一 Lead 用 calculate(Lead) が、バルク版と同じ結果を返すことを検証する。
     */
    @isTest
    static void testCalculateSingle() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        Lead queried = [
            SELECT Id, Industry, NumberOfEmployees, Title, LeadSource FROM Lead LIMIT 1
        ];

        Test.startTest();
        Decimal score = LeadAttributeScorer.calculate(queried);
        Test.stopTest();

        System.assertEquals(70, score, '単一計算でも既定リードは 70 のはず');
    }

    /**
     * null / 空リスト / Id が null のリード に対するガードを検証する。
     */
    @isTest
    static void testNullAndEmptyGuards() {
        Test.startTest();
        System.assertEquals(0, LeadAttributeScorer.calculateBulk(null).size(),
            'null リストは空 Map を返すはず');
        System.assertEquals(0, LeadAttributeScorer.calculateBulk(new List<Lead>()).size(),
            '空リストは空 Map を返すはず');
        // Id が null のリードはスキップされる
        Map<Id, Decimal> skipMap = LeadAttributeScorer.calculateBulk(
            new List<Lead>{ new Lead(LastName = 'NoId', Company = 'X', Industry = 'Technology') }
        );
        System.assertEquals(0, skipMap.size(), 'Id が null のリードはスキップされ空 Map のはず');

        System.assertEquals(0, LeadAttributeScorer.calculate(null),
            'null リードのスコアは 0 のはず');
        System.assertEquals(0, LeadAttributeScorer.calculate(new Lead(LastName = 'NoId')),
            'Id が null のリードのスコアは 0 のはず');
        Test.stopTest();
    }

    /**
     * バルク（200件）で全リードが計算され、件数とスコアが正しいことを検証する。
     */
    @isTest
    static void testBulk() {
        List<Lead> leads = TestDataFactory.createLeads(200);
        insert leads;
        List<Lead> queried = [
            SELECT Id, Industry, NumberOfEmployees, Title, LeadSource FROM Lead
        ];

        Test.startTest();
        Map<Id, Decimal> scores = LeadAttributeScorer.calculateBulk(queried);
        Test.stopTest();

        System.assertEquals(200, scores.size(), '200件すべてが計算されるはず');
        for (Id leadId : scores.keySet()) {
            System.assertEquals(70, scores.get(leadId),
                '全件が既定リード（属性スコア70）のはず');
        }
    }
}
