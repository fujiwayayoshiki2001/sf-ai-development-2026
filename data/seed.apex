/**
 * Phase 8 シードデータ投入スクリプト（冪等・Anonymous Apex / 時間減衰なし）
 *
 * 投入内容:
 *   - シードリード 50件（業界/規模/役職/ソースを多様化し、カテゴリを Hot/Warm/Cold/Low に分散）
 *   - キャンペーン 6個（Webinar / Trade Show / Email / White Paper / Demo Request）+ 英語ステータス
 *   - CampaignMember 約80件（すべて投入日付。時間減衰は使わない）
 *   - Lead_Interest__c 約80件（10トピックを均等分散、レベル 30-100）
 *
 * スコアはトリガー（afterInsert / CampaignMemberTrigger / LeadInterestTrigger）が自動計算する。
 * 時間減衰はシードでは再現しない（CreatedDate は投入日 = 減衰係数 1.0）。
 * 減衰ロジックは LeadBehaviorScorerTest（Test.setCreatedDate）で動作実証済み。
 *
 * 冪等性: 先頭で既存のシードデータ（タグ付き）を削除してから再生成する。
 * 追加の手動設定・権限は不要。
 *
 * カテゴリ設計（属性 + 行動 + 興味 = 合計）:
 *   Hot  (12件): 属性85 + 行動80(Demo50+Webinar30) + 興味80(上限) = 245
 *   Warm (18件): 属性60 + 行動30(展示会25+メール5) + 興味80(上限) = 170
 *   Cold (14件): 属性50 + (行動25 または 興味30-45) = 75〜95
 *   Low  ( 6件): 属性25 + (行動10 または なし) = 25〜35
 */
final String SEED_TAG = 'SEED_DATA_PHASE8';
final String SEED_EMAIL = 'seed%@example.com'; // Lead はメールでマーク（Description は textarea でフィルタ不可）

// ============================================================
// 0) 既存シードデータのクリーンアップ（冪等性）
// ============================================================
delete [SELECT Id FROM Lead_Interest__c WHERE Source__c = :SEED_TAG];
delete [SELECT Id FROM Lead WHERE Email LIKE :SEED_EMAIL]; // 子の CampaignMember も連動削除
delete [SELECT Id FROM Campaign WHERE Name LIKE 'Seed:%'];

// ============================================================
// 1) キャンペーン + 英語 CampaignMemberStatus
// ============================================================
Map<String, Campaign> camp = new Map<String, Campaign>();
camp.put('webinar',    new Campaign(Name = 'Seed: 年次ウェビナー2026',  Type = 'Webinar',      IsActive = true));
camp.put('conf',       new Campaign(Name = 'Seed: 顧客カンファレンス',   Type = 'Webinar',      IsActive = true));
camp.put('tradeshow',  new Campaign(Name = 'Seed: テクノロジー展示会',   Type = 'Trade Show',   IsActive = true));
camp.put('email',      new Campaign(Name = 'Seed: メールニュースレター', Type = 'Email',        IsActive = true));
camp.put('whitepaper', new Campaign(Name = 'Seed: ホワイトペーパーDL',   Type = 'White Paper',  IsActive = true));
camp.put('demo',       new Campaign(Name = 'Seed: デモ申込キャンペーン', Type = 'Demo Request', IsActive = true));
insert camp.values();

Map<String, List<String>> statusByCamp = new Map<String, List<String>>{
    'webinar'    => new List<String>{ 'Registered', 'Attended' },
    'conf'       => new List<String>{ 'Registered', 'Attended' },
    'tradeshow'  => new List<String>{ 'Registered', 'Visited' },
    'email'      => new List<String>{ 'Sent', 'Responded' },
    'whitepaper' => new List<String>{ 'Downloaded' },
    'demo'       => new List<String>{ 'Submitted' }
};
Set<String> respondedLabels = new Set<String>{ 'Attended', 'Responded', 'Visited', 'Downloaded', 'Submitted' };
List<CampaignMemberStatus> statuses = new List<CampaignMemberStatus>();
for (String key : statusByCamp.keySet()) {
    Integer sortOrder = 10;
    for (String label : statusByCamp.get(key)) {
        statuses.add(new CampaignMemberStatus(
            CampaignId = camp.get(key).Id, Label = label, SortOrder = sortOrder++,
            HasResponded = respondedLabels.contains(label)
        ));
    }
}
insert statuses;

// ============================================================
// 2) リード 50件（4グループに分けてカテゴリを分散）
// ============================================================
List<String> SURNAMES = new List<String>{
    '佐藤','鈴木','高橋','田中','伊藤','渡辺','山本','中村','小林','加藤',
    '吉田','山田','佐々木','山口','松本','井上','木村','林','斎藤','清水',
    '山崎','森','池田','橋本','阿部','石川','前田','藤田','後藤','岡田',
    '長谷川','村上','近藤','石井','坂本','遠藤','青木','藤井','西村','福田',
    '太田','三浦','藤原','岡本','松田','中川','中野','原田','小川','竹内'
};
List<String> GIVENNAMES = new List<String>{
    '太郎','花子','一郎','美咲','健太','由美','大樹','彩','翔','麻衣'
};
List<String> COMPANY_SUFFIX = new List<String>{
    '株式会社','商事株式会社','工業株式会社','システムズ株式会社','ホールディングス','製作所','電機株式会社','物産株式会社'
};
List<String> COMPANY_BASE = new List<String>{
    '日本','東京','大和','富士','旭','明星','明和','光洋','三葉','常磐'
};

// グループ境界: 0-11=Hot(12) / 12-29=Warm(18) / 30-43=Cold(14) / 44-49=Low(6)
final Integer HOT_END = 12, WARM_END = 30, COLD_END = 44;

List<Lead> leads = new List<Lead>();
for (Integer i = 0; i < 50; i++) {
    String company = COMPANY_BASE[Math.mod(i, COMPANY_BASE.size())]
        + COMPANY_SUFFIX[Math.mod(i, COMPANY_SUFFIX.size())] + ' ' + i;

    Lead l = new Lead(
        FirstName = GIVENNAMES[Math.mod(i, GIVENNAMES.size())],
        LastName = SURNAMES[i],
        Company = company,
        Email = 'seed' + String.valueOf(i).leftPad(2, '0') + '@example.com',
        Description = SEED_TAG
    );

    if (i < HOT_END) {
        // Hot: 属性85（Tech 15 / 2000名 20 / CEO 30 / Webinar 20）
        l.Industry = 'Technology'; l.NumberOfEmployees = 2000;
        l.Title = 'CEO'; l.LeadSource = 'Webinar';
    } else if (i < WARM_END) {
        // Warm: 属性60（Tech 15 / 1500名 20 / Manager 15 / Web 10）
        l.Industry = 'Technology'; l.NumberOfEmployees = 1500;
        l.Title = 'Sales Manager'; l.LeadSource = 'Web';
    } else if (i < COLD_END) {
        // Cold: 属性50（Tech 15 / 300名 10 / Manager 15 / Web 10）
        l.Industry = 'Technology'; l.NumberOfEmployees = 300;
        l.Title = 'Manager'; l.LeadSource = 'Web';
    } else {
        // Low: 属性25（業界/規模は加点なし / Manager 15 / Web 10）
        l.Industry = 'Agriculture'; l.NumberOfEmployees = 5;
        l.Title = 'Manager'; l.LeadSource = 'Web';
    }
    leads.add(l);
}
insert leads; // afterInsert で属性スコアが計算される

// ============================================================
// 3) Lead_Interest__c（10トピック均等分散・レベル 30-100）
//    レベルはグループで制御し、トピックは全体で巡回して均等に分散させる。
// ============================================================
List<String> TOPICS = new List<String>{
    'データ統合','業務効率化','セキュリティ強化','コスト削減','DX 推進',
    '既存システム置き換え','クラウド移行','自動化','AI 活用','ガバナンス強化'
};
List<Integer> HOT_LEVELS  = new List<Integer>{ 80, 100, 70 }; // Hot: 3件（上限80で頭打ち）
List<Integer> WARM_LEVELS = new List<Integer>{ 45, 60 };      // Warm: 2件（上限80で頭打ち）
final Integer COLD_LEVEL  = 30;                               // Cold-Y: 1件（最大 30×1.5=45）

List<Lead_Interest__c> interests = new List<Lead_Interest__c>();
Integer ti = 0; // トピック巡回インデックス（10種を均等に消費）
for (Integer i = 0; i < leads.size(); i++) {
    List<Integer> levelsForLead = new List<Integer>();
    if (i < HOT_END) {
        levelsForLead = HOT_LEVELS;                 // 3件
    } else if (i < WARM_END) {
        levelsForLead = WARM_LEVELS;                // 2件
    } else if (i < COLD_END && Math.mod(i, 2) == 1) {
        levelsForLead = new List<Integer>{ COLD_LEVEL }; // Cold-Y のみ 1件
    }
    // Cold-X / Low は興味なし（行動または属性のみでカテゴリを維持）

    for (Integer k = 0; k < levelsForLead.size(); k++) {
        interests.add(new Lead_Interest__c(
            Lead__c = leads[i].Id,
            Interest_Topic__c = TOPICS[Math.mod(ti, TOPICS.size())],
            Interest_Level__c = levelsForLead[k],
            Detected_Date__c = Date.today().addDays(-Math.mod(i, 60)),
            Source__c = SEED_TAG,
            Notes__c = 'Phase8 シードデータ'
        ));
        ti++;
    }
}
insert interests; // LeadInterestTrigger で興味スコアが再計算される

// ============================================================
// 4) CampaignMember（約80件・すべて投入日付 = 減衰なし）
// ============================================================
List<CampaignMember> members = new List<CampaignMember>();
for (Integer i = 0; i < leads.size(); i++) {
    Id leadId = leads[i].Id;
    if (i < HOT_END) {
        // Hot: 行動80（Demo/Submitted 50 + Webinar/Attended 30）
        members.add(new CampaignMember(CampaignId = camp.get('demo').Id,    LeadId = leadId, Status = 'Submitted'));
        members.add(new CampaignMember(CampaignId = camp.get('webinar').Id, LeadId = leadId, Status = 'Attended'));
    } else if (i < WARM_END) {
        // Warm: 行動30（Trade Show/Visited 25 + Email/Responded 5）
        members.add(new CampaignMember(CampaignId = camp.get('tradeshow').Id, LeadId = leadId, Status = 'Visited'));
        members.add(new CampaignMember(CampaignId = camp.get('email').Id,     LeadId = leadId, Status = 'Responded'));
    } else if (i < COLD_END) {
        if (Math.mod(i, 2) == 0) {
            // Cold-X: 行動25（Webinar/Registered 10 + White Paper/Downloaded 15）、興味なし → 75
            members.add(new CampaignMember(CampaignId = camp.get('webinar').Id,    LeadId = leadId, Status = 'Registered'));
            members.add(new CampaignMember(CampaignId = camp.get('whitepaper').Id, LeadId = leadId, Status = 'Downloaded'));
        }
        // Cold-Y（i%2==1）は興味のみ（行動なし）
    } else {
        if (Math.mod(i, 2) == 0) {
            // Low の半数: Webinar/Registered 10 のみ → 35
            members.add(new CampaignMember(CampaignId = camp.get('conf').Id, LeadId = leadId, Status = 'Registered'));
        }
        // 残りは行動・興味なし → 25
    }
}
insert members; // CampaignMemberTrigger で行動スコアが再計算される

System.debug('SEED_DONE leads=' + leads.size()
    + ' interests=' + interests.size() + ' members=' + members.size());
