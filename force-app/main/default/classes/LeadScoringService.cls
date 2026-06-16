/**
 * スコアリングの統括サービス。
 *
 * 3つの Scorer（LeadAttributeScorer / LeadBehaviorScorer / LeadInterestScorer）を呼び出し、
 * 属性・行動・興味の各スコアと合計（最終スコア）・カテゴリを算出して Lead に反映する。
 *
 * 主なメソッド:
 *  - calculateScores(Set<Id>) : 複数 Lead のスコアをまとめて計算・反映（基本メソッド）
 *  - calculateScore(Id)       : 単一 Lead のスコア計算（内部でバルクメソッドを呼ぶ）
 *  - determineCategory(Decimal): 最終スコアからカテゴリ（Hot/Warm/Cold/Low）を判定
 *
 * SOQL/DML を含むため with sharing を宣言する。
 */
public with sharing class LeadScoringService {

    /**
     * 複数 Lead のスコアを計算し、各スコア項目・カテゴリ・計算日時を反映する。
     * 一度の SOQL で対象 Lead を取得し、各 Scorer を呼び出してバルク update する。
     * @param leadIds 対象 Lead Id の集合
     */
    public static void calculateScores(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            return;
        }

        // 一度のクエリで属性スコア計算に必要な項目を取得
        Map<Id, Lead> leadMap = new Map<Id, Lead>([
            SELECT Id, Industry, NumberOfEmployees, Title, LeadSource
            FROM Lead
            WHERE Id IN :leadIds
            WITH SECURITY_ENFORCED
        ]);

        if (leadMap.isEmpty()) {
            return;
        }

        // 各 Scorer をバルクで呼び出し
        Map<Id, Decimal> attributeScores = LeadAttributeScorer.calculateBulk(leadMap.values());
        Map<Id, Decimal> behaviorScores  = LeadBehaviorScorer.calculateBulk(leadMap.keySet());
        Map<Id, Decimal> interestScores  = LeadInterestScorer.calculateBulk(leadMap.keySet());

        // 反映用の Lead リストを構築
        List<Lead> leadsToUpdate = new List<Lead>();
        for (Id leadId : leadMap.keySet()) {
            Decimal attributeScore = 0;
            if (attributeScores.containsKey(leadId)) {
                attributeScore = attributeScores.get(leadId);
            }
            Decimal behaviorScore = 0;
            if (behaviorScores.containsKey(leadId)) {
                behaviorScore = behaviorScores.get(leadId);
            }
            Decimal interestScore = 0;
            if (interestScores.containsKey(leadId)) {
                interestScore = interestScores.get(leadId);
            }
            Decimal totalScore = attributeScore + behaviorScore + interestScore;

            leadsToUpdate.add(new Lead(
                Id = leadId,
                Attribute_Score__c = attributeScore,
                Behavior_Score__c = behaviorScore,
                Interest_Score__c = interestScore,
                Score__c = totalScore,
                Lead_Category__c = determineCategory(totalScore),
                Score_Last_Calculated__c = System.now()
            ));
        }

        if (leadsToUpdate.isEmpty()) {
            return;
        }

        // 再帰防止フラグを立ててバルク update。flag は finally で必ず戻す。
        LeadTriggerHandler.bypassTrigger = true;
        try {
            update leadsToUpdate;
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR, 'LeadScoringService update error: ' + e.getMessage());
            throw e;
        } finally {
            LeadTriggerHandler.bypassTrigger = false;
        }
    }

    /**
     * 単一 Lead のスコアを計算し反映する。内部でバルクメソッドを呼び出す。
     * @param leadId 対象 Lead Id
     */
    public static void calculateScore(Id leadId) {
        if (leadId == null) {
            return;
        }
        calculateScores(new Set<Id>{ leadId });
    }

    /**
     * 最終スコアからカテゴリを判定する。閾値は LeadConstants から取得する。
     * @param score 最終スコア
     * @return カテゴリ（Hot / Warm / Cold / Low）。score が null の場合は Low。
     */
    public static String determineCategory(Decimal score) {
        if (score == null) {
            return LeadConstants.CATEGORY_LOW;
        }
        if (score >= LeadConstants.HOT_THRESHOLD) {
            return LeadConstants.CATEGORY_HOT;
        }
        if (score >= LeadConstants.WARM_THRESHOLD) {
            return LeadConstants.CATEGORY_WARM;
        }
        if (score >= LeadConstants.COLD_THRESHOLD) {
            return LeadConstants.CATEGORY_COLD;
        }
        return LeadConstants.CATEGORY_LOW;
    }
}
