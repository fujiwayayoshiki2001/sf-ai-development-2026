/**
 * Lead_Interest__c トリガーのハンドラ。
 *
 * LeadInterestTrigger から各イベントごとに呼ばれ、興味レコードの変更に応じて
 * 紐づく Lead のスコアを LeadScoringService へ委譲して再計算する薄いハンドラ。
 *
 * イベントごとの責務:
 *  - afterInsert / afterUndelete : 新規（復元）レコードの親 Lead を再計算
 *  - afterUpdate                 : 新親に加え、付け替え元（旧親）も再計算対象に含める
 *  - afterDelete                 : 削除されたレコードの（旧）親 Lead を再計算
 *
 * Lead__c は任意 Lookup のため、Lead__c が null のレコードは対象外とする。
 * スコア反映時の再帰呼び出しは LeadTriggerHandler.bypassTrigger フラグで抑止する
 * （LeadTrigger / LeadTriggerHandler と同一のパターン）。
 */
public with sharing class LeadInterestTriggerHandler {

    /**
     * after insert: 挿入された興味レコードの親 Lead を再計算する。
     * @param newInterests 挿入された Lead_Interest__c のリスト
     */
    public static void afterInsert(List<Lead_Interest__c> newInterests) {
        if (LeadTriggerHandler.bypassTrigger || newInterests == null || newInterests.isEmpty()) {
            return;
        }
        recalculate(collectLeadIds(newInterests));
    }

    /**
     * after update: 更新後の親 Lead と、付け替え元（更新前の親）の双方を再計算する。
     * @param newInterests 更新後の Lead_Interest__c のリスト
     * @param oldMap       更新前の Lead_Interest__c Map
     */
    public static void afterUpdate(List<Lead_Interest__c> newInterests, Map<Id, Lead_Interest__c> oldMap) {
        if (LeadTriggerHandler.bypassTrigger || newInterests == null || newInterests.isEmpty()) {
            return;
        }
        Set<Id> leadIds = collectLeadIds(newInterests);
        if (oldMap != null) {
            leadIds.addAll(collectLeadIds(oldMap.values())); // 付け替え元（旧親）も再計算対象に
        }
        recalculate(leadIds);
    }

    /**
     * after delete: 削除された興味レコードの（旧）親 Lead を再計算する。
     * @param oldInterests 削除された Lead_Interest__c のリスト
     */
    public static void afterDelete(List<Lead_Interest__c> oldInterests) {
        if (LeadTriggerHandler.bypassTrigger || oldInterests == null || oldInterests.isEmpty()) {
            return;
        }
        recalculate(collectLeadIds(oldInterests));
    }

    /**
     * after undelete: 復元された興味レコードの親 Lead を再計算する。
     * @param newInterests 復元された Lead_Interest__c のリスト
     */
    public static void afterUndelete(List<Lead_Interest__c> newInterests) {
        if (LeadTriggerHandler.bypassTrigger || newInterests == null || newInterests.isEmpty()) {
            return;
        }
        recalculate(collectLeadIds(newInterests));
    }

    /**
     * 興味レコード群から、null でない親 Lead Id を集める。
     * @param interests 対象の Lead_Interest__c リスト
     * @return 親 Lead Id の集合
     */
    private static Set<Id> collectLeadIds(List<Lead_Interest__c> interests) {
        Set<Id> leadIds = new Set<Id>();
        for (Lead_Interest__c interest : interests) {
            if (interest.Lead__c != null) {
                leadIds.add(interest.Lead__c);
            }
        }
        return leadIds;
    }

    /**
     * 対象 Lead Id 集合が空でなければスコアを再計算する。
     * @param leadIds 再計算対象の Lead Id 集合
     */
    private static void recalculate(Set<Id> leadIds) {
        if (!leadIds.isEmpty()) {
            LeadScoringService.calculateScores(leadIds);
        }
    }
}
