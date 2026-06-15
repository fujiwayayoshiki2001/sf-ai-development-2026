/**
 * Lead_Interest__c のトリガー。
 * ロジックは持たず、LeadInterestTriggerHandler に委譲する薄いトリガー。
 * bypassTrigger が立っている場合は早期 return して再帰を防止する。
 */
trigger LeadInterestTrigger on Lead_Interest__c (after insert, after update, after delete, after undelete) {
    if (LeadTriggerHandler.bypassTrigger) {
        return;
    }

    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            LeadInterestTriggerHandler.afterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            LeadInterestTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete) {
            LeadInterestTriggerHandler.afterDelete(Trigger.old);
        } else if (Trigger.isUndelete) {
            LeadInterestTriggerHandler.afterUndelete(Trigger.new);
        }
    }
}
