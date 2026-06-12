/**
 * LeadBehaviorScorer の単体テスト。
 *
 * 行動スコア（CampaignMember を Campaign.Type + '_' + Status のキーで重み付けし、
 * 時間減衰 0.95^経過日数 を掛けて合算、上限 120）を検証する。
 *
 * 重みは Lead_Scoring_Config__mdt（Score_Type='Behavior'）に依存する:
 *   Webinar_Registered=10 / Webinar_Attended=30 など。
 *
 * このプロジェクトの組織では CampaignMember の既定ステータスが日本語（送信／レスポンスあり）の
 * ため、テストでは Campaign に英語ラベルの CampaignMemberStatus を明示的に追加し、
 * 設定キーと一致させる。
 *
 * 検証観点: ポジティブ / 時間減衰 / 上限 / キー不一致 / メンバー無し / null・空 / バルク(200件)。
 */
@isTest
private class LeadBehaviorScorerTest {

    private static final String STATUS_REGISTERED = 'Registered'; // Webinar_Registered=10
    private static final String STATUS_ATTENDED   = 'Attended';   // Webinar_Attended=30

    /**
     * 既定リードを1件 insert して Id を返す。
     * （Lead 重複ルールを避けるため @TestSetup は使わず、各テストで個別生成する）
     */
    private static Id createLeadId() {
        List<Lead> leads = TestDataFactory.createLeads(1);
        insert leads;
        return leads[0].Id;
    }

    /**
     * Webinar キャンペーンを作成し、指定ラベルの CampaignMemberStatus を追加して返す。
     */
    private static Campaign createWebinarCampaign(String name, String statusLabel) {
        Campaign campaign = new Campaign(Name = name, Type = 'Webinar', IsActive = true);
        insert campaign;
        insert new CampaignMemberStatus(
            CampaignId = campaign.Id,
            Label = statusLabel,
            SortOrder = 10,
            HasResponded = false
        );
        return campaign;
    }

    /**
     * 指定リードを指定キャンペーンに、指定ステータスで参加させる。
     */
    private static CampaignMember addMember(Id campaignId, Id leadId, String status) {
        CampaignMember member = new CampaignMember(
            CampaignId = campaignId, LeadId = leadId, Status = status
        );
        insert member;
        return member;
    }

    /**
     * 当日参加（減衰なし）の Webinar_Registered メンバー1件 → スコア 10。
     */
    @isTest
    static void testCalculateSingle() {
        Id leadId = createLeadId();
        Campaign campaign = createWebinarCampaign('WB Reg', STATUS_REGISTERED);
        addMember(campaign.Id, leadId, STATUS_REGISTERED);

        Test.startTest();
        Decimal score = LeadBehaviorScorer.calculate(leadId);
        Test.stopTest();

        System.assertEquals(10, score,
            '当日参加の Webinar_Registered は減衰なしで 10 のはず');
    }

    /**
     * 10日前の参加に時間減衰（0.95^10）が掛かることを検証する。
     */
    @isTest
    static void testTimeDecay() {
        Id leadId = createLeadId();
        Campaign campaign = createWebinarCampaign('WB Decay', STATUS_REGISTERED);
        CampaignMember member = addMember(campaign.Id, leadId, STATUS_REGISTERED);
        // CreatedDate を10日前に設定して減衰を再現する
        Test.setCreatedDate(member.Id, System.now().addDays(-10));

        Test.startTest();
        Decimal score = LeadBehaviorScorer.calculate(leadId);
        Test.stopTest();

        Decimal expected = 10 * Math.pow(LeadConstants.DECAY_FACTOR.doubleValue(), 10);
        System.assert(
            Math.abs(score - expected) < 0.01,
            '10日減衰後のスコアは ' + expected + ' 付近のはず。実際: ' + score
        );
        System.assert(score < 10, '減衰により当日値(10)より小さいはず: ' + score);
    }

    /**
     * 上限（BEHAVIOR_MAX_SCORE=120）で頭打ちになることを検証する。
     * Webinar_Attended(30) のメンバーを5キャンペーン分 → 150 → 120 にキャップ。
     */
    @isTest
    static void testMaxCap() {
        Id leadId = createLeadId();
        for (Integer i = 0; i < 5; i++) {
            Campaign campaign = createWebinarCampaign('WB Cap ' + i, STATUS_ATTENDED);
            addMember(campaign.Id, leadId, STATUS_ATTENDED);
        }

        Test.startTest();
        Decimal score = LeadBehaviorScorer.calculate(leadId);
        Test.stopTest();

        System.assertEquals(
            LeadConstants.BEHAVIOR_MAX_SCORE, score,
            '30×5=150 は上限 120 にキャップされるはず'
        );
    }

    /**
     * 設定キーに一致しないステータスは加点されない（スコア 0）ことを検証する。
     */
    @isTest
    static void testNoMatchingKey() {
        Id leadId = createLeadId();
        Campaign campaign = createWebinarCampaign('WB Unknown', 'Bounced'); // Webinar_Bounced は未設定
        addMember(campaign.Id, leadId, 'Bounced');

        Test.startTest();
        Decimal score = LeadBehaviorScorer.calculate(leadId);
        Test.stopTest();

        System.assertEquals(0, score, '設定に無いキーは加点されず 0 のはず');
    }

    /**
     * CampaignMember が1件も無いリードはスコア 0（0 で初期化）であることを検証する。
     */
    @isTest
    static void testNoMembers() {
        Id leadId = createLeadId();

        Test.startTest();
        Map<Id, Decimal> scores = LeadBehaviorScorer.calculateBulk(new Set<Id>{ leadId });
        Test.stopTest();

        System.assertEquals(0, scores.get(leadId),
            'メンバーが無いリードは 0 で初期化されるはず');
    }

    /**
     * null / 空集合 / null Id に対するガードを検証する。
     */
    @isTest
    static void testNullAndEmptyGuards() {
        Test.startTest();
        System.assertEquals(0, LeadBehaviorScorer.calculateBulk(null).size(),
            'null 集合は空 Map のはず');
        System.assertEquals(0, LeadBehaviorScorer.calculateBulk(new Set<Id>()).size(),
            '空集合は空 Map のはず');
        System.assertEquals(0, LeadBehaviorScorer.calculate(null),
            'null Id のスコアは 0 のはず');
        Test.stopTest();
    }

    /**
     * バルク（200件）で全リードが計算されることを検証する。
     * 各リードを1つの Webinar キャンペーンに Registered で参加させ、全件スコア10。
     */
    @isTest
    static void testBulk() {
        List<Lead> leads = TestDataFactory.createLeads(200);
        insert leads;
        Campaign campaign = createWebinarCampaign('WB Bulk', STATUS_REGISTERED);

        List<CampaignMember> members = new List<CampaignMember>();
        for (Lead lead : leads) {
            members.add(new CampaignMember(
                CampaignId = campaign.Id, LeadId = lead.Id, Status = STATUS_REGISTERED
            ));
        }

        Test.startTest();
        insert members;
        Map<Id, Decimal> scores = LeadBehaviorScorer.calculateBulk(
            new Map<Id, Lead>(leads).keySet()
        );
        Test.stopTest();

        System.assertEquals(200, scores.size(), '200件すべてが計算されるはず');
        for (Id leadId : scores.keySet()) {
            System.assertEquals(10, scores.get(leadId),
                '全件が当日 Webinar_Registered（10）のはず');
        }
    }
}
