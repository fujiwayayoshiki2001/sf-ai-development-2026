/**
 * 商談化データ シードデータ投入スクリプト（冪等・Anonymous Apex）
 *
 * 機能1（カテゴリ別商談化率）・機能2（商談化トレンドグラフ）の動作確認用データを投入する。
 * 既存の data/seed.apex（SEED_DATA_PHASE8）とは完全に独立しており、互いに影響しない。
 *
 * 投入内容:
 *   - リード 40件（Hot/Warm/Cold/Low 各10件。属性・行動・興味の設計は seed.apex と同じ）
 *       Hot  : 属性85 + 行動80（Demo申込50+Webinar参加30） + 興味80（上限） = 245
 *       Warm : 属性60 + 行動30（展示会25+メール5）        + 興味80（上限） = 170
 *       Cold : 属性50 + 行動25（Webinar登録10+DL15）      + 興味0          = 75
 *       Low  : 属性25 + 行動0                              + 興味0          = 25
 *   - カテゴリごとに Convert（Opportunity作成）と Close（失注）に分割
 *       Hot: Convert 8 / Close 2, Warm: Convert 6 / Close 4,
 *       Cold: Convert 4 / Close 6, Low: Convert 2 / Close 8 （合計 Convert20 / Close20）
 *   - Convert は Database.convertLead() で Account/Contact/Opportunity を新規作成
 *     （既存レコードとの重複判定はしない）。Opportunity は Convert 後に一括更新で
 *     Amount（カテゴリ別レンジでランダム）・CloseDate（直近180日でランダム分散）・
 *     StageName（'商談成立' = Closed Won 相当）を設定する。
 *   - Close は Convert せず、Status を失注扱いに更新するのみ。
 *
 * この組織の LeadStatus は標準の4値（Open - Not Contacted / Working - Contacted /
 * Closed - Converted / Closed - Not Converted）+ Stale の構成になっている。
 * Convert 後のステータスには converted=true の 'Closed - Converted' を、
 * 失注扱いには 'Closed - Not Converted' を使用する（LeadStatus.standardValueSet-meta.xml 参照）。
 *
 * 同様に OpportunityStage も標準の 'Closed Won' を持たず日本語値に置き換えられている
 * （won=true/closed=true は '商談成立'。LeadStatus オブジェクトと同じく
 * `SELECT ApiName, IsWon, IsClosed FROM OpportunityStage` で確認済み）。
 *
 * 冪等性: 先頭で SEED_DATA_CONVERTED タグの既存データを削除してから再生成する。
 * Lead_Interest__c は Lead__c が任意 Lookup（主従関係ではない）のため、
 * Lead を削除しても連動削除されない。そのため Lead より先に明示的に削除する
 * （data/seed.apex と同じ制約・同じ対処）。
 * Convert 済みリードの削除に失敗した場合（組織側で変換済みリードの削除が制限されている場合）は
 * デバッグログに警告を出すのみで処理を継続する。
 */
final String SEED_TAG = 'SEED_DATA_CONVERTED';
final String SEED_EMAIL = 'seed_conv_%@example.com';
final String NAME_LIKE = '%SEED_CONVERTED%';
final String NAME_TAG = 'SEED_CONVERTED';
final String CONVERTED_STATUS = 'Closed - Converted';     // converted = true（この組織の LeadStatus 設計）
final String CLOSED_LOST_STATUS = 'Closed - Not Converted'; // 失注扱い
final String CLOSED_WON_STAGE = '商談成立';       // won=true/closed=true（この組織の OpportunityStage 設計）

// ============================================================
// 0) 既存シードデータのクリーンアップ（冪等性）
// ============================================================
delete [SELECT Id FROM Lead_Interest__c WHERE Source__c = :SEED_TAG];

List<Lead> oldLeads = [SELECT Id, IsConverted FROM Lead WHERE Email LIKE :SEED_EMAIL];
List<Lead> oldNotConverted = new List<Lead>();
List<Lead> oldConverted = new List<Lead>();
for (Lead oldLead : oldLeads) {
    if (oldLead.IsConverted) {
        oldConverted.add(oldLead);
    } else {
        oldNotConverted.add(oldLead);
    }
}
if (!oldNotConverted.isEmpty()) {
    delete oldNotConverted; // 子の CampaignMember も連動削除
}
if (!oldConverted.isEmpty()) {
    try {
        delete oldConverted; // 子の CampaignMember も連動削除
    } catch (DmlException e) {
        System.debug(LoggingLevel.WARN, 'CONVERTED_LEAD_DELETE_FAILED: 変換済みリード ' + oldConverted.size()
            + ' 件を削除できませんでした。組織側で変換済みリードの削除が制限されている可能性があります。'
            + '詳細: ' + e.getMessage());
    }
}

// Closed Won（商談成立）の商談を持つ取引先は、商談を残したまま削除できない
// （DELETE_FAILED: 「その取引先の商談の一部が成立しています」）ため、
// Opportunity を先に削除してから Account を削除する。
delete [SELECT Id FROM Opportunity WHERE Name LIKE :NAME_LIKE];
delete [SELECT Id FROM Account WHERE Name LIKE :NAME_LIKE]; // 子の Contact も連動削除
delete [SELECT Id FROM Campaign WHERE Name LIKE 'SeedConv:%'];

// ============================================================
// 1) キャンペーン + 英語 CampaignMemberStatus
// ============================================================
Map<String, Campaign> camp = new Map<String, Campaign>();
camp.put('webinar',    new Campaign(Name = 'SeedConv: ウェビナー',         Type = 'Webinar',      IsActive = true));
camp.put('tradeshow',  new Campaign(Name = 'SeedConv: 展示会',             Type = 'Trade Show',   IsActive = true));
camp.put('email',      new Campaign(Name = 'SeedConv: メールニュースレター', Type = 'Email',        IsActive = true));
camp.put('whitepaper', new Campaign(Name = 'SeedConv: ホワイトペーパーDL',   Type = 'White Paper',  IsActive = true));
camp.put('demo',       new Campaign(Name = 'SeedConv: デモ申込',           Type = 'Demo Request', IsActive = true));
insert camp.values();

Map<String, List<String>> statusByCamp = new Map<String, List<String>>{
    'webinar'    => new List<String>{ 'Registered', 'Attended' },
    'tradeshow'  => new List<String>{ 'Visited' },
    'email'      => new List<String>{ 'Responded' },
    'whitepaper' => new List<String>{ 'Downloaded' },
    'demo'       => new List<String>{ 'Submitted' }
};
Set<String> respondedLabels = new Set<String>{ 'Attended', 'Visited', 'Responded', 'Downloaded', 'Submitted' };
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
// 2) リード 40件（カテゴリごと10件）
// ============================================================
// カテゴリ別のリード情報（名前 + 会社名。40件すべて異なる人物・会社にするためべた書き）
List<Map<String, String>> HOT_LEADS = new List<Map<String, String>>{
    new Map<String, String>{'firstName' => '太郎',   'lastName' => '山田',   'company' => 'SEED_CONVERTED Hot0 日本テクノロジー株式会社'},
    new Map<String, String>{'firstName' => '花子',   'lastName' => '鈴木',   'company' => 'SEED_CONVERTED Hot1 東京システムズ株式会社'},
    new Map<String, String>{'firstName' => '一郎',   'lastName' => '田中',   'company' => 'SEED_CONVERTED Hot2 富士データソリューションズ株式会社'},
    new Map<String, String>{'firstName' => '美咲',   'lastName' => '佐藤',   'company' => 'SEED_CONVERTED Hot3 三菱デジタル株式会社'},
    new Map<String, String>{'firstName' => '健太',   'lastName' => '高橋',   'company' => 'SEED_CONVERTED Hot4 東芝インフォメーション株式会社'},
    new Map<String, String>{'firstName' => '由美',   'lastName' => '渡辺',   'company' => 'SEED_CONVERTED Hot5 日立ソフトウェア株式会社'},
    new Map<String, String>{'firstName' => '大樹',   'lastName' => '伊藤',   'company' => 'SEED_CONVERTED Hot6 NECネットワークス株式会社'},
    new Map<String, String>{'firstName' => '彩',     'lastName' => '山本',   'company' => 'SEED_CONVERTED Hot7 パナソニックITソリューションズ株式会社'},
    new Map<String, String>{'firstName' => '翔',     'lastName' => '中村',   'company' => 'SEED_CONVERTED Hot8 ソニーテクノロジー株式会社'},
    new Map<String, String>{'firstName' => '麻衣',   'lastName' => '小林',   'company' => 'SEED_CONVERTED Hot9 キヤノンシステムズ株式会社'}
};

List<Map<String, String>> WARM_LEADS = new List<Map<String, String>>{
    new Map<String, String>{'firstName' => '隆',       'lastName' => '加藤',   'company' => 'SEED_CONVERTED Warm0 東京商事株式会社'},
    new Map<String, String>{'firstName' => '真理子',   'lastName' => '吉田',   'company' => 'SEED_CONVERTED Warm1 関西ビジネス株式会社'},
    new Map<String, String>{'firstName' => '健',       'lastName' => '佐々木', 'company' => 'SEED_CONVERTED Warm2 北海道インダストリー株式会社'},
    new Map<String, String>{'firstName' => '亜紀',     'lastName' => '山口',   'company' => 'SEED_CONVERTED Warm3 九州エンジニアリング株式会社'},
    new Map<String, String>{'firstName' => '誠',       'lastName' => '松本',   'company' => 'SEED_CONVERTED Warm4 名古屋トレーディング株式会社'},
    new Map<String, String>{'firstName' => '恵子',     'lastName' => '井上',   'company' => 'SEED_CONVERTED Warm5 大阪コーポレーション株式会社'},
    new Map<String, String>{'firstName' => '拓也',     'lastName' => '木村',   'company' => 'SEED_CONVERTED Warm6 京都サービス株式会社'},
    new Map<String, String>{'firstName' => '里奈',     'lastName' => '林',     'company' => 'SEED_CONVERTED Warm7 神奈川ソリューションズ株式会社'},
    new Map<String, String>{'firstName' => '大輔',     'lastName' => '斎藤',   'company' => 'SEED_CONVERTED Warm8 埼玉プロダクツ株式会社'},
    new Map<String, String>{'firstName' => '舞子',     'lastName' => '清水',   'company' => 'SEED_CONVERTED Warm9 千葉テクニカル株式会社'}
};

List<Map<String, String>> COLD_LEADS = new List<Map<String, String>>{
    new Map<String, String>{'firstName' => '悟',       'lastName' => '山崎', 'company' => 'SEED_CONVERTED Cold0 湘南製作所'},
    new Map<String, String>{'firstName' => '亜美',     'lastName' => '森',   'company' => 'SEED_CONVERTED Cold1 城南工業株式会社'},
    new Map<String, String>{'firstName' => '弘',       'lastName' => '池田', 'company' => 'SEED_CONVERTED Cold2 城北製造株式会社'},
    new Map<String, String>{'firstName' => '沙織',     'lastName' => '橋本', 'company' => 'SEED_CONVERTED Cold3 湾岸産業株式会社'},
    new Map<String, String>{'firstName' => '智之',     'lastName' => '阿部', 'company' => 'SEED_CONVERTED Cold4 中央エレクトロニクス'},
    new Map<String, String>{'firstName' => '千秋',     'lastName' => '石川', 'company' => 'SEED_CONVERTED Cold5 東北マニュファクチャリング'},
    new Map<String, String>{'firstName' => '徹',       'lastName' => '前田', 'company' => 'SEED_CONVERTED Cold6 北陸ファブリケーション'},
    new Map<String, String>{'firstName' => 'みのり',   'lastName' => '藤田', 'company' => 'SEED_CONVERTED Cold7 中国テック'},
    new Map<String, String>{'firstName' => '章',       'lastName' => '後藤', 'company' => 'SEED_CONVERTED Cold8 四国イノベーション'},
    new Map<String, String>{'firstName' => '美香',     'lastName' => '岡田', 'company' => 'SEED_CONVERTED Cold9 沖縄デジタル'}
};

List<Map<String, String>> LOW_LEADS = new List<Map<String, String>>{
    new Map<String, String>{'firstName' => '学',       'lastName' => '長谷川', 'company' => 'SEED_CONVERTED Low0 東農園'},
    new Map<String, String>{'firstName' => '真由美',   'lastName' => '村上',   'company' => 'SEED_CONVERTED Low1 南果樹園'},
    new Map<String, String>{'firstName' => '直人',     'lastName' => '近藤',   'company' => 'SEED_CONVERTED Low2 西畜産株式会社'},
    new Map<String, String>{'firstName' => '桜',       'lastName' => '石井',   'company' => 'SEED_CONVERTED Low3 北酪農株式会社'},
    new Map<String, String>{'firstName' => '修',       'lastName' => '坂本',   'company' => 'SEED_CONVERTED Low4 中央農場'},
    new Map<String, String>{'firstName' => '里美',     'lastName' => '遠藤',   'company' => 'SEED_CONVERTED Low5 上原林業'},
    new Map<String, String>{'firstName' => '崇',       'lastName' => '青木',   'company' => 'SEED_CONVERTED Low6 下山養魚場'},
    new Map<String, String>{'firstName' => '咲希',     'lastName' => '藤井',   'company' => 'SEED_CONVERTED Low7 大和農産'},
    new Map<String, String>{'firstName' => '剛',       'lastName' => '西村',   'company' => 'SEED_CONVERTED Low8 高原花園'},
    new Map<String, String>{'firstName' => '香織',     'lastName' => '福田',   'company' => 'SEED_CONVERTED Low9 里山ファーム'}
};

List<String> CATEGORIES = new List<String>{ 'Hot', 'Warm', 'Cold', 'Low' };
Map<String, Integer> convertCountByCategory = new Map<String, Integer>{
    'Hot' => 8, 'Warm' => 6, 'Cold' => 4, 'Low' => 2
};
final Integer PER_CATEGORY = 10;

List<Lead> leads = new List<Lead>();
Map<String, List<Lead>> leadsByCategory = new Map<String, List<Lead>>();
Integer globalIndex = 0;

for (String category : CATEGORIES) {
    List<Map<String, String>> categoryLeadData;
    if (category == 'Hot') {
        categoryLeadData = HOT_LEADS;
    } else if (category == 'Warm') {
        categoryLeadData = WARM_LEADS;
    } else if (category == 'Cold') {
        categoryLeadData = COLD_LEADS;
    } else {
        categoryLeadData = LOW_LEADS;
    }

    List<Lead> categoryLeads = new List<Lead>();
    for (Integer i = 0; i < PER_CATEGORY; i++) {
        Map<String, String> leadInfo = categoryLeadData[i];
        Lead newLead = new Lead(
            FirstName = leadInfo.get('firstName'),
            LastName = leadInfo.get('lastName'),
            Company = leadInfo.get('company'),
            Email = 'seed_conv_' + String.valueOf(globalIndex).leftPad(2, '0') + '@example.com',
            Description = SEED_TAG
        );
        if (category == 'Hot') {
            // 属性85（Tech 15 / 2000名 20 / CEO 30 / Webinar 20）
            newLead.Industry = 'Technology'; newLead.NumberOfEmployees = 2000;
            newLead.Title = 'CEO'; newLead.LeadSource = 'Webinar';
        } else if (category == 'Warm') {
            // 属性60（Tech 15 / 1500名 20 / Manager 15 / Web 10）
            newLead.Industry = 'Technology'; newLead.NumberOfEmployees = 1500;
            newLead.Title = 'Sales Manager'; newLead.LeadSource = 'Web';
        } else if (category == 'Cold') {
            // 属性50（Tech 15 / 300名 10 / Manager 15 / Web 10）
            newLead.Industry = 'Technology'; newLead.NumberOfEmployees = 300;
            newLead.Title = 'Manager'; newLead.LeadSource = 'Web';
        } else {
            // 属性25（業界/規模は加点なし / Manager 15 / Web 10）
            newLead.Industry = 'Agriculture'; newLead.NumberOfEmployees = 5;
            newLead.Title = 'Manager'; newLead.LeadSource = 'Web';
        }
        categoryLeads.add(newLead);
        leads.add(newLead);
        globalIndex++;
    }
    leadsByCategory.put(category, categoryLeads);
}
// この組織の標準リード重複ルールは日本語の会社名（'株式会社' 等の共通語）を含む Company に対して
// 誤って重複と判定することがあるため、シードデータ投入では重複ルールをバイパスする。
Database.DMLOptions dmlOptions = new Database.DMLOptions();
dmlOptions.DuplicateRuleHeader.allowSave = true;
dmlOptions.OptAllOrNone = true;
Database.insert(leads, dmlOptions); // afterInsert で属性スコアが計算される

// ============================================================
// 3) Lead_Interest__c（Hot/Warm のみ。合計は必ず上限80に達する組み合わせ）
// ============================================================
List<String> TOPICS = new List<String>{
    'データ統合','業務効率化','セキュリティ強化','コスト削減','DX 推進',
    '既存システム置き換え','クラウド移行','自動化','AI 活用','ガバナンス強化'
};
List<Integer> HOT_LEVELS  = new List<Integer>{ 80, 100, 70 }; // 上限80で頭打ち
List<Integer> WARM_LEVELS = new List<Integer>{ 45, 60 };      // 上限80で頭打ち

List<Lead_Interest__c> interests = new List<Lead_Interest__c>();
Integer topicIndex = 0;
for (String category : CATEGORIES) {
    List<Integer> levels = new List<Integer>();
    if (category == 'Hot') {
        levels = HOT_LEVELS;
    } else if (category == 'Warm') {
        levels = WARM_LEVELS;
    }
    // Cold / Low は興味なし

    for (Lead categoryLead : leadsByCategory.get(category)) {
        for (Integer level : levels) {
            interests.add(new Lead_Interest__c(
                Lead__c = categoryLead.Id,
                Interest_Topic__c = TOPICS[Math.mod(topicIndex, TOPICS.size())],
                Interest_Level__c = level,
                Detected_Date__c = Date.today(),
                Source__c = SEED_TAG,
                Notes__c = '商談化シードデータ'
            ));
            topicIndex++;
        }
    }
}
insert interests; // LeadInterestTrigger で興味スコアが再計算される

// ============================================================
// 4) CampaignMember（Hot: Demo+Webinar / Warm: 展示会+メール / Cold: Webinar+WhitePaper / Low: なし）
// ============================================================
List<CampaignMember> members = new List<CampaignMember>();
for (String category : CATEGORIES) {
    for (Lead categoryLead : leadsByCategory.get(category)) {
        if (category == 'Hot') {
            // 行動80（Demo/Submitted 50 + Webinar/Attended 30）
            members.add(new CampaignMember(CampaignId = camp.get('demo').Id,    LeadId = categoryLead.Id, Status = 'Submitted'));
            members.add(new CampaignMember(CampaignId = camp.get('webinar').Id, LeadId = categoryLead.Id, Status = 'Attended'));
        } else if (category == 'Warm') {
            // 行動30（展示会/Visited 25 + メール/Responded 5）
            members.add(new CampaignMember(CampaignId = camp.get('tradeshow').Id, LeadId = categoryLead.Id, Status = 'Visited'));
            members.add(new CampaignMember(CampaignId = camp.get('email').Id,     LeadId = categoryLead.Id, Status = 'Responded'));
        } else if (category == 'Cold') {
            // 行動25（Webinar/Registered 10 + White Paper/Downloaded 15）
            members.add(new CampaignMember(CampaignId = camp.get('webinar').Id,    LeadId = categoryLead.Id, Status = 'Registered'));
            members.add(new CampaignMember(CampaignId = camp.get('whitepaper').Id, LeadId = categoryLead.Id, Status = 'Downloaded'));
        }
        // Low: 行動なし
    }
}
insert members; // CampaignMemberTrigger で行動スコアが再計算される（Convert 前に完了させる）

// ============================================================
// 5) Convert（Opportunity作成）/ Close（失注）の分割・実行
// ============================================================
Map<String, Decimal> amountMinByCategory = new Map<String, Decimal>{
    'Hot' => 5000000, 'Warm' => 2000000, 'Cold' => 500000, 'Low' => 100000
};
Map<String, Decimal> amountMaxByCategory = new Map<String, Decimal>{
    'Hot' => 10000000, 'Warm' => 5000000, 'Cold' => 2000000, 'Low' => 500000
};

List<Database.LeadConvert> toConvert = new List<Database.LeadConvert>();
List<String> convertCategoryOrder = new List<String>(); // toConvert と同じ順序でカテゴリを保持
List<Lead> toClose = new List<Lead>();

for (String category : CATEGORIES) {
    List<Lead> categoryLeads = leadsByCategory.get(category);
    Integer convertCount = convertCountByCategory.get(category);
    for (Integer i = 0; i < categoryLeads.size(); i++) {
        Lead categoryLead = categoryLeads[i];
        if (i < convertCount) {
            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(categoryLead.Id);
            lc.setConvertedStatus(CONVERTED_STATUS);
            lc.setOpportunityName(NAME_TAG + ' ' + category + ' Opp ' + i);
            toConvert.add(lc);
            convertCategoryOrder.add(category);
        } else {
            categoryLead.Status = CLOSED_LOST_STATUS;
            toClose.add(categoryLead);
        }
    }
}

if (!toClose.isEmpty()) {
    update toClose; // Close（失注）: Status のみ更新、Convert は実行しない
}

List<Database.LeadConvertResult> convertResults = new List<Database.LeadConvertResult>();
if (!toConvert.isEmpty()) {
    convertResults = Database.convertLead(toConvert, false);
}

// Opportunity の CloseDate/Amount/StageName は Convert 実行結果からまとめて更新する
// （Database.LeadConvert では Opportunity の CloseDate/Amount/StageName を指定できないため）
List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
Integer convertedCount = 0;
for (Integer i = 0; i < convertResults.size(); i++) {
    Database.LeadConvertResult result = convertResults[i];
    if (!result.isSuccess()) {
        System.debug(LoggingLevel.WARN, 'LEAD_CONVERT_FAILED: ' + result.getErrors());
        continue;
    }
    String category = convertCategoryOrder[i];
    Decimal amountMin = amountMinByCategory.get(category);
    Decimal amountMax = amountMaxByCategory.get(category);
    Decimal amount = (amountMin + (Math.random() * (amountMax - amountMin))).setScale(0);
    Integer daysAgo = Integer.valueOf(Math.random() * 180);

    opportunitiesToUpdate.add(new Opportunity(
        Id = result.getOpportunityId(),
        Amount = amount,
        CloseDate = Date.today().addDays(-daysAgo),
        StageName = CLOSED_WON_STAGE
    ));
    convertedCount++;
}
if (!opportunitiesToUpdate.isEmpty()) {
    update opportunitiesToUpdate;
}

System.debug('SEED_DONE leads=' + leads.size()
    + ' converted=' + convertedCount + ' closed=' + toClose.size()
    + ' interests=' + interests.size() + ' members=' + members.size());
