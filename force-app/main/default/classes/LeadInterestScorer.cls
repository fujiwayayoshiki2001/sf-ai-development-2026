/**
 * 興味スコアを計算するクラス。
 *
 * Lead に紐づく Lead_Interest__c を集計し、Interest_Topic__c に対応する重み
 * （Lead_Scoring_Config__mdt の Score_Type = 'Interest'）に Interest_Level__c を掛けて
 * 合算する。最大値は LeadConstants.INTEREST_MAX_SCORE で頭打ち。
 * 同一 Topic が複数ある場合は単純合算する（仕様）。
 *
 * Lead__c は任意 Lookup のため、Lead__c が null の興味レコードは集計対象外とする。
 *
 * 主なメソッド:
 *  - calculateBulk(Set<Id>) : 複数 Lead の興味スコアをまとめて計算（基本メソッド）
 *  - calculate(Id)          : 単一 Lead の興味スコア（内部でバルクメソッドを呼ぶ）
 *
 * SOQL を含むため with sharing を宣言する。
 */
public with sharing class LeadInterestScorer {

    // 重み Map のトランザクション内キャッシュ（小文字化したトピック → 重み）
    private static Map<String, Decimal> cachedWeightMap;

    /**
     * 複数 Lead の興味スコアをまとめて計算する。
     * @param leadIds 対象 Lead Id の集合
     * @return Lead Id → 興味スコア の Map（全 Lead を 0 で初期化済み）
     */
    public static Map<Id, Decimal> calculateBulk(Set<Id> leadIds) {
        Map<Id, Decimal> scoreMap = new Map<Id, Decimal>();
        if (leadIds == null || leadIds.isEmpty()) {
            return scoreMap;
        }

        // 全 Lead を 0 で初期化
        for (Id leadId : leadIds) {
            scoreMap.put(leadId, 0);
        }

        // 一度のクエリで対象 Lead の Lead_Interest__c をすべて取得（必要な項目のみ）
        List<Lead_Interest__c> interests = [
            SELECT Id, Lead__c, Interest_Topic__c, Interest_Level__c
            FROM Lead_Interest__c
            WHERE Lead__c IN :leadIds
            WITH SECURITY_ENFORCED
        ];

        Map<String, Decimal> weightMap = getWeightMap();

        // 集計
        for (Lead_Interest__c interest : interests) {
            if (interest.Lead__c == null
                    || String.isBlank(interest.Interest_Topic__c)
                    || interest.Interest_Level__c == null) {
                continue;
            }
            String key = interest.Interest_Topic__c.trim().toLowerCase();
            Decimal weight = 0;
            if (weightMap.containsKey(key)) {
                weight = weightMap.get(key);
            }
            if (weight == 0) {
                continue;
            }
            Decimal current = scoreMap.get(interest.Lead__c);
            scoreMap.put(interest.Lead__c, current + (interest.Interest_Level__c * weight));
        }

        // 上限で頭打ち
        for (Id leadId : scoreMap.keySet()) {
            scoreMap.put(leadId, Math.min(scoreMap.get(leadId), LeadConstants.INTEREST_MAX_SCORE));
        }

        return scoreMap;
    }

    /**
     * 単一 Lead の興味スコアを計算する。内部でバルクメソッドを呼び出す。
     * @param leadId 対象 Lead Id
     * @return 興味スコア（leadId が null の場合は 0）
     */
    public static Decimal calculate(Id leadId) {
        if (leadId == null) {
            return 0;
        }
        Map<Id, Decimal> scoreMap = calculateBulk(new Set<Id>{ leadId });
        if (scoreMap.containsKey(leadId)) {
            return scoreMap.get(leadId);
        }
        return 0;
    }

    /**
     * Lead_Scoring_Config__mdt から興味スコア用の重み Map を構築する（キーは小文字化）。
     * トランザクション内でキャッシュする。
     */
    private static Map<String, Decimal> getWeightMap() {
        if (cachedWeightMap != null) {
            return cachedWeightMap;
        }

        cachedWeightMap = new Map<String, Decimal>();
        for (Lead_Scoring_Config__mdt config : Lead_Scoring_Config__mdt.getAll().values()) {
            if (config.Score_Type__c == LeadConstants.SCORE_TYPE_INTEREST
                    && config.Is_Active__c == true
                    && String.isNotBlank(config.Key__c)
                    && config.Weight__c != null) {
                cachedWeightMap.put(config.Key__c.trim().toLowerCase(), config.Weight__c);
            }
        }
        return cachedWeightMap;
    }
}
