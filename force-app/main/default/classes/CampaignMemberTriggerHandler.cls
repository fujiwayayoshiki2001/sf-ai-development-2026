/**
 * CampaignMember トリガーのハンドラ。
 *
 * CampaignMemberTrigger から各イベントごとに呼ばれ、キャンペーン参加の変更に応じて
 * 紐づく Lead の（行動）スコアを LeadScoringService へ委譲して再計算する薄いハンドラ。
 *
 * イベントごとの責務:
 *  - afterInsert / afterUndelete : 新規（復元）メンバーの Lead を再計算
 *  - afterUpdate                 : 更新後の Lead に加え、付け替え元（旧 LeadId）も再計算対象に含める
 *  - afterDelete                 : 削除されたメンバーの（旧）Lead を再計算
 *
 * CampaignMember は Lead または Contact に紐づくため、Contact 経由（LeadId が null）の
 * メンバーは対象外とする。
 * スコア反映時の再帰呼び出しは LeadTriggerHandler.bypassTrigger フラグで抑止する
 * （LeadTrigger / LeadTriggerHandler と同一のパターン）。
 */
public with sharing class CampaignMemberTriggerHandler {

    /**
     * after insert: 挿入されたメンバーの Lead を再計算する。
     * @param newMembers 挿入された CampaignMember のリスト
     */
    public static void afterInsert(List<CampaignMember> newMembers) {
        if (LeadTriggerHandler.bypassTrigger || newMembers == null || newMembers.isEmpty()) {
            return;
        }
        recalculate(collectLeadIds(newMembers));
    }

    /**
     * after update: 更新後の Lead と、付け替え元（更新前の LeadId）の双方を再計算する。
     * @param newMembers 更新後の CampaignMember のリスト
     * @param oldMap     更新前の CampaignMember Map
     */
    public static void afterUpdate(List<CampaignMember> newMembers, Map<Id, CampaignMember> oldMap) {
        if (LeadTriggerHandler.bypassTrigger || newMembers == null || newMembers.isEmpty()) {
            return;
        }
        Set<Id> leadIds = collectLeadIds(newMembers);
        if (oldMap != null) {
            leadIds.addAll(collectLeadIds(oldMap.values())); // 付け替え元（旧 LeadId）も再計算対象に
        }
        recalculate(leadIds);
    }

    /**
     * after delete: 削除されたメンバーの（旧）Lead を再計算する。
     * @param oldMembers 削除された CampaignMember のリスト
     */
    public static void afterDelete(List<CampaignMember> oldMembers) {
        if (LeadTriggerHandler.bypassTrigger || oldMembers == null || oldMembers.isEmpty()) {
            return;
        }
        recalculate(collectLeadIds(oldMembers));
    }

    /**
     * after undelete: 復元されたメンバーの Lead を再計算する。
     * @param newMembers 復元された CampaignMember のリスト
     */
    public static void afterUndelete(List<CampaignMember> newMembers) {
        if (LeadTriggerHandler.bypassTrigger || newMembers == null || newMembers.isEmpty()) {
            return;
        }
        recalculate(collectLeadIds(newMembers));
    }

    /**
     * メンバー群から、null でない LeadId を集める（Contact 経由はスキップ）。
     * @param members 対象の CampaignMember リスト
     * @return Lead Id の集合
     */
    private static Set<Id> collectLeadIds(List<CampaignMember> members) {
        Set<Id> leadIds = new Set<Id>();
        for (CampaignMember member : members) {
            if (member.LeadId != null) {
                leadIds.add(member.LeadId);
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
