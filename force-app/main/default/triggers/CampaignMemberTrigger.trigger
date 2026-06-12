/**
 * CampaignMember のトリガー。
 * キャンペーン参加の変更に応じて、紐づく Lead の（行動）スコアを再計算する。
 * CampaignMember は Lead または Contact に紐づくが、Contact 経由（LeadId が null）の
 * メンバーは対象外とする。
 */
trigger CampaignMemberTrigger on CampaignMember (after insert, after update, after delete, after undelete) {
    Set<Id> leadIds = new Set<Id>();

    if (Trigger.isDelete) {
        for (CampaignMember member : Trigger.old) {
            if (member.LeadId != null) {
                leadIds.add(member.LeadId);
            }
        }
    } else {
        // insert / update / undelete
        for (CampaignMember member : Trigger.new) {
            if (member.LeadId != null) {
                leadIds.add(member.LeadId);
            }
        }
    }

    if (!leadIds.isEmpty()) {
        LeadScoringService.calculateScores(leadIds);
    }
}
