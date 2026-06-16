/**
 * 行動スコアを計算するクラス。
 *
 * Lead に紐づく CampaignMember を集計し、Campaign.Type と Status の組み合わせに対応する
 * 重み（Lead_Scoring_Config__mdt の Score_Type = 'Behavior'）に時間減衰係数を掛けて合算する。
 * 時間減衰は LeadConstants.DECAY_FACTOR ^ 経過日数。最大値は BEHAVIOR_MAX_SCORE で頭打ち。
 *
 * 主なメソッド:
 *  - calculateBulk(Set<Id>) : 複数 Lead の行動スコアをまとめて計算（基本メソッド）
 *  - calculate(Id)          : 単一 Lead の行動スコア（内部でバルクメソッドを呼ぶ）
 *
 * SOQL を含むため with sharing を宣言する。
 */
public with sharing class LeadBehaviorScorer {

    // 重み Map のトランザクション内キャッシュ（小文字化したキー → 重み）
    private static Map<String, Decimal> cachedWeightMap;

    /**
     * 複数 Lead の行動スコアをまとめて計算する。
     * @param leadIds 対象 Lead Id の集合
     * @return Lead Id → 行動スコア の Map（全 Lead を 0 で初期化済み）
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

        // 一度のクエリで対象 Lead の CampaignMember をすべて取得
        List<CampaignMember> members = [
            SELECT Id, LeadId, Campaign.Type, Status, CreatedDate
            FROM CampaignMember
            WHERE LeadId IN :leadIds
            WITH SECURITY_ENFORCED
        ];

        Map<String, Decimal> weightMap = getWeightMap();

        // 集計
        for (CampaignMember member : members) {
            if (member.LeadId == null || member.Campaign.Type == null || member.Status == null) {
                continue;
            }
            String key = (member.Campaign.Type + '_' + member.Status).toLowerCase();
            Decimal weight = 0;
            if (weightMap.containsKey(key)) {
                weight = weightMap.get(key);
            }
            if (weight == 0) {
                continue;
            }
            Decimal decay = calculateDecay(member.CreatedDate.date());
            Decimal current = scoreMap.get(member.LeadId);
            scoreMap.put(member.LeadId, current + (weight * decay));
        }

        // 上限で頭打ち
        for (Id leadId : scoreMap.keySet()) {
            scoreMap.put(leadId, Math.min(scoreMap.get(leadId), LeadConstants.BEHAVIOR_MAX_SCORE));
        }

        return scoreMap;
    }

    /**
     * 単一 Lead の行動スコアを計算する。内部でバルクメソッドを呼び出す。
     * @param leadId 対象 Lead Id
     * @return 行動スコア（leadId が null の場合は 0）
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
     * 活動日から今日までの経過日数に基づく時間減衰係数を計算する。
     * 係数 = DECAY_FACTOR ^ 経過日数（未来日付の場合は経過日数 0 = 減衰なし）。
     */
    private static Decimal calculateDecay(Date activityDate) {
        if (activityDate == null) {
            return 1;
        }
        Integer daysAgo = activityDate.daysBetween(Date.today());
        if (daysAgo < 0) {
            daysAgo = 0;
        }
        return Math.pow(LeadConstants.DECAY_FACTOR.doubleValue(), daysAgo);
    }

    /**
     * Lead_Scoring_Config__mdt から行動スコア用の重み Map を構築する（キーは小文字化）。
     * トランザクション内でキャッシュする。
     */
    private static Map<String, Decimal> getWeightMap() {
        if (cachedWeightMap != null) {
            return cachedWeightMap;
        }

        cachedWeightMap = new Map<String, Decimal>();
        for (Lead_Scoring_Config__mdt config : Lead_Scoring_Config__mdt.getAll().values()) {
            if (config.Score_Type__c == LeadConstants.SCORE_TYPE_BEHAVIOR
                    && config.Is_Active__c == true
                    && String.isNotBlank(config.Key__c)
                    && config.Weight__c != null) {
                cachedWeightMap.put(config.Key__c.trim().toLowerCase(), config.Weight__c);
            }
        }
        return cachedWeightMap;
    }
}
