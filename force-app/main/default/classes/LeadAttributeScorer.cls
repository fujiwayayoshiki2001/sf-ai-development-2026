/**
 * 属性スコアを計算するクラス。
 *
 * Lead レコード自身の項目（Industry / NumberOfEmployees / Title / LeadSource）を
 * 評価し、Lead_Scoring_Config__mdt（Score_Type = 'Attribute'）の重みを合算して
 * 属性スコアを算出する。最大値は LeadConstants.ATTRIBUTE_MAX_SCORE で頭打ち。
 *
 * 主なメソッド:
 *  - calculateBulk(List<Lead>) : 複数 Lead の属性スコアをまとめて計算（基本メソッド）
 *  - calculate(Lead)           : 単一 Lead の属性スコア（内部でバルクメソッドを呼ぶ）
 *
 * SOQL/DML を持たず、参照するのはカスタムメタデータのみのため sharing 指定は不要。
 */
public class LeadAttributeScorer {

    // 規模カテゴリのキー（Lead_Scoring_Config__mdt.Key__c と一致させる）
    private static final String KEY_SIZE_LARGE  = 'NumberOfEmployees_1000+';
    private static final String KEY_SIZE_MEDIUM = 'NumberOfEmployees_100-999';
    private static final String KEY_SIZE_SMALL  = 'NumberOfEmployees_10-99';

    // 役職カテゴリのキー
    private static final String KEY_TITLE_C       = 'Title_C-level';
    private static final String KEY_TITLE_VP      = 'Title_VP';
    private static final String KEY_TITLE_MANAGER = 'Title_Manager';

    // 重み Map のトランザクション内キャッシュ（小文字化したキー → 重み）
    private static Map<String, Decimal> cachedWeightMap;

    /**
     * 複数 Lead の属性スコアをまとめて計算する。
     * @param leads 対象 Lead のリスト（各項目を参照する）
     * @return Lead Id → 属性スコア の Map
     */
    public static Map<Id, Decimal> calculateBulk(List<Lead> leads) {
        Map<Id, Decimal> scoreMap = new Map<Id, Decimal>();
        if (leads == null || leads.isEmpty()) {
            return scoreMap;
        }

        Map<String, Decimal> weightMap = getWeightMap();

        for (Lead lead : leads) {
            if (lead.Id == null) {
                continue;
            }
            Decimal score = 0;
            score += getIndustryWeight(lead.Industry, weightMap);
            score += getSizeWeight(lead.NumberOfEmployees, weightMap);
            score += getTitleWeight(lead.Title, weightMap);
            score += getSourceWeight(lead.LeadSource, weightMap);

            // 上限で頭打ち
            score = Math.min(score, LeadConstants.ATTRIBUTE_MAX_SCORE);
            scoreMap.put(lead.Id, score);
        }

        return scoreMap;
    }

    /**
     * 単一 Lead の属性スコアを計算する。内部でバルクメソッドを呼び出す。
     * @param lead 対象 Lead
     * @return 属性スコア（lead が null の場合は 0）
     */
    public static Decimal calculate(Lead lead) {
        if (lead == null || lead.Id == null) {
            return 0;
        }
        Map<Id, Decimal> scoreMap = calculateBulk(new List<Lead>{ lead });
        return scoreMap.containsKey(lead.Id) ? scoreMap.get(lead.Id) : 0;
    }

    /**
     * 業界に応じた重みを返す。Key__c と Industry を大文字小文字無視で照合する。
     */
    private static Decimal getIndustryWeight(String industry, Map<String, Decimal> weightMap) {
        if (String.isBlank(industry)) {
            return 0;
        }
        return lookup(weightMap, industry);
    }

    /**
     * 従業員数の規模カテゴリに応じた重みを返す。
     */
    private static Decimal getSizeWeight(Integer numberOfEmployees, Map<String, Decimal> weightMap) {
        if (numberOfEmployees == null) {
            return 0;
        }
        if (numberOfEmployees >= 1000) {
            return lookup(weightMap, KEY_SIZE_LARGE);
        } else if (numberOfEmployees >= 100) {
            return lookup(weightMap, KEY_SIZE_MEDIUM);
        } else if (numberOfEmployees >= 10) {
            return lookup(weightMap, KEY_SIZE_SMALL);
        }
        return 0;
    }

    /**
     * 役職に応じた重みを返す。役職名の含有判定でカテゴリを決定する。
     */
    private static Decimal getTitleWeight(String title, Map<String, Decimal> weightMap) {
        if (String.isBlank(title)) {
            return 0;
        }
        String normalized = title.toLowerCase();

        // C レベル（CEO / CTO / CFO / COO / CMO / Chief など）
        if (normalized.contains('ceo') || normalized.contains('cto')
                || normalized.contains('cfo') || normalized.contains('coo')
                || normalized.contains('cmo') || normalized.contains('chief')
                || normalized.contains('c-level')) {
            return lookup(weightMap, KEY_TITLE_C);
        }
        // VP（Vice President）
        if (normalized.contains('vp') || normalized.contains('vice president')) {
            return lookup(weightMap, KEY_TITLE_VP);
        }
        // マネージャー / ディレクター
        if (normalized.contains('manager') || normalized.contains('director')) {
            return lookup(weightMap, KEY_TITLE_MANAGER);
        }
        return 0;
    }

    /**
     * リードソースに応じた重みを返す。Key__c と LeadSource を大文字小文字無視で照合する。
     * 'Web' と 'Webinar' のような前方一致を避けるため、完全一致（小文字化後の等価）で判定する。
     */
    private static Decimal getSourceWeight(String leadSource, Map<String, Decimal> weightMap) {
        if (String.isBlank(leadSource)) {
            return 0;
        }
        return lookup(weightMap, leadSource);
    }

    /**
     * 小文字化したキーで重み Map を引く。存在しなければ 0 を返す。
     */
    private static Decimal lookup(Map<String, Decimal> weightMap, String key) {
        String normalizedKey = key.trim().toLowerCase();
        return weightMap.containsKey(normalizedKey) ? weightMap.get(normalizedKey) : 0;
    }

    /**
     * Lead_Scoring_Config__mdt から属性スコア用の重み Map を構築する（キーは小文字化）。
     * トランザクション内でキャッシュする。
     */
    private static Map<String, Decimal> getWeightMap() {
        if (cachedWeightMap != null) {
            return cachedWeightMap;
        }

        cachedWeightMap = new Map<String, Decimal>();
        for (Lead_Scoring_Config__mdt config : Lead_Scoring_Config__mdt.getAll().values()) {
            if (config.Score_Type__c == LeadConstants.SCORE_TYPE_ATTRIBUTE
                    && config.Is_Active__c == true
                    && String.isNotBlank(config.Key__c)
                    && config.Weight__c != null) {
                cachedWeightMap.put(config.Key__c.trim().toLowerCase(), config.Weight__c);
            }
        }
        return cachedWeightMap;
    }
}
