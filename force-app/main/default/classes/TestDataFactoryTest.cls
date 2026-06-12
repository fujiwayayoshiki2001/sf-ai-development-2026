/**
 * TestDataFactory の動作を検証するテストクラス。
 * 各ファクトリメソッドが期待件数を返し、insert まで成功することを確認する。
 */
@isTest
private class TestDataFactoryTest {

    @isTest
    static void testCreateLeads() {
        Test.startTest();
        List<Lead> leads = TestDataFactory.createLeads(10);
        insert leads;
        Test.stopTest();

        System.assertEquals(10, leads.size(), '10件の Lead が生成されるはず');
        List<Lead> inserted = [SELECT Id, Company, Industry FROM Lead];
        System.assertEquals(10, inserted.size(), '10件すべて insert されるはず');
        System.assertEquals(
            LeadConstants.INDUSTRY_TECHNOLOGY,
            inserted[0].Industry,
            'Industry は定数値で設定されるはず'
        );
    }

    @isTest
    static void testCreateLeadsBulk() {
        Test.startTest();
        List<Lead> leads = TestDataFactory.createLeads(200);
        insert leads;
        Test.stopTest();

        System.assertEquals(200, leads.size(), 'バルク 200件が生成されるはず');
        System.assertEquals(200, [SELECT COUNT() FROM Lead], '200件すべて insert されるはず');
    }

    @isTest
    static void testCreateInterests() {
        List<Lead> leads = TestDataFactory.createLeads(3);
        insert leads;

        Test.startTest();
        List<Lead_Interest__c> interests = TestDataFactory.createInterests(leads, 4);
        insert interests;
        Test.stopTest();

        System.assertEquals(12, interests.size(), '3リード × 4件 = 12件のはず');
        for (Lead_Interest__c interest : interests) {
            System.assertNotEquals(null, interest.Lead__c, 'Lead__c が設定されるはず');
            System.assert(
                interest.Interest_Level__c >= 1 && interest.Interest_Level__c <= 100,
                'Interest_Level__c は 1〜100 の範囲のはず: ' + interest.Interest_Level__c
            );
        }
    }

    @isTest
    static void testCreateInterestsWithEmptyInput() {
        // ネガティブケース: 空・null 入力では空リストを返す
        System.assertEquals(
            0,
            TestDataFactory.createInterests(new List<Lead>(), 3).size(),
            '空リード入力では 0件のはず'
        );
        System.assertEquals(
            0,
            TestDataFactory.createInterests(null, 3).size(),
            'null 入力では 0件のはず'
        );
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        System.assertEquals(
            0,
            TestDataFactory.createInterests(leads, 0).size(),
            'perLead が 0 では 0件のはず'
        );
    }

    @isTest
    static void testCreateCampaignsAndMembers() {
        List<Lead> leads = TestDataFactory.createLeads(5);
        insert leads;

        Test.startTest();
        List<Campaign> campaigns = TestDataFactory.createCampaigns(2);
        insert campaigns;

        List<CampaignMember> members = TestDataFactory.createCampaignMembers(leads, campaigns);
        insert members;
        Test.stopTest();

        System.assertEquals(2, campaigns.size(), '2件の Campaign が生成されるはず');
        System.assertEquals(10, members.size(), '5リード × 2キャンペーン = 10件のはず');
        System.assertEquals(
            10,
            [SELECT COUNT() FROM CampaignMember],
            '10件すべて insert されるはず'
        );
    }

    @isTest
    static void testCreateCampaignMembersWithEmptyInput() {
        // ネガティブケース
        System.assertEquals(
            0,
            TestDataFactory.createCampaignMembers(null, null).size(),
            'null 入力では 0件のはず'
        );
        System.assertEquals(
            0,
            TestDataFactory.createCampaignMembers(new List<Lead>(), new List<Campaign>()).size(),
            '空リスト入力では 0件のはず'
        );
    }
}
