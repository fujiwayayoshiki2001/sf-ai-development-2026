/**
 * Lead トリガーのハンドラ。
 *
 * LeadTrigger から各イベントごとに呼ばれ、内部でバリデーション（LeadValidator）と
 * スコア再計算（LeadScoringService）へ委譲する薄いハンドラ。
 *
 * イベントごとの責務:
 *  - beforeInsert / beforeUpdate : バリデーション（LeadValidator は Step 4 で実装）
 *  - afterInsert                 : 全リードのスコアを計算
 *  - afterUpdate                 : 属性関連項目が変わったリードのみ再計算
 *
 * スコア反映時の再帰呼び出しは bypassTrigger フラグで抑止する。
 */
public with sharing class LeadTriggerHandler {

    /**
     * 再帰トリガー防止フラグ。
     * LeadScoringService がスコア反映のために Lead を update する際、true にセットして
     * トリガーの再発火を抑止する。テストからのアクセスを許可するため @TestVisible とする。
     */
    @TestVisible
    public static Boolean bypassTrigger = false;

    /**
     * before insert: 新規リードのバリデーション。
     * @param newLeads 挿入される Lead のリスト
     */
    public static void beforeInsert(List<Lead> newLeads) {
        if (bypassTrigger || newLeads == null || newLeads.isEmpty()) {
            return;
        }
        LeadValidator.validate(newLeads);
    }

    /**
     * before update: 更新リードのバリデーション。
     * @param newLeads 更新後の Lead のリスト
     * @param oldMap   更新前の Lead Map
     */
    public static void beforeUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        if (bypassTrigger || newLeads == null || newLeads.isEmpty()) {
            return;
        }
        LeadValidator.validate(newLeads);
    }

    /**
     * after insert: 全リードのスコアを計算する。
     * @param newLeads 挿入された Lead のリスト
     * @param newMap   挿入された Lead Map（Id 取得用）
     */
    public static void afterInsert(List<Lead> newLeads, Map<Id, Lead> newMap) {
        if (bypassTrigger || newMap == null || newMap.isEmpty()) {
            return;
        }
        LeadScoringService.calculateScores(newMap.keySet());
    }

    /**
     * after update: 属性関連項目が変わったリードのみスコアを再計算する。
     * @param newLeads 更新後の Lead のリスト
     * @param oldMap   更新前の Lead Map
     * @param newMap   更新後の Lead Map
     */
    public static void afterUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap, Map<Id, Lead> newMap) {
        if (bypassTrigger || newLeads == null || newLeads.isEmpty()) {
            return;
        }

        Set<Id> leadsToRecalc = new Set<Id>();
        for (Lead newLead : newLeads) {
            Lead oldLead = null;
            if (oldMap != null) {
                oldLead = oldMap.get(newLead.Id);
            }
            if (oldLead == null || isAttributeChanged(oldLead, newLead)) {
                leadsToRecalc.add(newLead.Id);
            }
        }

        if (!leadsToRecalc.isEmpty()) {
            LeadScoringService.calculateScores(leadsToRecalc);
        }
    }

    /**
     * 属性スコアに影響する項目（Industry / NumberOfEmployees / Title / LeadSource）が
     * 変更されたかを判定する。
     * @param oldLead 更新前の Lead
     * @param newLead 更新後の Lead
     * @return いずれかの属性項目が変わっていれば true
     */
    private static Boolean isAttributeChanged(Lead oldLead, Lead newLead) {
        return oldLead.Industry != newLead.Industry
            || oldLead.NumberOfEmployees != newLead.NumberOfEmployees
            || oldLead.Title != newLead.Title
            || oldLead.LeadSource != newLead.LeadSource;
    }
}
