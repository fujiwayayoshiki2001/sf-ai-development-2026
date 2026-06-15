/**
 * Lead に対する一般的な操作を提供するビジネスロジック中核クラス。
 *
 * LeadController（LWC 窓口）やバッチ／Flow から呼ばれ、Lead の取得・検索・更新を担う。
 * 全 SOQL に WITH SECURITY_ENFORCED を付け、LIMIT で件数を制限する。
 *
 * 主なメソッド:
 *  - getLeadsByCategory(String, Integer) : カテゴリ別リードをスコア降順で取得
 *  - searchLeads(String, Integer)        : 名前・会社名で検索
 *  - updateLastActionDate(Set<Id>)       : 最終アクション日を更新
 *  - getStaleLeads()                     : 一定日数アクションのないリードを取得
 *
 * SOQL/DML を含むため with sharing を宣言する。
 */
public with sharing class LeadService {

    // 取得件数の既定値と上限
    private static final Integer DEFAULT_LIMIT = 50;
    private static final Integer MAX_LIMIT = 200;

    // 1リードあたりの興味レコード取得上限
    private static final Integer INTEREST_LIMIT = 100;

    /**
     * 指定カテゴリのリードをスコア降順で取得する。
     * @param category  Lead_Category__c の値（Hot/Warm/Cold/Low）
     * @param limitSize 取得上限（null/0 以下は既定 50、200 を超える場合は 200）
     * @return 該当リードのリスト（category が空なら空リスト）
     */
    public static List<Lead> getLeadsByCategory(String category, Integer limitSize) {
        if (String.isBlank(category)) {
            return new List<Lead>();
        }
        Integer effectiveLimit = normalizeLimit(limitSize);

        return [
            SELECT Id, Name, Company, Title, Industry,
                   Score__c, Attribute_Score__c, Behavior_Score__c, Interest_Score__c,
                   Lead_Category__c, Status
            FROM Lead
            WHERE Lead_Category__c = :category
            WITH SECURITY_ENFORCED
            ORDER BY Score__c DESC
            LIMIT :effectiveLimit
        ];
    }

    /**
     * 全カテゴリのリードをスコア降順で取得する（カテゴリ未指定 = 「All」表示用）。
     * @param limitSize 取得上限（null/0 以下は既定 50、200 を超える場合は 200）
     * @return リードのリスト
     */
    public static List<Lead> getAllLeads(Integer limitSize) {
        Integer effectiveLimit = normalizeLimit(limitSize);

        return [
            SELECT Id, Name, Company, Title, Industry,
                   Score__c, Attribute_Score__c, Behavior_Score__c, Interest_Score__c,
                   Lead_Category__c, Status
            FROM Lead
            WITH SECURITY_ENFORCED
            ORDER BY Score__c DESC NULLS LAST
            LIMIT :effectiveLimit
        ];
    }

    /**
     * 名前または会社名で部分一致検索する（スコア降順）。
     * 入力は String.escapeSingleQuotes でエスケープし、バインド変数で安全に渡す。
     * @param searchTerm 検索文字列
     * @param limitSize  取得上限（null/0 以下は既定 50、200 を超える場合は 200）
     * @return 該当リードのリスト（searchTerm が空なら空リスト）
     */
    public static List<Lead> searchLeads(String searchTerm, Integer limitSize) {
        if (String.isBlank(searchTerm)) {
            return new List<Lead>();
        }
        Integer effectiveLimit = normalizeLimit(limitSize);

        // バインド変数を使用するため動的 SOQL は不要だが、規約に従い入力をエスケープしておく
        String escaped = String.escapeSingleQuotes(searchTerm);
        String pattern = '%' + escaped + '%';

        return [
            SELECT Id, Name, Company, Score__c, Lead_Category__c
            FROM Lead
            WHERE Name LIKE :pattern OR Company LIKE :pattern
            WITH SECURITY_ENFORCED
            ORDER BY Score__c DESC
            LIMIT :effectiveLimit
        ];
    }

    /**
     * 指定リードの 3 軸スコアの内訳を返す。
     * @param leadId 対象 Lead Id
     * @return { attribute, behavior, interest, total } の Map
     * @throws IllegalArgumentException leadId が null の場合
     * @throws QueryException           指定リードが存在しない場合
     */
    public static Map<String, Decimal> getScoreBreakdown(Id leadId) {
        if (leadId == null) {
            throw new IllegalArgumentException('リード ID が指定されていません');
        }

        List<Lead> leads = [
            SELECT Id, Score__c, Attribute_Score__c, Behavior_Score__c, Interest_Score__c
            FROM Lead
            WHERE Id = :leadId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (leads.isEmpty()) {
            throw new QueryException('指定されたリードが見つかりません: ' + leadId);
        }

        Lead lead = leads[0];
        return new Map<String, Decimal>{
            'attribute' => lead.Attribute_Score__c,
            'behavior'  => lead.Behavior_Score__c,
            'interest'  => lead.Interest_Score__c,
            'total'     => lead.Score__c
        };
    }

    /**
     * 指定リードに紐づく興味レコードを関心度（Interest_Level__c）の降順で取得する。
     * @param leadId 対象 Lead Id
     * @return Lead_Interest__c のリスト（最大 INTEREST_LIMIT 件）
     * @throws IllegalArgumentException leadId が null の場合
     */
    public static List<Lead_Interest__c> getInterests(Id leadId) {
        if (leadId == null) {
            throw new IllegalArgumentException('リード ID が指定されていません');
        }

        return [
            SELECT Id, Interest_Topic__c, Interest_Level__c, Detected_Date__c, Source__c, Notes__c
            FROM Lead_Interest__c
            WHERE Lead__c = :leadId
            WITH SECURITY_ENFORCED
            ORDER BY Interest_Level__c DESC
            LIMIT :INTEREST_LIMIT
        ];
    }

    /**
     * 指定リードの最終アクション日を本日に更新する。
     * 更新権限（CRUD）を確認してから DML を実行する。
     * @param leadIds 対象 Lead Id の集合
     */
    public static void updateLastActionDate(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            return;
        }
        if (!Schema.sObjectType.Lead.isUpdateable()) {
            throw new AuraHandledException('リードの更新権限がありません');
        }

        List<Lead> leadsToUpdate = new List<Lead>();
        for (Id leadId : leadIds) {
            leadsToUpdate.add(new Lead(
                Id = leadId,
                Last_Action_Date__c = Date.today()
            ));
        }
        update leadsToUpdate;
    }

    /**
     * 最終アクション日が STALE_DAYS 日以上前で、まだ Stale 化されていないリードを取得する。
     * @return 陳腐化候補のリードのリスト
     */
    public static List<Lead> getStaleLeads() {
        Date thresholdDate = Date.today().addDays(-LeadConstants.STALE_DAYS);

        return [
            SELECT Id, Name, Last_Action_Date__c, Status
            FROM Lead
            WHERE Last_Action_Date__c < :thresholdDate
              AND Status != :LeadConstants.STATUS_STALE
            WITH SECURITY_ENFORCED
        ];
    }

    /**
     * 取得上限を既定値・上限内に正規化する。
     * @param limitSize 入力上限
     * @return 1〜MAX_LIMIT の範囲に収めた上限
     */
    private static Integer normalizeLimit(Integer limitSize) {
        if (limitSize == null || limitSize <= 0) {
            return DEFAULT_LIMIT;
        }
        return Math.min(limitSize, MAX_LIMIT);
    }
}
