/**
 * CampaignMember のトリガー。
 * ロジックは持たず、CampaignMemberTriggerHandler に委譲する薄いトリガー。
 * bypassTrigger が立っている場合は早期 return して再帰を防止する。
 */
trigger CampaignMemberTrigger on CampaignMember (after insert, after update, after delete, after undelete) {
    if (LeadTriggerHandler.bypassTrigger) {
        return;
    }

    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            CampaignMemberTriggerHandler.afterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            CampaignMemberTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete) {
            CampaignMemberTriggerHandler.afterDelete(Trigger.old);
        } else if (Trigger.isUndelete) {
            CampaignMemberTriggerHandler.afterUndelete(Trigger.new);
        }
    }
}
