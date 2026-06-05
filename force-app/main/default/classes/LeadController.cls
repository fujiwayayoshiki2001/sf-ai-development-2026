/**
 * リード管理機能（leadManager LWC）のコントローラ。
 *
 * - リード一覧の取得（ステータス・高スコアでのフィルタ）
 * - リードスコアの計算（トリガーからも再利用）
 * - 既存リードのスコア再計算
 *
 * スコアは Lead.Score__c（0〜100）に格納され、登録／更新時に
 * LeadTrigger によって自動で再計算される。
 */
public with sharing class LeadController {
    /** 高スコアリードとみなすスコアの下限値。 */
    @TestVisible
    private static final Integer HIGH_SCORE_THRESHOLD = 30;

    /** スコアの上限値（これを超えないように丸める）。 */
    private static final Integer MAX_SCORE = 100;

    // --- スコア加点ルール（マジックナンバー禁止のため定数化） ---
    private static final Integer POINTS_EMAIL = 10;
    private static final Integer POINTS_PHONE = 10;
    private static final Integer POINTS_INDUSTRY = 5;
    private static final Integer POINTS_LEAD_SOURCE = 5;
    private static final Integer POINTS_RATING_HOT = 20;
    private static final Integer POINTS_RATING_WARM = 10;
    private static final Integer POINTS_REVENUE_HIGH = 20;
    private static final Integer POINTS_REVENUE_MID = 10;
    private static final Integer POINTS_EMPLOYEES_HIGH = 20;
    private static final Integer POINTS_EMPLOYEES_MID = 10;

    private static final Decimal REVENUE_HIGH_THRESHOLD = 100000000; // 1億円
    private static final Decimal REVENUE_MID_THRESHOLD = 10000000;   // 1千万円
    private static final Integer EMPLOYEES_HIGH_THRESHOLD = 1000;
    private static final Integer EMPLOYEES_MID_THRESHOLD = 100;

    /** スコア計算・一覧取得で参照する項目（クエリ最適化のため必要項目のみ）。 */
    private static final List<String> SELECT_FIELDS = new List<String>{
        'Id', 'Name', 'Company', 'Email', 'Phone', 'Status', 'Rating',
        'Industry', 'LeadSource', 'AnnualRevenue', 'NumberOfEmployees', 'Score__c'
    };

    /**
     * リード一覧を取得する。
     *
     * @param statusFilter  ステータスでの絞り込み（null／空なら全件）
     * @param highScoreOnly true の場合は高スコア（30以上）のみ返す
     * @return 条件に一致するリードのリスト（スコア降順）
     */
    @AuraEnabled(cacheable=true)
    public static List<Lead> getLeads(String statusFilter, Boolean highScoreOnly) {
        Boolean onlyHigh = highScoreOnly == true;
        String trimmedStatus = String.isBlank(statusFilter) ? null : statusFilter.trim();
        Integer minScore = HIGH_SCORE_THRESHOLD;

        List<String> conditions = new List<String>();
        if (trimmedStatus != null) {
            conditions.add('Status = :trimmedStatus');
        }
        if (onlyHigh) {
            conditions.add('Score__c >= :minScore');
        }

        String soql = 'SELECT ' + String.join(SELECT_FIELDS, ', ') + ' FROM Lead';
        if (!conditions.isEmpty()) {
            soql += ' WHERE ' + String.join(conditions, ' AND ');
        }
        soql += ' WITH SECURITY_ENFORCED ORDER BY Score__c DESC NULLS LAST, Name ASC LIMIT 1000';

        try {
            return Database.query(soql);
        } catch (QueryException e) {
            throw new LeadScoreException('リード一覧の取得に失敗しました。', e);
        }
    }

    /**
     * 高スコアリード（スコア30以上）を取得する。
     *
     * @return 高スコアリードのリスト
     */
    @AuraEnabled(cacheable=true)
    public static List<Lead> getHighScoreLeads() {
        return getLeads(null, true);
    }

    /**
     * 指定したリードのスコアを再計算して更新する。
     * 実際の Score__c の再計算は LeadTrigger（before update）が行う。
     *
     * @param leadIds 再計算対象のリードIDリスト
     * @return 更新後のリードリスト
     */
    @AuraEnabled
    public static List<Lead> recalculateScores(List<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            throw new LeadScoreException('再計算するリードが指定されていません。');
        }
        if (!Schema.sObjectType.Lead.isUpdateable()) {
            throw new LeadScoreException('リードを更新する権限がありません。');
        }

        List<Lead> targets = [
            SELECT Id FROM Lead WHERE Id IN :leadIds WITH SECURITY_ENFORCED
        ];
        if (targets.isEmpty()) {
            throw new LeadScoreException('指定されたリードが見つかりませんでした。');
        }

        try {
            // 空更新でも before update トリガーが発火し Score__c が再計算される。
            update targets;
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR, 'リードスコア再計算の更新に失敗: ' + e.getMessage());
            throw new LeadScoreException('リードスコアの再計算に失敗しました。', e);
        }

        return getLeadsByIds(leadIds);
    }

    /**
     * 1件のリードのスコアを計算する純粋関数。
     * SOQL/DML を行わないためトリガー内のループからも安全に呼び出せる。
     *
     * @param targetLead スコアを計算するリード
     * @return 0〜100 のスコア
     */
    public static Integer calculateScore(Lead targetLead) {
        if (targetLead == null) {
            return 0;
        }

        Integer score = 0;
        score += String.isNotBlank(targetLead.Email) ? POINTS_EMAIL : 0;
        score += String.isNotBlank(targetLead.Phone) ? POINTS_PHONE : 0;
        score += String.isNotBlank(targetLead.Industry) ? POINTS_INDUSTRY : 0;
        score += String.isNotBlank(targetLead.LeadSource) ? POINTS_LEAD_SOURCE : 0;
        score += scoreForRating(targetLead.Rating);
        score += scoreForRevenue(targetLead.AnnualRevenue);
        score += scoreForEmployees(targetLead.NumberOfEmployees);

        return Math.min(score, MAX_SCORE);
    }

    /** Rating（評価）による加点。 */
    private static Integer scoreForRating(String rating) {
        if (rating == 'Hot') {
            return POINTS_RATING_HOT;
        }
        if (rating == 'Warm') {
            return POINTS_RATING_WARM;
        }
        return 0;
    }

    /** 年間売上による加点。null の場合は0点。 */
    private static Integer scoreForRevenue(Decimal annualRevenue) {
        if (annualRevenue == null) {
            return 0;
        }
        if (annualRevenue >= REVENUE_HIGH_THRESHOLD) {
            return POINTS_REVENUE_HIGH;
        }
        if (annualRevenue >= REVENUE_MID_THRESHOLD) {
            return POINTS_REVENUE_MID;
        }
        return 0;
    }

    /** 従業員数による加点。null の場合は0点。 */
    private static Integer scoreForEmployees(Integer numberOfEmployees) {
        if (numberOfEmployees == null) {
            return 0;
        }
        if (numberOfEmployees >= EMPLOYEES_HIGH_THRESHOLD) {
            return POINTS_EMPLOYEES_HIGH;
        }
        if (numberOfEmployees >= EMPLOYEES_MID_THRESHOLD) {
            return POINTS_EMPLOYEES_MID;
        }
        return 0;
    }

    /** ID指定でリードを取得する（再計算後の返却用）。 */
    private static List<Lead> getLeadsByIds(List<Id> leadIds) {
        return [
            SELECT Id, Name, Company, Email, Phone, Status, Rating,
                   Industry, LeadSource, AnnualRevenue, NumberOfEmployees, Score__c
            FROM Lead
            WHERE Id IN :leadIds
            WITH SECURITY_ENFORCED
            ORDER BY Score__c DESC NULLS LAST
        ];
    }
}